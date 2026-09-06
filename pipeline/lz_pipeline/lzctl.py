"""lzctl - landing-zone runner.

Wraps the operational lifecycle around the generated Terraform envs: ordered
plans/applies with lock + state backup + plan triage, drift sweeps, import
helper, and preflight for the environment mistakes that otherwise surface as
cryptic mid-apply errors.

Standalone by design: stdlib only, no pipeline imports - this file (plus
plan_triage.py next to it and the envs tree's deps.json) ships inside the
customer handover artifact. Pipeline-side commands (build/validate/docs) exist
only where the pipeline is installed and say so otherwise.

Usage (lifecycle order):
    lzctl intake       FILLED_QUESTIONNAIRE.xlsx [-o dump.json]
    lzctl assess       DUMP.json --customer <id> [--workspace <dir>] [--force]
    lzctl set          --spec SPEC.json --field PATH (--value V | --json J | --null)
    lzctl validate     SPEC.json            (alias: spec-validate)
    lzctl build        --spec SPEC.json --envs-dir <envs> [--scaffold-dir <dir>]
    lzctl preflight    --envs-dir <envs>
    lzctl plan         --envs-dir <envs> [ENV[,ENV...] | --all] [--dry-run]
    lzctl apply        --envs-dir <envs> [ENV[,ENV...] | --all] [--dry-run]
                       [--allow-destroy] [--yes] [--destroy-confirm ENV]
    lzctl verify       --envs-dir <envs> [ENV[,ENV...]] [--report out.md]
    lzctl report       --envs-dir <envs> [--out <dir>]
    lzctl drift        --envs-dir <envs> [ENV[,ENV...]] [--report out.md]
    lzctl adopt        --envs-dir <envs> ENV ADDRESS CLOUD_ID
    lzctl state-backup --envs-dir <envs> [ENV | --all]
    lzctl triage       PLAN_JSON [...]
    lzctl who-changed  RESOURCE_NAME
    lzctl order        --envs-dir <envs>
    lzctl check        [CHECK]              (regression harness)

Exit codes follow terraform's plan convention where relevant:
0 ok / no changes, 2 changes present, 3 destructive changes present
(or blocked by a content gate), 4 refused: this context cannot satisfy
a required confirmation (agent session, or no terminal for a prompt).
"""

import argparse
import datetime
import getpass
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

# Terraform emits box-drawing/arrow characters; a piped stdout on Windows
# defaults to cp1252 and would raise UnicodeEncodeError mid-stream.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import plan_triage  # shipped next to lzctl.py in the artifact
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parent / "tools"))
    import plan_triage

REQUIRED_ENV = {
    "AWS_ACCESS_KEY_ID": None,
    "AWS_SECRET_ACCESS_KEY": None,
    "AWS_REQUEST_CHECKSUM_CALCULATION": "when_required",
    "AWS_RESPONSE_CHECKSUM_VALIDATION": "when_required",
}
MIN_TF = (1, 6, 3)
LOCK_STALE_S = 2 * 3600  # ponytail: per-env refresh keeps live runs fresh; a SINGLE env apply >2h can still look stale - add mid-env refreshing if one ever runs that long
PRICING_PATH = None   # --pricing override; default card sits next to plan_triage


# ────────────────────────────────────────────────────────────────────────────
# Shared plumbing
# ────────────────────────────────────────────────────────────────────────────

def env_dirs(envs: Path):
    return sorted(p for p in envs.iterdir() if p.is_dir() and re.match(r"^\d{2}-", p.name))


def apply_order(envs: Path):
    deps = envs / "deps.json"
    if deps.exists():
        doc = json.loads(deps.read_text(encoding="utf-8"))
        order = doc.get("apply_order")
        if order:
            return [e for e in order if (envs / e).is_dir()]
    return [d.name for d in env_dirs(envs)]


def select(envs: Path, target, all_: bool):
    """Resolve ENV[,ENV...] (exact or unique prefix per token) or --all.
    Multi-selections always run in apply order regardless of token order."""
    if all_:
        return apply_order(envs)
    if not target:
        print("specify an ENV (comma-separate for several) or --all", file=sys.stderr)
        sys.exit(2)
    chosen = []
    for tok in (t.strip() for t in str(target).split(",") if t.strip()):
        matches = [d.name for d in env_dirs(envs)
                   if d.name == tok or d.name.startswith(tok)]
        if len(matches) != 1:
            print(f"ambiguous or unknown env {tok!r}: {matches}", file=sys.stderr)
            sys.exit(2)
        if matches[0] not in chosen:
            chosen.append(matches[0])
    order = apply_order(envs)
    return sorted(chosen, key=order.index)


def run_tf(env_dir: Path, args, dry, log=None, **kw):
    """Run terraform, STREAMING its output live (console + log) so long
    refreshes show progress. Returns a CompletedProcess whose stdout holds
    the output tail (stderr is merged into the stream)."""
    cmd = ["terraform"] + args
    line = f"[{env_dir.name}] $ {' '.join(cmd)}"
    print(line, flush=True)
    if log:
        log.write(line + "\n")
    if dry:
        return subprocess.CompletedProcess(cmd, 0, "", "")
    p = subprocess.Popen(cmd, cwd=str(env_dir), stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace", **kw)
    tail = []
    for out in p.stdout:
        print(out.rstrip("\n"), flush=True)
        if log:
            log.write(out)
        tail.append(out)
        if len(tail) > 300:
            tail.pop(0)
    p.wait()
    return subprocess.CompletedProcess(cmd, p.returncode, "".join(tail), "")


def logfile(envs: Path, name: str):
    d = envs / "lzctl-logs"
    d.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    return (d / f"{ts}-{name}.log").open("w", encoding="utf-8")


class Lock:
    """Advisory machine-local lock: one apply at a time against this tree.
    (There is no remote state locking on the OBS backend; CI concurrency
    groups remain the authoritative serializer across machines.)"""

    def __init__(self, envs: Path):
        self.path = envs / ".lzctl.lock"

    def acquire(self, dry=False):
        if self.path.exists():
            try:
                info = json.loads(self.path.read_text(encoding="utf-8"))
            except ValueError:
                info = {}
            age = time.time() - info.get("time", 0)
            holder = f"{info.get('user','?')}@{info.get('host','?')} pid {info.get('pid','?')}"
            if age < LOCK_STALE_S:
                raise SystemExit(f"lock held by {holder} ({int(age)}s ago) - "
                                 f"one apply at a time; remove {self.path} only if that run is dead")
            # Auto-break only a lock WE could plausibly verify: same host.
            # A live holder refreshes its timestamp per env, so a genuinely
            # active run never looks stale for long. A foreign host's lock
            # cannot be liveness-checked from here - require manual removal.
            if info.get("host") not in ("?", None, socket.gethostname()):
                raise SystemExit(
                    f"STALE lock from another host ({holder}, {int(age)}s old) - "
                    f"verify that run is dead, then remove {self.path} manually")
            print(f"note: breaking STALE lock ({holder}, {int(age)}s old)")
            if not dry:
                self.path.unlink(missing_ok=True)
        if not dry:
            # atomic exclusive create: two simultaneous acquires cannot both win
            try:
                with open(self.path, "x", encoding="utf-8") as f:
                    f.write(self._payload())
            except FileExistsError:
                raise SystemExit(f"lock grabbed concurrently by another process - "
                                 f"one apply at a time ({self.path})")

    def _payload(self):
        return json.dumps({"user": getpass.getuser(), "host": socket.gethostname(),
                           "pid": os.getpid(), "time": time.time()})

    def _owned(self):
        try:
            info = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return False
        return (info.get("pid") == os.getpid()
                and info.get("host") == socket.gethostname())

    def refresh(self, dry=False):
        """Re-stamp the timestamp so a long multi-env apply never crosses the
        stale threshold while genuinely running (called between envs)."""
        if not dry and self.path.exists() and self._owned():
            self.path.write_text(self._payload(), encoding="utf-8")

    def release(self, dry=False):
        # owner-checked: never delete a lock a newer process now holds
        if not dry and self.path.exists() and self._owned():
            self.path.unlink()


def triage_plan(env_dir: Path, dry: bool, log, plan_file="tf.plan") -> tuple:
    """(exit_class, buckets) from the plan file just written: 0/2/3."""
    if dry:
        return 0, None
    r = subprocess.run(["terraform", "show", "-json", plan_file],
                       cwd=str(env_dir), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print(f"  triage: terraform show failed ({r.stderr[:200]})")
        return 2, None
    plan_json = json.loads(r.stdout)
    buckets = plan_triage.triage(plan_json)
    print(plan_triage.report(env_dir.name, buckets))
    cost = plan_triage.cost_report(env_dir.name, plan_json,
                                   plan_triage.load_pricing(PRICING_PATH))
    if cost:
        print(cost)
    if log:
        log.write(plan_triage.report(env_dir.name, buckets) + "\n")
        if cost:
            log.write(cost + "\n")
    if buckets["destructive"]:
        return 3, buckets
    if any(buckets.values()):
        return 2, buckets
    return 0, buckets


# ────────────────────────────────────────────────────────────────────────────
# Verbs
# ────────────────────────────────────────────────────────────────────────────

_PSK_PLACEHOLDER = ("var.", "secret", "tbd", "<", "replace_with", "${")


def psk_problems(envs: Path):
    """VPN connections whose EFFECTIVE psk (terraform.tfvars.json, then
    *.auto.tfvars.json overrides in terraform's load order) is blank, a
    reference, or a placeholder. LZR-027 keeps literal PSKs out of the SPEC;
    this gate keeps non-values out of the DEPLOYMENT - terraform would use
    the literal placeholder text as the live tunnel key."""
    out = []
    for env_dir in env_dirs(envs):
        conns = None
        files = [env_dir / "terraform.tfvars.json"] + sorted(env_dir.glob("*.auto.tfvars.json"))
        for p in files:
            if not p.exists():
                continue
            try:
                doc = json.loads(p.read_text(encoding="utf-8"))
            except ValueError:
                continue
            if isinstance(doc.get("connections"), list):
                conns = doc["connections"]
        if not conns:
            continue
        bad = [str(c.get("name") or "?") for c in conns if isinstance(c, dict)
               and (not str(c.get("psk") or "").strip()
                    or str(c["psk"]).strip().lower().startswith(_PSK_PLACEHOLDER))]
        if bad:
            out.append(f"{env_dir.name}: VPN connection(s) {', '.join(bad)} have a "
                       "blank/placeholder psk - put the real PSK in the env's gitignored "
                       "secrets override (*.auto.tfvars.json) before apply")
    return out


# ────────────────────────────────────────────────────────────────────────────
# Phase status: where this workspace is on the graph, derived from artifacts
#
# Nothing here is remembered. Every phase's state is recomputed from what is
# on disk, so the report cannot drift from reality the way a stored pointer
# would - and editing the spec automatically makes everything downstream
# STALE without anyone having to declare it.
#
# The canonical graph is schemas/phases.json; this table restates the parts a
# progress report needs. tests/unit/test_doctrine_sync.py fails if they drift.
# ────────────────────────────────────────────────────────────────────────────

PHASES = ("intake", "design", "build", "verify_pre", "deploy", "verify_post", "deliver")

PHASE_DOC = {
    "intake": dict(
        gist="turn the questionnaire into a draft",
        summary="Turn a requirement source into a neutral draft spec plus the decisions agenda.",
        who="agent", cloud="none",
        reversible="re-run assess --force"),
    "design": dict(
        gist="resolve decisions, validate clean",
        summary="Interpret answers into the spec, resolve every OPEN decision, validate clean.",
        who="agent drafts, human approves", cloud="none",
        reversible="the spec is a reviewable diff"),
    "build": dict(
        gist="generate the env tree",
        summary="Generate the env tree (tfvars + *.generated.tf) and a fresh deps.json.",
        who="agent", cloud="none",
        reversible="regenerate or delete the tree"),
    "verify_pre": dict(
        gist="prove the tree before it touches anything",
        summary="Prove the tree before it touches anything: harness, preflight, ordered plans, triage.",
        who="agent", cloud="read-only (plan)",
        reversible="plans write nothing"),
    "deploy": dict(
        gist="apply in dependency order",
        summary="Apply in dependency order, with a state backup and a reviewed plan per env.",
        who="HUMAN at a terminal", cloud="WRITES",
        reversible="per-resource; account + PoC EP creation never"),
    "verify_post": dict(
        gist="re-plan every env",
        summary="Re-plan everything: every env clean or known-benign, or the apply left it inconsistent.",
        who="agent", cloud="read-only (plan)",
        reversible="read-only"),
    "deliver": dict(
        gist="package evidence, docs and artifact",
        summary="Package the evidence bundle, the generated documents, and the handover artifact.",
        who="agent", cloud="none",
        reversible="regenerate"),
}


_REL_BASE = None      # workspace root, so a report prints paths a human can retype


def _rel(p):
    """Workspace-relative path, or the absolute one when it lies outside."""
    if p is None:
        return "-"
    p = Path(p)
    if _REL_BASE:
        try:
            return str(p.resolve().relative_to(_REL_BASE)).replace("\\", "/")
        except ValueError:
            pass
    return str(p)


def _n(count, word, plural=None):
    """'1 snapshot' / '2 snapshots'. Cheap, but '(s)' reads like a placeholder
    nobody finished."""
    return f"{count} {word if count == 1 else (plural or word + 's')}"


def _mtime(p: Path):
    try:
        return p.stat().st_mtime
    except OSError:
        return None


def _newest(paths):
    times = [t for t in (_mtime(p) for p in paths) if t is not None]
    return max(times) if times else None


def _logs(envs: Path, kind: str):
    d = envs / "lzctl-logs"
    return sorted(d.glob(f"*-{kind}.log")) if d.is_dir() else []


def _find_spec(explicit, cwd: Path):
    if explicit:
        return Path(explicit).resolve()
    for d in (cwd / "specs", cwd / "lz_spec", cwd):
        if not d.is_dir():
            continue
        cands = [p for p in sorted(d.glob("lz.spec.*.json"))
                 if not p.name.endswith((".decisions.json", ".schema.json", ".journal.jsonl"))]
        if len(cands) == 1:
            return cands[0].resolve()
        if len(cands) > 1:
            return cands  # ambiguous: caller reports the choice
    return None


def _workspace_root(spec_path, cwd: Path):
    """The workspace a spec belongs to - its own tree, not whatever directory
    the command was launched from. `specs/` is where `assess` writes."""
    if not isinstance(spec_path, Path):
        return cwd
    d = spec_path.parent
    return d.parent if d.name in ("specs", "lz_spec") else d


def _find_envs(explicit, cwd: Path, spec=None):
    """The env tree belonging to this spec's workspace, or None.

    Never borrows one from elsewhere: reporting THIS repo's example tree as a
    customer's build artifacts turned "nothing generated yet" into "12 envs
    built". The example tree is only the answer when the workspace IS this
    checkout.
    """
    if explicit:
        return Path(explicit).resolve()
    root = _workspace_root(spec, cwd)
    cands = [p for p in sorted(root.glob("envs*"))
             if p.is_dir() and any(re.match(r"^\d{2}-", c.name) for c in p.iterdir() if c.is_dir())]
    if len(cands) == 1:
        return cands[0].resolve()
    tf = root / "terraform" / "envs-example"
    if tf.is_dir() and root.resolve() == Path(__file__).resolve().parents[2]:
        return tf.resolve()
    return None


def _decisions_status(spec_path: Path):
    """(blocking, open, note) for a spec's decisions gate - stdlib only, same
    rule `lzctl build` enforces."""
    if spec_path is None or not spec_path.exists():
        return (0, 0, "no spec")
    try:
        ir = json.loads(spec_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return (0, 0, f"unreadable spec ({e})")
    prov = ir.get("provenance") or {}
    dec = spec_path.with_name(prov.get("decisions_file")
                              or (spec_path.stem + ".decisions.json"))
    if not dec.exists():
        return (0, 0, "no decisions file (spec has no questionnaire lineage)")
    doc = json.loads(dec.read_text(encoding="utf-8"))
    items = doc.get("items") or []
    open_items = [i for i in items if i.get("state") == "OPEN"]
    blocking = [i for i in open_items if not isinstance(i.get("resolution"), dict)]
    note = f"{dec.name}: {len(blocking)} blocking of {len(open_items)} open"
    if prov.get("decision_set_sha256") and \
            _decision_set_sha256(items) != prov["decision_set_sha256"]:
        return (max(1, len(blocking)), len(open_items),
                note + " - DECISION SET ALTERED (build will refuse)")
    return (len(blocking), len(open_items), note)


def _validate_status(spec_path: Path):
    """(errors, warnings, note). Runs the real validator so status can never
    disagree with the gate; unavailable in a runtime-only install."""
    if spec_path is None or not spec_path.exists():
        return (None, None, "no spec")
    r = subprocess.run([sys.executable, "-X", "utf8", "-m", "lz_pipeline",
                        "spec-validate", str(spec_path)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    m = re.search(r"validate: (\d+) error\(s\), (\d+) warning\(s\)", r.stdout or "")
    if not m:
        return (None, None, "validator unavailable (runtime-only install)")
    return (int(m.group(1)), int(m.group(2)),
            f"{_n(int(m.group(1)), 'error')}, {_n(int(m.group(2)), 'warning')}")


def phase_report(spec_path, envs, deep=True):
    """Every phase's state, derived from artifacts. Never reads a stored
    pointer: `status` after a crash is as accurate as `status` after a
    clean run."""
    ph = {p: dict(state="todo", artifacts=[], blockers=[], notes=[],
                  inputs=[], next=None) for p in PHASES}
    spec_mtime = _mtime(spec_path) if spec_path else None

    # ── intake ──────────────────────────────────────────────────────────
    p = ph["intake"]
    if spec_path is None:
        p["blockers"].append("no spec found - pass --spec, or run `lzctl intake` + `lzctl assess`")
        p["inputs"].append("a filled questionnaire (xlsx), an LLD, or a described target")
        p["next"] = "lzctl intake <filled.xlsx> -o dump.json  &&  lzctl assess dump.json --customer <id>"
    else:
        p["artifacts"].append((True, f"spec drafted ({_rel(spec_path)})"))
        dec = spec_path.with_name(spec_path.stem + ".decisions.json")
        p["artifacts"].append((dec.exists(),
                               f"decisions file present ({dec.name})" if dec.exists()
                               else "no decisions file (not questionnaire-derived)"))
        p["state"] = "done"
        if not dec.exists():
            p["notes"].append("no decisions file: this spec did not come from a questionnaire, "
                              "so there is no intake gate to clear")

    # ── design ──────────────────────────────────────────────────────────
    p = ph["design"]
    blocking, n_open, dec_note = _decisions_status(spec_path)
    errors = warnings = None
    if spec_path is not None:
        p["notes"].append(dec_note)
        if deep:
            errors, warnings, val_note = _validate_status(spec_path)
            p["notes"].append("validate: " + val_note)
        else:
            p["notes"].append("validate: not run (--quick) - phase state assumes it would pass")
        if blocking:
            p["blockers"].append(f"{_n(blocking, 'OPEN decision')} without a resolution "
                                 "- `lzctl build` exits 3 until each records who decided and why")
            p["inputs"].append("a resolution per open decision (the app's Decisions & gaps view)")
        if errors:
            p["blockers"].append(f"{_n(errors, 'validation error')} - run `lzctl validate` for the list")
            p["inputs"].append("the values the validator names (placeholders included: LZR-032)")
        # errors is None when the validator did not run (--quick, or a
        # runtime-only install): unknown is not the same as failing, so the
        # phase is judged on what WAS checked and the note says so.
        if ph["intake"]["state"] == "done" and not blocking and not errors:
            p["state"] = "done"
        p["next"] = f"lzctl validate {_rel(spec_path)}" if (errors or blocking) else None

    # ── build ───────────────────────────────────────────────────────────
    p = ph["build"]
    tfvars, oldest_tfvars = [], None
    if envs and envs.is_dir():
        tfvars = sorted(envs.glob("*/terraform.tfvars.json"))
        times = [t for t in (_mtime(f) for f in tfvars) if t is not None]
        oldest_tfvars = min(times) if times else None
        deps = envs / "deps.json"
        p["artifacts"].append((bool(tfvars),
                               f"terraform.tfvars.json present in all {_n(len(tfvars), 'env')}"
                               if tfvars else "terraform.tfvars.json missing - nothing generated yet"))
        p["artifacts"].append((deps.exists(),
                               "deps.json present" if deps.exists() else "deps.json missing"))
        if tfvars and deps.exists():
            p["state"] = "done"
            if spec_mtime and oldest_tfvars and spec_mtime > oldest_tfvars:
                # Timestamps are a HINT, not proof: a spec edit that touches
                # four envs leaves the other nine correct but older. Err
                # toward "re-verify" and name the check that settles it -
                # regen-diff regenerates and compares bytes.
                behind = sum(1 for f in tfvars
                             if (_mtime(f) or 0) < spec_mtime)
                p["state"] = "stale"
                p["blockers"].append(
                    f"the spec is newer than {behind} of {len(tfvars)} envs - the tree may "
                    "not match it. Timestamps only suggest that; regeneration proves it")
                p["next"] = (
                    f"lzctl check regen-diff --envs-dir {_rel(envs)} "
                    f"--spec {_rel(spec_path) if spec_path else '<spec>'}"
                    "   ->   lzctl build ...   # only if regen-diff reports differences")
        elif tfvars and not deps.exists():
            p["blockers"].append("deps.json missing - preflight fails and apply order falls "
                                 "back to numeric prefix (`lzctl deps --envs-dir " + _rel(envs) + "`)")
    else:
        p["artifacts"].append((False, "no env tree generated yet"))
    if p["state"] in ("todo", "stale") and not p["next"]:
        p["next"] = (f"lzctl build --spec {_rel(spec_path) if spec_path else '<spec>'} "
                     f"--envs-dir {_rel(envs) if envs else '<envs>'}"
                     + ("" if (envs and envs.is_dir()) else " --scaffold-dir terraform/scaffold"))

    # ── verify_pre ──────────────────────────────────────────────────────
    p = ph["verify_pre"]
    if envs and envs.is_dir():
        plans = sorted(envs.glob("*/tf.plan"))
        newest_plan = _newest(plans)
        p["artifacts"].append((bool(plans),
                               f"{len(plans)} of {len(tfvars) or len(plans)} envs planned"
                               if plans else "no env planned yet"))
        plan_logs = _logs(envs, "plan")
        p["artifacts"].append((bool(plan_logs),
                               f"{_n(len(plan_logs), 'plan run')} logged"
                               if plan_logs else "no plan run logged"))
        if plans and len(plans) >= len(tfvars) and newest_plan:
            p["state"] = "done"
            if oldest_tfvars and newest_plan < oldest_tfvars:
                p["state"] = "stale"
                p["blockers"].append("plans are older than the generated tree - re-plan before "
                                     "apply (a plan file is only a claim about the tree it came from)")
        elif plans:
            p["notes"].append(f"{len(plans)}/{len(tfvars)} envs planned")
        if ph["build"]["state"] == "stale":
            p["state"] = "stale"
            p["notes"].append("Recheck follows build: regenerate first, then re-plan. "
                              "Planning from a tree that no longer matches the spec is a "
                              "forbidden transition.")
    if p["state"] in ("todo", "stale"):
        p["inputs"].append("HW_ACCESS_KEY / HW_SECRET_KEY (or per-env secrets.auto.tfvars.json)")
        e = _rel(envs)
        p["next"] = (f"lzctl check all --envs-dir {e} --spec {spec_path.name if spec_path else '<spec>'}"
                     f"   ->   lzctl preflight --envs-dir {e}   ->   lzctl plan --envs-dir {e} --all")

    # ── deploy ──────────────────────────────────────────────────────────
    p = ph["deploy"]
    if envs and envs.is_dir():
        backups = sorted((envs / "state-backups").glob("*.tfstate.json")) \
            if (envs / "state-backups").is_dir() else []
        apply_logs = _logs(envs, "apply")
        p["artifacts"].append((bool(backups),
                               f"{_n(len(backups), 'state snapshot')} kept"
                               if backups else "no state backup taken"))
        p["artifacts"].append((bool(apply_logs),
                               f"{_n(len(apply_logs), 'apply run')} logged"
                               if apply_logs else "never applied from this tree"))
        if apply_logs:
            p["state"] = "done"
            last_apply = _newest(apply_logs)
            if oldest_tfvars and last_apply and last_apply < oldest_tfvars:
                p["state"] = "stale"
                p["notes"].append("the tree changed after the last apply - the estate no longer "
                                  "matches this configuration")
        lock = envs / ".lzctl.lock"
        if lock.exists():
            p["state"] = "blocked"
            p["blockers"].append(f"{_rel(lock)} present - an apply was interrupted. Do NOT re-apply "
                                 "blindly: read the newest lzctl-logs/*-apply.log, check "
                                 "state-backups/, then clear the lock deliberately")
            p["inputs"].append("a human decision on the interrupted run - resuming an apply is "
                               "never automatic")
            # A blocked phase still needs a next step: inspection, not apply.
            p["next"] = (f"read {_rel(envs)}/lzctl-logs/<newest>-apply.log and "
                         f"`lzctl verify --envs-dir {_rel(envs)}` to see what actually landed, "
                         f"BEFORE removing {_rel(lock)}")
            p["next_meta"] = dict(who="HUMAN - inspection first, then a deliberate decision",
                                  cloud="read-only (re-plan)",
                                  reversible="this step only looks")
    if p["state"] in ("todo", "stale"):
        p["who_note"] = True
        p["inputs"].append("a reviewed plan + a human at a terminal for the typed confirmation")
        p["next"] = f"lzctl apply --envs-dir {_rel(envs)} --all      # HUMAN runs this, never the agent"

    # ── verify_post ─────────────────────────────────────────────────────
    p = ph["verify_post"]
    if envs and envs.is_dir():
        drift_logs = _logs(envs, "drift")
        p["artifacts"].append((bool(drift_logs),
                               f"{_n(len(drift_logs), 'verification')} logged"
                               if drift_logs else "never verified"))
        last_apply = _newest(_logs(envs, "apply"))
        last_drift = _newest(drift_logs)
        if drift_logs and last_apply and last_drift and last_drift > last_apply:
            p["state"] = "done"
        elif drift_logs:
            p["notes"].append("the last verification predates the last apply - re-verify")
    if p["state"] == "todo" and ph["deploy"]["state"] == "done":
        p["next"] = f"lzctl verify --envs-dir {_rel(envs)}"

    # ── deliver ─────────────────────────────────────────────────────────
    p = ph["deliver"]
    if envs and envs.is_dir():
        ev = sorted((envs / "evidence").glob("*")) if (envs / "evidence").is_dir() else []
        p["artifacts"].append((bool(ev),
                               f"{_n(len(ev), 'evidence bundle')} built"
                               if ev else "no evidence bundle"))
        if ev:
            p["state"] = "done"
    if p["state"] == "todo" and ph["verify_post"]["state"] == "done":
        p["next"] = f"lzctl report --envs-dir {_rel(envs)}   ->   lzctl docs --envs-dir {_rel(envs)} --out-dir dist/docs"
    return ph


def _current_phase(ph):
    for name in PHASES:
        if ph[name]["state"] != "done":
            return name
    return PHASES[-1]


# ── Reporting ───────────────────────────────────────────────────────────────
#
# `status` reports FACTS; presentation is the caller's job. The agent renders
# the phase report into its own transcript (the format is specified in the
# huawei-cloud-landing-zone skill), so this file carries no colour, no box
# glyphs, and no terminal layout - just --json for a caller that formats, and
# a terse text form for a human who ran the command by hand.

STATE_WORD = {"done": "complete", "stale": "recheck", "blocked": "blocked", "todo": "pending"}
STATE_HINT = {
    "stale": "Timestamp hint only. Content may still match.",
    "blocked": "Something must be decided by a person before this can move.",
}


def _wrap(text, indent, hang=None, width=78):
    import textwrap
    return textwrap.fill(text, width=width, initial_indent=" " * indent,
                         subsequent_indent=" " * (indent if hang is None else hang),
                         break_long_words=False, break_on_hyphens=False)


def status_document(spec_path, envs, ph):
    """The phase report as data - the contract every caller formats from."""
    cur = _current_phase(ph)
    return {
        "customer": spec_path.stem.replace("lz.spec.", "") if spec_path else None,
        "spec": _rel(spec_path), "envs": _rel(envs),
        "complete": sum(1 for n in PHASES if ph[n]["state"] == "done"),
        "total": len(PHASES),
        "current": cur,
        "env_count": len(list(envs.glob("*/terraform.tfvars.json")))
                     if envs and envs.is_dir() else 0,
        "hints": [STATE_HINT[s] for s in ("stale", "blocked")
                  if any(ph[n]["state"] == s for n in PHASES)],
        "phases": [{
            "name": name,
            "state": ph[name]["state"],
            "status": STATE_WORD[ph[name]["state"]],
            "current": name == cur,
            "gist": PHASE_DOC[name]["gist"],
            "summary": PHASE_DOC[name]["summary"],
            "artifacts": [{"present": ok, "what": label}
                          for ok, label in ph[name]["artifacts"]],
            "blockers": ph[name]["blockers"],
            "notes": ph[name]["notes"],
            "needs": ph[name]["inputs"],
            "next": [x.strip() for x in re.split(r"\s+->\s+", ph[name]["next"])]
                    if ph[name]["next"] else [],
            "runner": (ph[name].get("next_meta") or PHASE_DOC[name])["who"],
            "cloud_access": (ph[name].get("next_meta") or PHASE_DOC[name])["cloud"],
            "undo": (ph[name].get("next_meta") or PHASE_DOC[name])["reversible"],
        } for name in PHASES],
        "remaining": [n for n in PHASES if ph[n]["state"] != "done"],
    }


def print_status(doc, verbose=False):
    """Terse text for a human at a prompt. Deliberately plain: the readable
    version of this report is the one the agent renders in its transcript."""
    print(f"{doc['customer'] or '(no spec)'}: {doc['complete']}/{doc['total']} complete"
          + (f", {_n(doc['env_count'], 'env')}" if doc["env_count"] else ""))
    print(f"  spec {doc['spec']}")
    print(f"  envs {doc['envs']}")
    print()
    width = max(len(p["name"]) for p in doc["phases"])
    for ph_ in doc["phases"]:
        mark = ">" if ph_["current"] else " "
        print(f"{mark} {ph_['name'].ljust(width)}  {ph_['status']}")
    for hint in doc["hints"]:
        print()
        print(f"  {hint}")

    for ph_ in doc["phases"]:
        if not verbose and not ph_["current"] and ph_["state"] not in ("stale", "blocked"):
            continue
        print()
        print(f"{ph_['name']} / {ph_['gist']}")
        for b in ph_["blockers"]:
            print(_wrap(f"! {b}", 2, hang=4))
        for n in ph_["notes"]:
            print(_wrap(n, 2))
        for a in ph_["artifacts"]:
            print(f"  [{'x' if a['present'] else ' '}] {a['what']}")
        for i in ph_["needs"]:
            print(_wrap(f"needs: {i}", 2, hang=4))
        for i, step in enumerate(ph_["next"], 1):
            lead = "  next: " if len(ph_["next"]) == 1 else f"  {i}. "
            print(lead + step)
        if ph_["next"]:
            print(_wrap(f"runner {ph_['runner']} | cloud {ph_['cloud_access']} "
                        f"| undo {ph_['undo']}", 2, hang=4))
    print()
    print(f"remaining: {', '.join(doc['remaining']) or 'none'}")


def cmd_status(args):
    global _REL_BASE
    cwd = Path(args.workspace or ".").resolve()
    _REL_BASE = cwd
    spec = _find_spec(getattr(args, "spec", None), cwd)
    if isinstance(spec, list):
        print("several specs found - pass --spec <path>:", file=sys.stderr)
        for s in spec:
            print(f"  {s}", file=sys.stderr)
        return 2
    envs = _find_envs(getattr(args, "envs_dir", None), cwd, spec)
    ph = phase_report(spec, envs, deep=not args.quick)
    doc = status_document(spec, envs, ph)
    doc["journal"] = _journal_entries(spec)

    if getattr(args, "json", False):
        print(json.dumps(doc, indent=2, ensure_ascii=False))
    else:
        print_status(doc, verbose=args.verbose)
        for e in doc["journal"][-3:]:
            print(f"  journal {e['at'].split('T')[0]} -> {e['phase']} "
                  f"({e['by']}): {e['reason']}")

    blocked = [n for n in PHASES if ph[n]["state"] == "blocked"]
    stale = [n for n in PHASES if ph[n]["state"] == "stale"]
    return 3 if blocked else (2 if stale else 0)


def _journal_entries(spec_path):
    j = _journal_path(spec_path)
    if not j or not j.exists():
        return []
    return [json.loads(x) for x in j.read_text(encoding="utf-8").splitlines() if x.strip()]


def _journal_path(spec_path):
    return spec_path.with_suffix(".journal.jsonl") if spec_path else None


def cmd_back(args):
    """Re-enter an earlier phase deliberately, and record WHY.  # noqa: D401

    This never undoes anything - it cannot: applied infrastructure is undone
    by Terraform under a human's typed confirmation, not by a status command.
    What it does is make the decision auditable, and say plainly what the
    re-entry invalidates. Staleness itself is DERIVED (edit the spec and the
    tree is stale whether or not anyone ran this), so the journal is the
    honest part: the reason, and who decided.
    """
    global _REL_BASE
    cwd = Path(args.workspace or ".").resolve()
    _REL_BASE = cwd
    spec = _find_spec(getattr(args, "spec", None), cwd)
    if isinstance(spec, list) or spec is None:
        print("need exactly one spec - pass --spec <path>", file=sys.stderr)
        return 2
    if args.phase not in PHASES:
        print(f"unknown phase {args.phase!r}; one of: {', '.join(PHASES)}", file=sys.stderr)
        return 2
    envs = _find_envs(getattr(args, "envs_dir", None), cwd, spec)
    ph = phase_report(spec, envs, deep=False)
    cur = _current_phase(ph)
    if PHASES.index(args.phase) >= PHASES.index(cur):
        print(f"already at or before {args.phase} (current: {cur}) - nothing to re-enter",
              file=sys.stderr)
        return 1

    invalidated = PHASES[PHASES.index(args.phase) + 1:]
    # "Has this ever been applied?" is evidence, not phase state: a deploy
    # blocked by an interrupted-apply lock has still touched the cloud.
    applied = bool(envs and envs.is_dir() and _logs(envs, "apply"))
    entry = {"at": datetime.datetime.now().isoformat(timespec="seconds"),
             "by": getattr(args, "by", None) or getpass.getuser(),
             "from_phase": cur, "phase": args.phase, "reason": args.reason,
             "invalidates": list(invalidated)}
    j = _journal_path(spec)
    with j.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry) + "\n")

    print(f"== re-entering {args.phase} (from {cur}) ==")
    print(f"   reason: {args.reason}")
    print(f"   logged: {_rel(j)}")
    print(f"\n   invalidates (must be redone in order): {', '.join(invalidated)}")
    print("   nothing was deleted. Re-running each phase regenerates its artifacts;")
    print("   `lzctl status` shows what is stale from here.")
    if applied:
        print("\n   WARNING: this estate is already APPLIED. Going back changes the")
        print("   CONFIGURATION only - the deployed resources stay exactly as they are.")
        print("   The next plan diffs your new configuration against live infrastructure,")
        print("   so read that plan as a change to production, not as a fresh install.")
        print("   Removing a resource from the spec plans a DESTROY. Triage before apply.")
    return 0


def cmd_preflight(args):
    envs = Path(args.envs_dir)
    problems = []
    checks = 0
    print("== preflight checks ==")
    tf = shutil.which("terraform")
    checks += 1
    if not tf:
        problems.append("terraform not on PATH")
    else:
        out = subprocess.run(["terraform", "version", "-json"], capture_output=True, text=True)
        try:
            ver = json.loads(out.stdout).get("terraform_version", "0")
            vt = tuple(int(x) for x in ver.split(".")[:3])
            if vt < MIN_TF:
                problems.append(f"terraform {ver} < required {'.'.join(map(str, MIN_TF))}")
            else:
                print(f"  PASS terraform {ver}")
        except (ValueError, KeyError):
            problems.append("could not parse terraform version")
    for k, want in REQUIRED_ENV.items():
        checks += 1
        v = os.environ.get(k)
        if not v:
            fix = f'set {k}={want}' if want else f"set {k}=<your master {'AK' if 'ACCESS_KEY_ID' in k else 'SK'}>"
            problems.append(f"env var {k} not set  ->  {fix}")
        elif want and v != want:
            problems.append(f"env var {k}={v!r} (must be {want!r} or state save fails AFTER apply)")
        else:
            print(f"  PASS {k}")
    checks += 1
    if not envs.exists():
        problems.append(f"envs dir not found: {envs}")
    elif not (envs / "deps.json").exists():
        problems.append(f"deps.json missing in {envs} (apply order falls back to numeric prefix)")
    else:
        print(f"  PASS deps.json ({len(apply_order(envs))} envs in order)")
    if envs.exists():
        checks += 1
        psk_bad = psk_problems(envs)
        if psk_bad:
            problems.extend(psk_bad)
        else:
            print("  PASS VPN psk values (real or no VPN connections)")
    for p in problems:
        print(f"  FAIL {p}")
    if problems:
        print(f"\n== RESULT: FAILED ({checks - len(problems)}/{checks} checks; {len(problems)} problem(s) above) ==")
    else:
        print(f"\n== RESULT: ALL PASSED ({checks}/{checks} checks) ==")
    return 1 if problems else 0


def cmd_order(args):
    envs = Path(args.envs_dir)
    for e in apply_order(envs):
        print(e)
    return 0


def _plan_one(env_dir: Path, dry: bool, log) -> int:
    if not (env_dir / ".terraform").exists() and not dry:
        init_args = ["init", "-input=false"]
        if (env_dir / "backend.hcl").exists():
            init_args.append("-backend-config=backend.hcl")
        r = run_tf(env_dir, init_args, dry, log)
        if r.returncode != 0:
            print(f"  FAIL {env_dir.name}: init error (see output above)")
            return 1
    r = run_tf(env_dir, ["plan", "-input=false", "-out", "tf.plan", "-detailed-exitcode"], dry, log)
    if r.returncode == 1:
        print(f"  FAIL {env_dir.name}: plan error (see output above)")
        return 1
    cls, _ = triage_plan(env_dir, dry, log)
    return cls


def cmd_plan(args):
    envs = Path(args.envs_dir)
    worst = 0
    targets = select(envs, args.env, args.all)
    log = logfile(envs, "plan") if not args.dry_run else None
    for name in targets:
        rc = _plan_one(envs / name, args.dry_run, log)
        if rc == 1:
            print(f"\n== RESULT: FAILED (plan error in {name}) ==")
            return 1
        worst = max(worst, rc)
    if args.dry_run:
        print(f"\n== RESULT: DRY RUN COMPLETE ({len(targets)} env(s), no cloud access) ==")
    elif worst == 0:
        print(f"\n== RESULT: NO CHANGES ({len(targets)}/{len(targets)} env(s) clean) ==")
    elif worst == 2:
        print(f"\n== RESULT: CHANGES PRESENT (review the plan output above before apply) ==")
    else:
        print(f"\n== RESULT: DESTRUCTIVE CHANGES PRESENT (apply is blocked without --allow-destroy) ==")
    return worst


def cmd_state_backup(args):
    envs = Path(args.envs_dir)
    dest = envs / "state-backups"
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    for name in select(envs, args.env, args.all):
        env_dir = envs / name
        if args.dry_run:
            print(f"[{name}] $ terraform state pull > state-backups/{ts}-{name}.tfstate.json")
            continue
        r = subprocess.run(["terraform", "state", "pull"], cwd=str(env_dir),
                           capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        if r.returncode != 0 or not r.stdout.strip():
            print(f"  {name}: no state pulled ({(r.stderr or 'empty state').strip()[:120]})")
            continue
        dest.mkdir(exist_ok=True)
        out = dest / f"{ts}-{name}.tfstate.json"
        out.write_text(r.stdout, encoding="utf-8")
        print(f"  {name}: backed up -> {out.name} ({len(r.stdout)} bytes)")
    return 0


# Documented transient platform errors that merit exactly one retry (async
# authority grants, log-service hiccups). Extend per engagement with
# LZ_TRANSIENT_SIGNATURES (comma-separated substrings) rather than editing
# code; keep signatures SPECIFIC - a broad match retries real failures.
TRANSIENT_SIGNATURES = tuple(
    s for s in os.environ.get(
        "LZ_TRANSIENT_SIGNATURES", "LTS.2101,EPS.0004").split(",") if s.strip())


def _is_transient(output: str) -> bool:
    return any(sig in (output or "") for sig in TRANSIENT_SIGNATURES)


def _saved_plan_usable(env_dir: Path) -> bool:
    """A tf.plan from a previous plan/drift run can be applied directly IF no
    configuration input changed after it was written (terraform itself refuses
    the plan if the STATE moved). Skips the expensive re-plan on large envs.
    Inputs include the SHARED module tree and the provider lock: a plan is a
    config snapshot, so applying it after a module edit would silently execute
    the OLD module code."""
    tfp = env_dir / "tf.plan"
    if not tfp.exists():
        return False
    newest = 0.0
    for pat in ("*.tf", "terraform.tfvars.json", "backend.hcl", "*.auto.tfvars.json",
                ".terraform.lock.hcl"):
        for f in env_dir.glob(pat):
            newest = max(newest, f.stat().st_mtime)
    # any modules tree the env's .tf sources point into (../modules layout)
    for mod_root in (env_dir.parent.parent / "modules",
                     env_dir.parent / "modules", env_dir / "modules"):
        if mod_root.is_dir():
            for f in mod_root.rglob("*.tf"):
                newest = max(newest, f.stat().st_mtime)
    return tfp.stat().st_mtime >= newest


def cmd_apply(args):
    # The skills' no-apply promise as a STRONG DEFAULT (not a security
    # boundary: an agent with shell access can set the override - the point is
    # converting silent violation into a deliberate, visible act). A human
    # inside a Claude Code terminal sets LZ_OPERATOR_APPLY=1; CI has no
    # CLAUDECODE and is unaffected. A true boundary is credential isolation:
    # the agent never holds AK/SK, so preflight fails regardless.
    if (os.environ.get("CLAUDECODE") and not args.dry_run
            and not os.environ.get("LZ_OPERATOR_APPLY")):
        print("apply refused: agent session detected (CLAUDECODE set). The skills "
              "stop at the apply gate by contract - run this from your own "
              "terminal, or set LZ_OPERATOR_APPLY=1 if you are a human inside a "
              "Claude Code session. (--dry-run is always allowed.)")
        return 4
    envs = Path(args.envs_dir)
    order = select(envs, args.env, args.all)
    if not args.dry_run:
        psk_bad = [p for p in psk_problems(envs) if p.split(":")[0] in order]
        if psk_bad:
            for p in psk_bad:
                print(f"FAIL {p}")
            print("== RESULT: BLOCKED (a placeholder psk would become the live tunnel key) ==")
            return 3
    lock = Lock(envs)
    lock.acquire(dry=args.dry_run)
    log = logfile(envs, "apply") if not args.dry_run else None
    applied, skipped = 0, 0
    try:
        for name in order:
            env_dir = envs / name
            print(f"== {name} ==")
            lock.refresh(dry=args.dry_run)   # long applies must not go stale mid-run
            # 1. state backup first (LZR-007)
            ns = argparse.Namespace(envs_dir=str(envs), env=name, all=False, dry_run=args.dry_run)
            cmd_state_backup(ns)
            # 2. plan + triage gate - reuse the reviewed plan file when it is
            #    still current (approve-what-you-apply; avoids double-planning
            #    slow envs). terraform refuses the file if state moved since.
            if not args.dry_run and _saved_plan_usable(env_dir):
                print(f"  using the saved plan from the last plan run "
                      f"(configuration unchanged since; terraform verifies state freshness)")
                rc, _ = triage_plan(env_dir, False, log)
            else:
                rc = _plan_one(env_dir, args.dry_run, log)
            if rc == 1:
                print(f"\n== RESULT: FAILED (plan error in {name}; earlier envs were applied) ==")
                return 1
            if rc == 0:
                print(f"  PASS {name}: no changes, skipping apply")
                skipped += 1
                continue
            if rc == 3 and not args.allow_destroy:
                print(f"  FAIL {name}: DESTRUCTIVE changes in plan - stopping. Review the plan; "
                      "re-run with --allow-destroy only if the destruction is intended.")
                print(f"\n== RESULT: BLOCKED (destructive changes in {name}) ==")
                return 3
            if not args.yes and not args.dry_run:
                if not sys.stdin.isatty():
                    print(f"  STOP {name}: interactive confirmation needed but stdin "
                          "is not a terminal - run from a terminal, or pass --yes "
                          "for non-destructive applies")
                    return 4
                resp = input(f"  apply {name}? [y/N] ").strip().lower()
                if resp != "y":
                    print("\n== RESULT: STOPPED by operator ==")
                    return 2
            # Destructive applies take a SECOND, explicit confirmation that
            # --yes never satisfies: type the env name, or pre-authorize the
            # specific env with --destroy-confirm <env> (for CI).
            if rc == 3 and not args.dry_run:
                pre = getattr(args, "destroy_confirm", None) or []
                if name not in pre:
                    if not sys.stdin.isatty():
                        print(f"  STOP {name}: destructive applies require a typed "
                              "confirmation at a terminal (or --destroy-confirm ENV "
                              "for CI) - refusing in a non-interactive context")
                        return 4
                    resp = input(f"  DESTRUCTIVE apply - type the env name "
                                 f"({name}) to confirm: ").strip()
                    if resp != name:
                        print("\n== RESULT: STOPPED (destructive apply not confirmed) ==")
                        return 2
            # 3. apply the reviewed plan file
            r = run_tf(env_dir, ["apply", "-input=false", "tf.plan"], args.dry_run, log)
            if r.returncode != 0 and not args.dry_run and _is_transient(r.stdout):
                # Retry-once on documented transients (async grants, log-service
                # hiccups). The saved plan is stale after a partial apply, so
                # the retry is re-plan + apply of the remainder, never a replay.
                print(f"  RETRY {name}: transient platform error - re-plan + apply once")
                if log:
                    log.write("\n[retry] transient signature matched; re-plan + apply\n")
                rc2 = _plan_one(env_dir, False, log)
                if rc2 == 0:
                    r = subprocess.CompletedProcess([], 0, "", "")
                elif rc2 == 2:
                    r = run_tf(env_dir, ["apply", "-input=false", "tf.plan"], False, log)
                # rc2 in (1, 3): fall through with the original failure
            if r.returncode != 0:
                if "stale" in r.stdout.lower():
                    print(f"  FAIL {name}: the saved plan is stale (state changed since it "
                          "was created) - re-run plan for this env, review, then apply again")
                else:
                    print(f"  FAIL {name}: apply error - state backup is in state-backups/; "
                          "see cookbooks (recovering from a failed apply)")
                print(f"\n== RESULT: FAILED (apply error in {name}) ==")
                return 1
            print(f"  PASS {name}: applied")
            applied += 1
    finally:
        lock.release(dry=args.dry_run)
    if args.dry_run:
        print(f"\n== RESULT: DRY RUN COMPLETE ({len(order)} env(s), no cloud access) ==")
    else:
        print(f"\n== RESULT: APPLIED ({applied} applied, {skipped} already current) ==")
    return 0


def cmd_drift(args):
    envs = Path(args.envs_dir)
    rows = []
    log = logfile(envs, "drift")
    targets = select(envs, args.env, not args.env)   # no ENV -> all
    for name in targets:
        env_dir = envs / name
        if not (env_dir / ".terraform").exists():
            rows.append((name, "SKIP (not initialized)"))
            continue
        # a drift sweep is read-only in spirit: write a SEPARATE plan file so
        # it can never arm cmd_apply's saved-plan reuse (tf.plan stays the
        # reviewed artifact from an explicit plan run)
        r = run_tf(env_dir, ["plan", "-input=false", "-out", "drift.tfplan",
                             "-detailed-exitcode"], False, log)
        if r.returncode == 0:
            rows.append((name, "clean"))
        elif r.returncode == 1:
            last = next((l for l in reversed(r.stdout.strip().splitlines()) if l.strip()), "?")
            rows.append((name, f"ERROR: {last[:100]}"))
        else:
            cls, buckets = triage_plan(env_dir, False, log, plan_file="drift.tfplan")
            if buckets and not buckets["update"] and not buckets["destructive"] and not buckets["create"]:
                rows.append((name, f"known-benign drift only ({len(buckets['benign'])})"))
            else:
                b = buckets or {}
                rows.append((name, f"DRIFT: {len(b.get('destructive', []))} destructive, "
                                   f"{len(b.get('update', []))} update, {len(b.get('create', []))} create"))
    print("\n== drift summary ==")
    for name, status in rows:
        tok = "PASS" if status == "clean" or status.startswith("known-benign") else \
              "SKIP" if status.startswith("SKIP") else "FAIL"
        print(f"  {tok} {name:20} {status}")
    if args.report:
        ts = datetime.datetime.now().isoformat(timespec="seconds")
        md = [f"# Drift report - {ts}", ""]
        md += [f"| Env | Status |", "|---|---|"] + [f"| {n} | {s} |" for n, s in rows]
        Path(args.report).write_text("\n".join(md) + "\n", encoding="utf-8")
        print(f"report -> {args.report}")
    bad = [s for _, s in rows if s.startswith(("DRIFT", "ERROR"))]
    clean = len(rows) - len(bad)
    if bad:
        print(f"\n== RESULT: DRIFT FOUND ({len(bad)} env(s) with drift or errors, {clean} clean) ==")
    else:
        print(f"\n== RESULT: NO UNEXPLAINED DRIFT ({clean}/{len(rows)} env(s) clean or known-benign) ==")
    return 2 if bad else 0


def cmd_adopt(args):
    envs = Path(args.envs_dir)
    env_dir = envs / select(envs, args.env, False)[0]
    r = run_tf(env_dir, ["import", args.address, args.cloud_id], args.dry_run)
    if r.returncode != 0:
        print("  import failed (see output above)")
        return 1
    r = run_tf(env_dir, ["plan", "-input=false", "-detailed-exitcode"], args.dry_run)
    if r.returncode == 2:
        print("  imported, but the plan above still shows differences for review.")
        print("  Align the configuration block with the imported values and re-plan.")
        return 2
    print("  imported clean: configuration matches the resource")
    return 0


def cmd_who_changed(args):
    print(f"CTS query for changes to {args.resource!r}:")
    print("  1. Console: CTS (security/audit account) -> Trace List ->")
    print(f"     filter resource name = {args.resource}, time range as needed.")
    print("  2. Older than the console window: query the aggregated copies in LTS")
    print("     (log admin account), or the audit bucket's org-audit prefix (365 d).")
    return 0


def cmd_triage(args):
    return plan_triage.main_files(args.plans)


def cmd_docs(args):
    """Regenerate the doc set (IPAM / checklist / config book) from the tree."""
    root = Path(__file__).resolve().parent.parent
    tools = Path(__file__).resolve().parent / "tools"
    if not tools.exists():
        print("'docs' needs the build pipeline, which this runtime-only "
              "installation does not include.")
        return 2
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    envs = str(Path(args.envs_dir))
    title = args.customer or "Landing Zone"
    jobs = []
    # The Excel LLD workbook is a generated ARTIFACT of the JSON spec
    # (the authoritative store) - regenerate it with the rest of the doc set.
    ir = getattr(args, "ir", None)
    if ir:
        jobs.append((tools / "gen_workbook.py",
                     ["--ir", ir, "-o", str(out / "landing-zone-spec.xlsx")]))
    jobs += [
        (tools / "gen_ipam.py", ["--envs-dir", envs, "--out", str(out / "ip-management.xlsx"),
                                 "--title", f"{title} - IP management"]),
        (tools / "gen_config_book.py", ["--envs-dir", envs, "--out", str(out / "config-book.xlsx"),
                                        "--customer", title]
         + (["--states-dir", args.states_dir] if args.states_dir else [])),
    ]
    if args.states_dir:
        jobs.append((tools / "gen_checklist.py",
                     ["--envs-dir", envs, "--states-dir", args.states_dir,
                      "--out", str(out / "resource-checklist.xlsx"),
                      "--title", f"{title} - Resource Checklist"]))
    rc = 0
    print("== document generation ==")
    for script, extra in jobs:
        r = subprocess.run([sys.executable, "-X", "utf8", str(script)] + extra,
                           capture_output=True, text=True)
        tail = (r.stdout or r.stderr).strip().splitlines()
        print(f"  {'PASS' if r.returncode == 0 else 'FAIL'} {script.name}"
              + (f" - {tail[-1]}" if tail else ""))
        rc = rc or r.returncode
    if rc == 0:
        print(f"\n== RESULT: {len(jobs)} DOCUMENT(S) GENERATED -> {out} ==")
    else:
        print(f"\n== RESULT: FAILED (see the FAIL line(s) above) ==")
    return rc


def _pipeline_delegate(what, extra):
    import importlib.util
    if importlib.util.find_spec("lz_spec") is None:
        print(f"'{what}' needs the build pipeline, which this runtime-only "
              "installation does not include.")
        return 2
    # the delegated parser prints usage for the command the OPERATOR typed,
    # not for the module that happens to implement it
    env = dict(os.environ, LZ_INVOKED_AS=f"lzctl {what}")
    if what == "check":
        return subprocess.run([sys.executable, "-m", "lz_spec.verify_pipeline"] + extra,
                              env=env).returncode
    if what == "export":
        return subprocess.run([sys.executable, "-m", "lz_pipeline.export_v2"] + extra,
                              env=env).returncode
    if what == "validate":
        what = "spec-validate"
    # cwd stays the CALLER's cwd so relative --spec/--envs-dir paths resolve
    # exactly as typed (the old pipeline-dir cwd silently re-anchored them)
    return subprocess.run([sys.executable, "-m", "lz_pipeline", what] + extra,
                          env=env).returncode


def cmd_intake(args):
    """Filled questionnaire xlsx -> mechanical answers dump (no interpretation)."""
    import importlib.util
    if importlib.util.find_spec("lz_pipeline.tools.dump_questionnaire") is None:
        print("'intake' needs the build pipeline (dump_questionnaire).")
        return 2
    argv = [sys.executable, "-X", "utf8", "-m", "lz_pipeline.tools.dump_questionnaire",
            args.xlsx]
    if args.out:
        argv += ["-o", args.out]
    return subprocess.run(argv).returncode


def _decision_set_sha256(items):
    """Hash of the IMMUTABLE decision set - ref/state/question/targets/
    default_if_silent, never `resolution` (resolutions must stay editable).
    Stored in the spec's provenance at assess time and recomputed by the
    build gate, so deleting or altering any decision - not just leaving one
    unresolved - blocks the build."""
    import hashlib
    basis = [{k: i.get(k) for k in
              ("ref", "state", "question", "targets", "default_if_silent")
              if k in i}
             for i in items]
    return hashlib.sha256(json.dumps(basis, sort_keys=True, ensure_ascii=False)
                          .encode("utf-8")).hexdigest()


def _skeleton():
    """Schema-shaped neutral sheets: every table [], every scalar field null.

    `null` - not "" - is how this pipeline spells "nobody has supplied this
    yet"; LZR-034 reports unsupplied values against the decisions file, and
    a draft built from this fails validation until answers are interpreted
    in - which is the point: nothing deployable exists that wasn't decided.

    Built from lz_spec.schema, NOT the example fixture: neutralizing the
    fixture meant any sheet or field the fixture predated (11_SGACL, half
    of CloudFirewall) was silently absent from every fresh draft, and the
    fixture's old schema_version got stamped onto new work (round-4
    benchmark, 12+ runs).
    """
    from lz_spec import schema as wb
    sheets = {}
    for sh in wb.SHEETS:
        if sh.name in wb.INFO_SHEETS or sh.name == "_meta":
            continue
        tables = {}
        for t in sh.tables:
            if t.kind == "scalar":
                tables[t.name] = {getattr(r, "name", r): None for r in (t.rows or [])}
            else:
                tables[t.name] = []
        sheets[sh.name] = tables
    return sheets


def _specpath():
    """The schema path resolver, or None in a runtime-only installation.

    It reads the lz_spec workbook schema, which does not ship in the handover
    artifact this file also lives in.
    """
    try:
        from lz_pipeline import specpath
    except ImportError:
        return None
    return specpath


_OPEN_HEADING = "## OPEN ({n}) - resolve before build"


def _unresolved_open(items):
    """OPEN decisions nobody has resolved - exactly what the build gate counts."""
    return sum(1 for i in items if i.get("state") == "OPEN"
               and not isinstance(i.get("resolution"), dict))


def _restate_open_heading(body: str, n: int) -> str:
    """Re-render the agenda's `## OPEN (n)` heading in place.

    `gap add` appends items to the same file, so the count `assess` wrote
    understates the gate from the first gap onward - and a heading that
    reports fewer blockers than exist is worse than no heading.
    """
    return re.sub(r"^## OPEN \(\d+\).*$", _OPEN_HEADING.format(n=n), body,
                  count=1, flags=re.M)


def cmd_assess(args):
    """Deterministic assessment pre-pass: neutral draft + decisions files.

    The draft is a schema-shaped skeleton with every value UNSET (it fails
    `lzctl validate` until interpreted - by design). The decisions files
    (.md for humans, .json for the build gate) classify every question:
    ANSWERED / DEFAULTED (silent with a documented default) / OPEN (required,
    no default). Interpreting prose answers into spec fields is the agent's
    or engineer's job - this command never guesses, and `build` refuses to
    run while OPEN items lack a recorded resolution."""
    import hashlib
    dump_bytes = Path(args.dump).read_bytes()
    dump = json.loads(dump_bytes.decode("utf-8"))
    # lineage id: hash of the answers dump. Stable across resolution edits
    # (those touch the decisions file, not the dump), so a copied/renamed
    # spec still carries — and the gate still demands — its decisions file.
    assessment_id = hashlib.sha256(dump_bytes).hexdigest()
    ws = Path(args.workspace or ".").resolve()
    specs = ws / "specs"
    specs.mkdir(parents=True, exist_ok=True)
    slug = args.customer.lower()
    draft = specs / f"lz.spec.{slug}.json"
    decisions = specs / f"lz.spec.{slug}.decisions.md"
    decisions_json = specs / f"lz.spec.{slug}.decisions.json"
    if draft.exists() and not args.force:
        print(f"refusing to overwrite {draft} (use --force)")
        return 1
    sp = _specpath()
    if sp is None:
        print("'assess' needs the build pipeline (the schema shapes the neutral "
              "draft), which this runtime-only installation does not include.",
              file=sys.stderr)
        return 2
    from lz_spec import schema as wb_schema
    spec = {"format": "lz-spec-ir/1", "schema_version": wb_schema.SCHEMA_VERSION,
            "customer": slug, "sheets": _skeleton()}
    meta = dump.get("meta", {})
    spec["source"] = (f"assessment questionnaire v{meta.get('questionnaire_version', '?')} "
                      f"({dump.get('source_file', '?')}) - NEUTRAL DRAFT: every value "
                      "unset until interpreted from the answers; validate fails until then")
    answered, defaulted, gaps = [], [], []
    for a in dump.get("answers", []):
        ref, q = a.get("ref", "?"), (a.get("question") or "").strip()
        ans = (a.get("answer") or "").strip()
        tg = list(a.get("targets") or [])
        if ans:
            answered.append((ref, q, ans, tg))
        elif (a.get("default_if_silent") or "").strip():
            defaulted.append((ref, q, a["default_if_silent"].strip(), tg))
        else:
            gaps.append((ref, q, tg))
    apx = dump.get("appendices", {})

    # the immutable decision set, hashed into the spec's provenance: build
    # verifies the manifest still holds EXACTLY this set (resolutions aside),
    # so truncating or altering decisions blocks just like leaving them open
    items = (
        [{"ref": r, "state": "OPEN", "question": q, "targets": t,
          "resolution": None} for r, q, t in gaps]
        + [{"ref": r, "state": "DEFAULTED", "question": q, "default_if_silent": d,
            "targets": t, "resolution": None} for r, q, d, t in defaulted]
        + [{"ref": r, "state": "ANSWERED", "question": q, "targets": t,
            "resolution": None} for r, q, _, t in answered])
    spec["provenance"] = {"source_type": "questionnaire",
                          "decisions_file": decisions_json.name,
                          "assessment_id": assessment_id,
                          "decision_set_sha256": _decision_set_sha256(items),
                          "decision_count": len(items),
                          "customer": slug}
    draft.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    lines = [f"# Decisions needed - {slug}", "",
             f"Generated by `lzctl assess` from {dump.get('source_file', '?')}.",
             "Every question lands in exactly one state - ANSWERED, DEFAULTED",
             "(silent with a documented default), or OPEN (required, no default).",
             "Nothing below was guessed.", "",
             _OPEN_HEADING.format(n=len(gaps)), ""]
    lines += [f"- **{r}** {q}  \n  targets: `{', '.join(t) or '-'}`" for r, q, t in gaps] or ["(none)"]
    lines += ["", f"## DEFAULTED ({len(defaulted)}) - documented defaults apply; review", ""]
    lines += [f"- **{r}** {q}  \n  default: {d}" for r, q, d, _ in defaulted] or ["(none)"]
    lines += ["", f"## ANSWERED ({len(answered)}) - interpret into the draft spec", ""]
    lines += [f"- **{r}** {q}" for r, q, _, _ in answered] or ["(none)"]
    lines += ["", "## Appendices (copy VERBATIM - never retype)", ""]
    lines += [f"- Appendix {k}: {len(v.get('rows', []))} row(s) -> `{', '.join(v.get('targets') or [])}`"
              for k, v in sorted(apx.items())] or ["(none)"]
    decisions.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # machine-readable twin: the build gate reads this. OPEN items block
    # `build` until a resolution is recorded; DEFAULTED/ANSWERED never block.
    decisions_json.write_text(json.dumps({
        "customer": slug, "source_file": dump.get("source_file", "?"),
        "assessment_id": assessment_id,
        "resolution_contract": {
            "blocking": "state=OPEN with resolution=null blocks `lzctl build`",
            "resolve_by": 'set resolution to {"status": "ANSWERED"|"ACCEPTED_DEFAULT",'
                          ' "approved_by": "<person>", "reason": "<why>"} - all three'
                          ' fields required; see schemas/decisions.schema.json'},
        "items": items}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"draft spec (neutral) -> {draft}")
    print(f"decisions (human)    -> {decisions}")
    print(f"decisions (gate)     -> {decisions_json}")
    print(f"\n== RESULT: ASSESSED ({len(answered)} ANSWERED, {len(defaulted)} DEFAULTED, "
          f"{len(gaps)} OPEN) ==")
    print("next: interpret answered questions into the draft (questionnaire-to-spec"
          " skill or by hand), resolve OPEN items in the decisions .json, then"
          " `lzctl validate`")
    return 0


def cmd_gap(args):
    """Register a gap found while interpreting - the ONLY sanctioned way to
    add to a decision set after assessment.

    `assess` can only classify what the QUESTIONNAIRE left blank. Facts the
    spec needs that no question asked for (an on-prem resolver IP, a peer
    gateway's public IP, a certificate ID) surface later, during
    interpretation - and until now had nowhere to live: the decision set is
    hash-bound, so appending by hand is indistinguishable from tampering and
    blocks the build.

    This command appends the item and re-stamps BOTH sides atomically -
    decisions .json, decisions .md, and the spec's provenance hash - so the
    gap becomes a real OPEN item that blocks `build` until somebody resolves
    it and records who decided. A hand-edited set still fails, exactly as
    before.
    """
    spec_path = Path(args.spec).resolve()
    if not spec_path.exists():
        print(f"spec not found: {spec_path}", file=sys.stderr)
        return 2
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    prov = spec.get("provenance") or {}
    if prov.get("source_type") != "questionnaire":
        print("this spec has no questionnaire lineage (no provenance block), so it "
              "has no decision set to add to - record the gap wherever this spec's "
              "requirements live", file=sys.stderr)
        return 2
    dec_path = spec_path.with_name(prov.get("decisions_file")
                                   or (spec_path.stem + ".decisions.json"))
    if not dec_path.exists():
        print(f"decisions file missing: {dec_path}", file=sys.stderr)
        return 2
    doc = json.loads(dec_path.read_text(encoding="utf-8"))
    items = doc.get("items") or []

    if args.action == "list":
        # read-only, so it runs against ANY set - including an altered one,
        # which is precisely when somebody needs to see what is in there
        gaps = [i for i in items if str(i.get("ref", "")).startswith("G")]
        print(f"== {len(gaps)} registered gap(s) in {dec_path.name} ==")
        for i in gaps:
            res = i.get("resolution") or {}
            state = res.get("status") or "UNRESOLVED"
            tg = i.get("targets") or []
            print(f"  {i['ref']:4} [{state}] {', '.join([tg] if isinstance(tg, str) else tg)}")
            print(f"       {i.get('question', '')}")
        return 0

    # Refuse to launder a set that is ALREADY altered: re-stamping here would
    # bless whatever edit came before us. Only a set matching its provenance
    # may grow.
    if _decision_set_sha256(items) != prov.get("decision_set_sha256"):
        print("decision set does not match the spec's provenance hash - it was "
              "altered outside this command. Restore it (or re-run `lzctl assess`) "
              "before adding gaps; `gap add` will not re-stamp an edited set.",
              file=sys.stderr)
        return 3

    fields = args.field or []
    if not fields or not args.question:
        print("gap add needs --field <Sheet.Table[row].Column> (repeat it for a gap "
              "that spans several fields) and --question <what is missing and who "
              "can answer it>", file=sys.stderr)
        return 2

    # A target that resolves to nothing tracks nothing: "05_Network.HubSubnets
    # and SpokeSubnets" reads like a declaration and joins to no field.
    sp = _specpath()
    if sp is None:
        print("'gap add' needs the build pipeline (it resolves --field against the "
              "schema), which this runtime-only installation does not include.",
              file=sys.stderr)
        return 2
    for f in fields:
        try:
            sp.parse(f)
        except sp.PathError as e:
            print(f"--field {e}", file=sys.stderr)
            return 2

    used = {str(i.get("ref", "")) for i in items}
    ref = args.ref or next(f"G{n}" for n in range(1, 1000) if f"G{n}" not in used)
    if ref in used:
        print(f"ref {ref} already exists in {dec_path.name}", file=sys.stderr)
        return 2
    item = {"ref": ref, "state": "OPEN", "question": args.question,
            "targets": list(fields), "resolution": None}
    items.append(item)
    doc["items"] = items
    doc["gaps_registered"] = sum(1 for i in items if str(i.get("ref", "")).startswith("G"))

    prov["decision_set_sha256"] = _decision_set_sha256(items)
    prov["decision_count"] = len(items)
    spec["provenance"] = prov

    dec_path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    spec_path.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    md = dec_path.with_name(dec_path.name.replace(".json", ".md"))
    if md.exists():
        body = md.read_text(encoding="utf-8").rstrip("\n")
        if "## Gaps found during interpretation" not in body:
            body += ("\n\n## Gaps found during interpretation\n\n"
                     "Values the spec needs that no questionnaire question asked for.\n"
                     "Registered by `lzctl gap add`; each one blocks `build` until "
                     "resolved in the decisions .json.\n")
        body += f"\n- **{ref}** {args.question}  \n  targets: `{', '.join(fields)}`\n"
        md.write_text(_restate_open_heading(body, _unresolved_open(items)),
                      encoding="utf-8")

    print(f"registered {ref} -> {dec_path.name} (now {len(items)} decisions)")
    print(f"re-stamped provenance in {spec_path.name}")
    print(f"\n== RESULT: GAP {ref} REGISTERED (OPEN - blocks build until resolved) ==")
    return 0


_BOOL_WORDS = {"true": True, "1": True, "yes": True, "y": True,
               "false": False, "0": False, "no": False, "n": False}
_ROW_KEYS = ("Name", "VPCName", "UserName", "Key")


def _coerce(raw: str, typ: str):
    t = (typ or "string").lower()
    if t == "int":
        return int(raw)
    if t == "bool":
        v = _BOOL_WORDS.get(raw.strip().lower())
        if v is None:
            raise ValueError("expected true or false")
        return v
    if t == "csv-list":
        return [x.strip() for x in raw.split(",") if x.strip()]
    if t == "json":
        return json.loads(raw)
    return raw


def _find_row(rows, key):
    """A row by its name-ish key, else (for keyless tables and dotted names)
    by 0-based index. Never invents one."""
    row = next((r for r in rows
                if any(str(r.get(k)) == key for k in _ROW_KEYS)), None)
    if row is None and key.isdigit() and int(key) < len(rows):
        row = rows[int(key)]
    return row


def _set_delete_row(args, p, spec_path):
    """`set --field 'Sheet.Table[row]' --null`: remove one row.

    The one row-level operation `set` has, added after a round-4 run turned
    a rename in a keyless table (SGRules) into a permanent orphan - without
    it, the only recovery from a bad append is `assess --force`."""
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    sheet = spec.setdefault("sheets", {}).setdefault(p["sheet"], {})
    rows = sheet.get(p["table"])
    if not isinstance(rows, list):
        rows = []
    target = None
    if p["row"].isdigit() and int(p["row"]) < len(rows):
        target = rows[int(p["row"])]
    else:
        target = next((r for r in rows if isinstance(r, dict) and
                       any(str(r.get(k)) == p["row"] for k in _ROW_KEYS)), None)
        if target is None and p["row"] in rows:      # list-single tables
            target = p["row"]
    if target is None:
        print(f"{p['sheet']}.{p['table']} has no row {p['row']!r} to delete "
              f"({len(rows)} row(s); name or 0-based index)", file=sys.stderr)
        return 2
    rows.remove(target)
    sheet[p["table"]] = rows
    spec_path.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n",
                         encoding="utf-8", newline="\n")
    print(f"deleted {p['sheet']}.{p['table']}[{p['row']}] "
          f"({len(rows)} row(s) remain)")
    return 0


def _set_append_row(sp, args, p, spec_path):
    """`set --field Sheet.Table[+] --json '{...}'`: append one whole row.

    The last mechanical write `set` could not do: rows are addressed by name,
    so a row that does not exist yet was unreachable and every run hand-wrote
    a JSON mutator for its appendix rows. Append validates every key against
    the schema's columns - the misspelled-key hazard is the same one `set`
    exists to close. `[+]` appends only; existing rows are edited by name.
    """
    if p["column"]:
        print(f"--field {args.field!r}: [+] appends a whole row - give the "
              f"columns as --json, not a path to one column", file=sys.stderr)
        return 2
    if p["kind"] == "scalar":
        print(f"--field {args.field!r}: {p['sheet']}.{p['table']} is a scalar "
              f"table and has no rows - set its fields directly", file=sys.stderr)
        return 2

    if p["kind"] == "list-single":
        if args.null:
            print("a list-single row cannot be null - give the value", file=sys.stderr)
            return 2
        value = json.loads(args.json) if args.json is not None else args.value
    else:
        if args.json is None:
            print(f"row append takes the row as JSON: --field "
                  f"'{p['sheet']}.{p['table']}[+]' --json "
                  f"'{{\"Column\": value, ...}}'", file=sys.stderr)
            return 2
        try:
            value = json.loads(args.json)
        except ValueError as e:
            print(f"--json is not valid JSON: {e}", file=sys.stderr)
            return 2
        if not isinstance(value, dict) or not value:
            print("--json must be a non-empty object of column values",
                  file=sys.stderr)
            return 2
        for k in value:
            try:
                sp.parse(f"{p['sheet']}.{p['table']}[x].{k}")
            except sp.PathError as e:
                print(f"--json {e}", file=sys.stderr)
                return 2

    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    sheet = spec.setdefault("sheets", {}).setdefault(p["sheet"], {})
    rows = sheet.get(p["table"])
    if not isinstance(rows, list):
        rows = []
    rows.append(value)
    sheet[p["table"]] = rows
    spec_path.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n",
                         encoding="utf-8", newline="\n")
    print(f"appended {p['sheet']}.{p['table']}[{len(rows) - 1}] = "
          f"{json.dumps(value, ensure_ascii=False)}")
    return 0


def cmd_set(args):
    """Put one value into the spec at a schema path.

    The mechanical half of interpretation. Deciding WHAT the value is stays a
    human/agent judgement; typing it into the right slot is not, and doing it
    by hand-rolled JSON mutation is how a value lands under a misspelled key
    that no builder ever reads and no validator ever misses.
    """
    sp = _specpath()
    if sp is None:
        print("'set' needs the build pipeline (it resolves --field against the "
              "schema), which this runtime-only installation does not include.",
              file=sys.stderr)
        return 2
    spec_path = Path(args.spec).resolve()
    if not spec_path.exists():
        print(f"spec not found: {spec_path}", file=sys.stderr)
        return 2
    try:
        p = sp.parse(args.field)
    except sp.PathError as e:
        print(f"--field {e}", file=sys.stderr)
        return 2
    if p["row"] == "+":
        return _set_append_row(sp, args, p, spec_path)
    if p["row"] and not p["column"] and not p["field"]:
        # a whole row: --null deletes it (the only row-level operation).
        # Rows in keyless tables are addressable by 0-based index, so a
        # mid-interpretation mistake is recoverable without assess --force.
        if args.null:
            return _set_delete_row(args, p, spec_path)
        print(f"--field {args.field!r} names a whole row - give "
              f"{p['sheet']}.{p['table']}[{p['row']}].Column to write one "
              "value, or pass --null to DELETE the row", file=sys.stderr)
        return 2
    if not p["field"] and not p["column"]:
        print(f"--field {args.field!r} names a table, not a value - give "
              "Sheet.Table.field, Sheet.Table[row].Column, or Sheet.Table[+] "
              "with --json to append a row (list-single tables: one "
              "--value/--json element per [+] call)", file=sys.stderr)
        return 2
    if p["column"] and not p["row"]:
        print(f"--field {args.field!r} names a column but no row - give "
              f"{p['sheet']}.{p['table']}[<row>].{p['column']}", file=sys.stderr)
        return 2

    typ = sp.field_type(args.field)
    if args.null:
        value = None
    elif args.json is not None:
        try:
            value = json.loads(args.json)
        except ValueError as e:
            print(f"--json is not valid JSON: {e}", file=sys.stderr)
            return 2
    else:
        try:
            value = _coerce(args.value, typ)
        except ValueError as e:
            print(f"--value {args.value!r} is not a valid {typ}: {e}", file=sys.stderr)
            return 2

    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    sheet = spec.setdefault("sheets", {}).setdefault(p["sheet"], {})
    if p["field"]:
        sheet.setdefault(p["table"], {})[p["field"]] = value
    else:
        rows = [r for r in (sheet.get(p["table"]) or []) if isinstance(r, dict)]
        row = _find_row(rows, p["row"])
        if row is None:
            names = [str(next((r[k] for k in _ROW_KEYS if r.get(k)), "?")) for r in rows]
            print(f"{p['sheet']}.{p['table']} has no row {p['row']!r} "
                  f"(rows: {', '.join(names) or 'none'}; a 0-based index works "
                  f"too) - add it first with "
                  f"--field '{p['sheet']}.{p['table']}[+]' --json '{{...}}'; "
                  "addressing never invents a row", file=sys.stderr)
            return 2
        row[p["column"]] = value
    spec_path.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n",
                         encoding="utf-8", newline="\n")
    print(f"set {args.field} = {json.dumps(value, ensure_ascii=False)}")
    return 0


def cmd_verify(args):
    """Post-apply verification: every env must be clean or known-benign."""
    print("== post-apply verification (re-plan + triage every env) ==")
    ns = argparse.Namespace(envs_dir=args.envs_dir, env=args.env, report=args.report)
    rc = cmd_drift(ns)
    if rc == 0:
        print("== VERIFY: PASS (deployed infrastructure matches the configuration) ==")
        return 0
    print("== VERIFY: FAIL (unexplained differences above - the apply chain "
          "left the deployed infrastructure inconsistent; investigate before further changes) ==")
    return rc


def cmd_report(args):
    """Evidence bundle: logs, deps, drift report, versions -> evidence/<ts>/."""
    import hashlib
    envs = Path(args.envs_dir)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out = Path(args.out or (envs / "evidence" / ts))
    out.mkdir(parents=True, exist_ok=True)
    collected = []
    logs = sorted((envs / "lzctl-logs").glob("*.log"))[-args.last_logs:] \
        if (envs / "lzctl-logs").exists() else []
    for src in logs + [envs / "deps.json"]:
        if Path(src).exists():
            shutil.copy2(src, out / Path(src).name)
            collected.append(Path(src).name)
    vers = [f"python {sys.version.split()[0]}"]
    if shutil.which("terraform"):
        r = subprocess.run(["terraform", "version"], capture_output=True, text=True)
        vers.append((r.stdout or "").splitlines()[0] if r.stdout else "terraform ?")
    (out / "versions.txt").write_text("\n".join(vers) + "\n", encoding="utf-8")
    drift_report = out / "drift-report.md"
    ns = argparse.Namespace(envs_dir=str(envs), env=None, report=str(drift_report))
    drift_rc = cmd_drift(ns)
    manifest = []
    for p in sorted(out.iterdir()):
        if p.name == "MANIFEST.txt" or not p.is_file():
            continue
        manifest.append(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}")
    (out / "MANIFEST.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    print(f"\n== RESULT: EVIDENCE BUNDLE -> {out} ({len(manifest)} file(s); "
          f"drift {'clean/benign' if drift_rc == 0 else 'HAS FINDINGS'}) ==")
    return 0 if drift_rc == 0 else 2


DELEGATES = ("build", "validate", "spec-validate", "check", "export", "deps")


def _version() -> str:
    """Installed distribution version, or a marker when running standalone.

    This file also ships loose inside the handover artifact, where there is
    no installed distribution to ask - hence the fallback rather than an
    import of the package it usually lives in.
    """
    try:
        from importlib.metadata import version, PackageNotFoundError
        return version("huawei-cloud-landing-zone-pipeline")
    except Exception:
        return "standalone runner (no installed distribution)"


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    # Delegated commands pass their entire argv through untouched - argparse's
    # remainder handling cannot preserve leading --options, so dispatch first.
    # `lzctl <command> --help` reaches the delegated parser's own help.
    if argv and argv[0] in DELEGATES:
        return _pipeline_delegate(argv[0], argv[1:])
    ap = argparse.ArgumentParser(prog="lzctl", description=__doc__.splitlines()[0])
    ap.add_argument("--version", action="version", version=f"lzctl {_version()}")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("--envs-dir", required=True)
        p.add_argument("--pricing", help="rate card JSON for the monthly cost estimate")
        p.add_argument("env", nargs="?")
        p.add_argument("--all", action="store_true")
        p.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("preflight");  p.add_argument("--envs-dir", required=True); p.set_defaults(fn=cmd_preflight)
    p = sub.add_parser("order");      p.add_argument("--envs-dir", required=True); p.set_defaults(fn=cmd_order)
    p = sub.add_parser("plan");       common(p); p.set_defaults(fn=cmd_plan)
    p = sub.add_parser("apply");      common(p)
    p.add_argument("--allow-destroy", action="store_true")
    p.add_argument("--yes", action="store_true",
                   help="skip the per-env confirm; NEVER skips the destructive confirm")
    p.add_argument("--destroy-confirm", action="append", metavar="ENV",
                   help="pre-authorize a destructive apply for this exact env (CI)")
    p.set_defaults(fn=cmd_apply)
    p = sub.add_parser("drift");      p.add_argument("--envs-dir", required=True)
    p.add_argument("env", nargs="?", help="ENV[,ENV...] subset (default: all)")
    p.add_argument("--report"); p.set_defaults(fn=cmd_drift)
    p = sub.add_parser("state-backup"); common(p); p.set_defaults(fn=cmd_state_backup)
    p = sub.add_parser("adopt");      p.add_argument("--envs-dir", required=True)
    p.add_argument("env"); p.add_argument("address"); p.add_argument("cloud_id")
    p.add_argument("--dry-run", action="store_true"); p.set_defaults(fn=cmd_adopt)
    p = sub.add_parser("who-changed"); p.add_argument("resource"); p.set_defaults(fn=cmd_who_changed)
    p = sub.add_parser("triage");     p.add_argument("plans", nargs="+"); p.set_defaults(fn=cmd_triage)
    p = sub.add_parser("docs");       p.add_argument("--envs-dir", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--states-dir")
    p.add_argument("--customer", default="")
    p.add_argument("--spec", "--ir", dest="ir",
                   help="the JSON spec (--ir is an accepted alias) - also regenerate the Excel LLD workbook artifact")
    p.set_defaults(fn=cmd_docs)
    p = sub.add_parser("intake", help="filled questionnaire xlsx -> answers dump (mechanical)")
    p.add_argument("xlsx")
    p.add_argument("-o", "--out", help="output json path (default: stdout)")
    p.set_defaults(fn=cmd_intake)
    p = sub.add_parser("assess", help="answers dump -> draft spec + decisions file (no guessing)")
    p.add_argument("dump", help="json produced by `lzctl intake`")
    p.add_argument("--customer", required=True, help="customer ID: short lowercase identifier used in filenames, e.g. acme")
    p.add_argument("--workspace", help="workspace dir (default: cwd); writes specs/ inside it")
    p.add_argument("--force", action="store_true")
    p.set_defaults(fn=cmd_assess)
    p = sub.add_parser("status", help="where this workspace is on the phase graph "
                                      "(read-only; derived from artifacts)")
    p.add_argument("--workspace", help="workspace root (default: cwd)")
    p.add_argument("--spec", "--ir", dest="spec", help="spec to report on (default: the one in specs/)")
    p.add_argument("--envs-dir", help="env tree (default: the one envs* dir found)")
    p.add_argument("--verbose", "-v", action="store_true", help="print every phase, not just the live ones")
    p.add_argument("--quick", action="store_true", help="skip the validator subprocess")
    p.add_argument("--json", action="store_true",
                   help="the phase report as data - what an agent formats from; "
                        "the plain text form is only for a human at a prompt")
    p.set_defaults(fn=cmd_status)
    p = sub.add_parser("back", help="deliberately re-enter an earlier phase, with a "
                                    "recorded reason (never undoes anything)")
    p.add_argument("phase", help=f"one of: {', '.join(PHASES)}")
    p.add_argument("--reason", required=True, help="why - this is the audit trail")
    p.add_argument("--by", help="who decided (default: the OS user)")
    p.add_argument("--workspace", help="workspace root (default: cwd)")
    p.add_argument("--spec", "--ir", dest="spec")
    p.add_argument("--envs-dir")
    p.set_defaults(fn=cmd_back)
    p = sub.add_parser("gap", help="register a gap found while interpreting (appends "
                                   "an OPEN decision and re-stamps provenance)")
    p.add_argument("action", choices=["add", "list"])
    p.add_argument("--spec", "--ir", dest="spec", required=True)
    p.add_argument("--field", action="append", metavar="FIELD",
                   help="REQUIRED for add: where the value belongs, as "
                        "Sheet.Table[row].Column (repeat for a gap that "
                        "spans several fields); unused by list")
    p.add_argument("--question",
                   help="REQUIRED for add: what is missing, and who can "
                        "answer it; unused by list")
    p.add_argument("--ref", help="explicit ref (default: next free G<n>)")
    p.set_defaults(fn=cmd_gap)
    p = sub.add_parser("set", help="write one value into the spec at a schema path")
    p.add_argument("--spec", "--ir", dest="spec", required=True)
    p.add_argument("--field", required=True,
                   help="Sheet.Table.field, Sheet.Table[row].Column (row = name "
                        "or 0-based index), Sheet.Table[+] to append a row "
                        "(object tables: --json '{...}'; list-single tables: "
                        "one --value/--json element per call - whole-array "
                        "writes are refused), or Sheet.Table[row] with --null "
                        "to delete the row")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--value", help="the value, coerced to the field's declared type")
    g.add_argument("--json", help="a JSON literal, for lists and exact types")
    g.add_argument("--null", action="store_true",
                   help="declare the value not known yet (null, not empty "
                        "string); on a Sheet.Table[row] path: delete the row")
    p.set_defaults(fn=cmd_set)
    p = sub.add_parser("verify", help="post-apply gate: every env clean or known-benign")
    p.add_argument("--envs-dir", required=True)
    p.add_argument("env", nargs="?", help="ENV[,ENV...] subset (default: all)")
    p.add_argument("--report", help="write the verification table to this markdown file")
    p.set_defaults(fn=cmd_verify)
    p = sub.add_parser("report", help="evidence bundle: logs + deps + drift + versions")
    p.add_argument("--envs-dir", required=True)
    p.add_argument("--out", help="bundle dir (default: <envs>/evidence/<ts>)")
    p.add_argument("--last-logs", type=int, default=10, help="how many recent logs to include")
    p.set_defaults(fn=cmd_report)
    for verb in DELEGATES:
        hint = {"build": "generate tfvars + HCL from the spec",
                "validate": "spec validation (structural + semantic + platform rules)",
                "spec-validate": "alias of validate",
                "check": "the pipeline regression harness (7 checks)",
                "export": "handover artifact export",
                "deps": "regenerate <envs-dir>/deps.json (build writes it too)"}[verb]
        # registered for --help only; real dispatch happens in main() before
        # argparse so the delegated argv passes through completely untouched
        p = sub.add_parser(verb, help=f"pipeline-side: {hint}")
        p.add_argument("extra", nargs=argparse.REMAINDER)

    args = ap.parse_args(argv)
    global PRICING_PATH
    if getattr(args, "pricing", None):
        PRICING_PATH = args.pricing
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
