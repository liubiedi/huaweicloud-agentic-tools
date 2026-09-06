"""The gap register and the gates that close the "fully answered questionnaire
proves nothing" hole: LZR-032 (no placeholder survives), LZR-033 (reserved
security toggles), `lzctl gap add`, and the app's decisions endpoints.

Traced to a demo run where a 54/54-answered questionnaire produced 0 OPEN
decisions, yet the spec that got built still carried four values nobody had
supplied.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
FIXTURE = REPO / "pipeline" / "lz_pipeline" / "fixtures" / "example.spec.json"


def run(mod, *args):
    return subprocess.run([sys.executable, "-X", "utf8", "-m", mod, *args],
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", cwd=str(REPO),
                          stdin=subprocess.DEVNULL)


def sheets():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))["sheets"]


# ── LZR-032: placeholders never reach build ────────────────────────────────

def test_clean_fixture_has_no_placeholder_findings():
    from lz_pipeline.rules import placeholder_findings
    assert placeholder_findings(sheets()) == []


def test_placeholder_in_any_field_is_an_error():
    from lz_pipeline.rules import placeholder_findings
    spec = sheets()
    spec.setdefault("10_VPN", {}).setdefault("CustomerGateways", []).append(
        {"Enabled": "TRUE", "Name": "dc1", "IP": "REPLACE_WITH_DC1_PUBLIC_IP", "ASN": 65010})
    found = placeholder_findings(spec)
    assert [f["path"] for f in found] == ["10_VPN.CustomerGateways[dc1].IP"]
    assert found[0]["sheet"] == "10_VPN" and found[0]["column"] == "IP"


def test_vpn_psk_placeholder_is_exempt():
    """LZR-027 REQUIRES a placeholder there (a literal secret would be worse);
    lzctl preflight blocks it before it can become a live tunnel key."""
    from lz_pipeline.rules import placeholder_findings
    spec = sheets()
    spec.setdefault("10_VPN", {}).setdefault("Connections", []).append(
        {"Enabled": "TRUE", "Name": "t1", "PSK": "REPLACE_WITH_STRONG_PSK"})
    assert placeholder_findings(spec) == []


# ── LZR-033: a flag that deploys nothing must not read as delivered ────────

@pytest.mark.parametrize("field", ["enable_hss", "enable_dbss"])
def test_reserved_security_toggle_blocks(field):
    from lz_pipeline import rules
    spec = sheets()
    spec.setdefault("07_Security", {}).setdefault("Settings", {})[field] = True
    msgs = [f.message for f in rules.run_spec_rules(spec) if f.rule_id == "LZR-033"]
    assert any(field in m and "deploys nothing" in m for m in msgs)


def test_reserved_security_toggles_silent_when_false():
    from lz_pipeline import rules
    spec = sheets()
    spec.setdefault("07_Security", {}).setdefault("Settings", {}).update(
        {"enable_hss": False, "enable_dbss": False})
    assert not [f for f in rules.run_spec_rules(spec) if f.rule_id == "LZR-033"]


# ── lzctl gap add: the only sanctioned way to grow a decision set ──────────

@pytest.fixture
def assessed(tmp_path):
    """A real assess() output: neutral draft + decisions files."""
    dump = tmp_path / "dump.json"
    dump.write_text(json.dumps({
        "source_file": "q.xlsx", "meta": {"questionnaire_version": "1.1"},
        "answers": [{"ref": "C1", "question": "Q one?", "answer": "an answer",
                     "targets": ["01_Foundation.Settings"], "default_if_silent": ""}],
        "appendices": {},
    }), encoding="utf-8")
    r = run("lz_pipeline.lzctl", "assess", str(dump), "--customer", "t",
            "--workspace", str(tmp_path))
    assert r.returncode == 0, r.stdout + r.stderr
    return tmp_path / "specs" / "lz.spec.t.json"


def test_gap_add_registers_and_blocks_build(assessed, tmp_path):
    before = json.loads(assessed.read_text(encoding="utf-8"))["provenance"]

    r = run("lz_pipeline.lzctl", "gap", "add", "--spec", str(assessed),
            "--field", "08_DNS.ResolverRules[fwd].TargetIPs",
            "--question", "On-prem DNS IPs")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "G1" in r.stdout

    after = json.loads(assessed.read_text(encoding="utf-8"))["provenance"]
    assert after["decision_count"] == before["decision_count"] + 1
    assert after["decision_set_sha256"] != before["decision_set_sha256"]

    # the gap now blocks the build gate (exit 3), by ref
    b = run("lz_pipeline", "build", "--spec", str(assessed),
            "--envs-dir", str(tmp_path / "envs"))
    assert b.returncode == 3, b.stdout + b.stderr
    assert "OPEN G1" in b.stderr

    # ...and the human-readable agenda records it too
    md = assessed.with_name("lz.spec.t.decisions.md").read_text(encoding="utf-8")
    assert "Gaps found during interpretation" in md and "G1" in md


def test_gap_add_refuses_to_launder_an_edited_set(assessed):
    dec = assessed.with_name("lz.spec.t.decisions.json")
    doc = json.loads(dec.read_text(encoding="utf-8"))
    doc["items"][0]["question"] = "tampered"
    dec.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")

    r = run("lz_pipeline.lzctl", "gap", "add", "--spec", str(assessed),
            "--field", "X.Y.Z", "--question", "q")
    assert r.returncode == 3
    assert "altered outside this command" in r.stderr


def test_gap_add_rejects_a_field_that_names_nothing(assessed):
    """A target that resolves to no schema field tracks no schema field."""
    r = run("lz_pipeline.lzctl", "gap", "add", "--spec", str(assessed),
            "--field", "05_Network.HubSubnets and SpokeSubnets",
            "--question", "q")
    assert r.returncode == 2
    assert "names more than one thing" in r.stderr


def test_gap_add_takes_several_fields_and_restates_the_open_count(assessed):
    r = run("lz_pipeline.lzctl", "gap", "add", "--spec", str(assessed),
            "--field", "08_DNS.ResolverRules[fwd].TargetIPs",
            "--field", "08_DNS.ResolverEndpoints[ep].IPs",
            "--question", "On-prem DNS IPs")
    assert r.returncode == 0, r.stdout + r.stderr

    doc = json.loads(assessed.with_name("lz.spec.t.decisions.json")
                     .read_text(encoding="utf-8"))
    gap = next(i for i in doc["items"] if i["ref"] == "G1")
    assert gap["targets"] == ["08_DNS.ResolverRules[fwd].TargetIPs",
                              "08_DNS.ResolverEndpoints[ep].IPs"]

    # the agenda's heading counts the gate, not the questions assess saw
    md = assessed.with_name("lz.spec.t.decisions.md").read_text(encoding="utf-8")
    assert "## OPEN (1) - resolve before build" in md


def test_gap_list_is_not_blocked_by_an_altered_set(assessed):
    """Listing is read-only - and an altered set is exactly when somebody
    needs to see what is in there. Only `add` refuses."""
    run("lz_pipeline.lzctl", "gap", "add", "--spec", str(assessed),
        "--field", "08_DNS.ResolverRules[fwd].TargetIPs", "--question", "q")
    dec = assessed.with_name("lz.spec.t.decisions.json")
    doc = json.loads(dec.read_text(encoding="utf-8"))
    doc["items"][0]["question"] = "tampered"
    dec.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")

    r = run("lz_pipeline.lzctl", "gap", "list", "--spec", str(assessed))
    assert r.returncode == 0, r.stdout + r.stderr
    assert "G1" in r.stdout


def test_gap_add_needs_questionnaire_lineage(tmp_path):
    plain = tmp_path / "lz.spec.plain.json"
    plain.write_text(json.dumps({"format": "lz-spec-ir/1", "schema_version": "2.2",
                                 "customer": "p", "sheets": {}}), encoding="utf-8")
    r = run("lz_pipeline.lzctl", "gap", "add", "--spec", str(plain),
            "--field", "X.Y.Z", "--question", "q")
    assert r.returncode == 2 and "no questionnaire lineage" in r.stderr


# ── the app's decisions endpoints write ONLY resolutions ───────────────────

def test_app_resolve_writes_resolution_and_keeps_the_hash(assessed):
    from lz_app import server
    from lz_pipeline import model
    from lz_pipeline.lzctl import _decision_set_sha256

    run("lz_pipeline.lzctl", "gap", "add", "--spec", str(assessed),
        "--field", "08_DNS.ResolverRules[fwd].TargetIPs", "--question", "On-prem DNS IPs")

    server.STATE.update({"workspace": assessed.parents[1], "ir": model.load(assessed),
                         "source": str(assessed), "file": assessed.name})
    payload = server.decisions_payload()
    assert payload["available"] and payload["counts"]["blocking"] == 1

    server.resolve_decision("G1", "ANSWERED", "Network Eng", "10.100.1.53, 10.100.2.53")
    assert server.decisions_payload()["counts"]["blocking"] == 0

    # the immutable half is untouched: the spec's provenance hash still matches
    doc = json.loads(assessed.with_name("lz.spec.t.decisions.json").read_text(encoding="utf-8"))
    prov = json.loads(assessed.read_text(encoding="utf-8"))["provenance"]
    assert _decision_set_sha256(doc["items"]) == prov["decision_set_sha256"]


@pytest.mark.parametrize("args,msg", [
    (("G1", "MAYBE", "who", "why"), "status must be one of"),
    (("G1", "ANSWERED", "", "why"), "approved_by and reason"),
    (("G1", "ANSWERED", "who", "  "), "approved_by and reason"),
    (("NOPE", "ANSWERED", "who", "why"), "no decision"),
])
def test_app_resolve_rejects_unauditable_input(assessed, args, msg):
    from lz_app import server
    from lz_pipeline import model
    run("lz_pipeline.lzctl", "gap", "add", "--spec", str(assessed),
        "--field", "08_DNS.ResolverRules[fwd].TargetIPs", "--question", "q")
    server.STATE.update({"workspace": assessed.parents[1], "ir": model.load(assessed),
                         "source": str(assessed), "file": assessed.name})
    with pytest.raises(ValueError, match=msg):
        server.resolve_decision(*args)


# ── lzctl set: the mechanical write step ───────────────────────────────────

@pytest.fixture
def draft(tmp_path):
    p = tmp_path / "lz.spec.set.json"
    p.write_text(FIXTURE.read_text(encoding="utf-8"), encoding="utf-8")
    return p


def sheets_of(p):
    return json.loads(p.read_text(encoding="utf-8"))["sheets"]


@pytest.mark.parametrize("field,flag,value,expected", [
    ("Global.Settings.home_region", "--value", "ap-southeast-3", "ap-southeast-3"),
    ("05_Network.Settings.enable_hub", "--value", "no", False),
    ("08_DNS.ResolverRules[ad-forward].TargetIPs", "--value", "10.1.1.1, 10.1.1.2",
     ["10.1.1.1", "10.1.1.2"]),
    ("Global.Settings.home_region", "--json", '"ap-southeast-1"', "ap-southeast-1"),
])
def test_set_writes_the_coerced_value(draft, field, flag, value, expected):
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft), "--field", field, flag, value)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"set {field} = " in r.stdout
    s = sheets_of(draft)
    sheet, table = field.split(".")[0], field.split(".")[1].split("[")[0]
    tail = field.split(".")[-1]
    got = s[sheet][table][tail] if "[" not in field else \
        next(row[tail] for row in s[sheet][table] if row.get("Name") == "ad-forward")
    assert got == expected


def test_set_null_is_the_declared_unknown(draft):
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "Global.Settings.home_region", "--null")
    assert r.returncode == 0, r.stdout + r.stderr
    assert sheets_of(draft)["Global"]["Settings"]["home_region"] is None


@pytest.mark.parametrize("args,msg", [
    (("--field", "Global.Settings.nope", "--value", "x"), "has no field 'nope'"),
    (("--field", "Nope.Settings.x", "--value", "x"), "no table 'Nope.Settings'"),
    (("--field", "05_Network.Settings.enable_hub", "--value", "maybe"), "not a valid bool"),
    (("--field", "08_DNS.ResolverRules[ghost].TargetIPs", "--value", "1.1.1.1"),
     "addressing never invents a row"),
    (("--field", "08_DNS.ResolverRules.TargetIPs", "--value", "1.1.1.1"),
     "names a column but no row"),
])
def test_set_refuses_rather_than_guessing(draft, args, msg):
    before = draft.read_bytes()
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft), *args)
    assert r.returncode == 2, r.stdout + r.stderr
    assert msg in r.stderr
    assert draft.read_bytes() == before, "a refused set must not touch the spec"


# ── lzctl set [+]: row append, the last hand-written mutator ───────────────

def test_set_appends_a_row_then_addresses_it_by_name(draft):
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "05_Network.NATGateways[+]",
            "--json", '{"Name": "nat-hub", "Specification": "small"}')
    assert r.returncode == 0, r.stdout + r.stderr
    assert "appended 05_Network.NATGateways[0]" in r.stdout

    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "05_Network.NATGateways[nat-hub].Subnet",
            "--value", "snet-egress")
    assert r.returncode == 0, r.stdout + r.stderr
    assert sheets_of(draft)["05_Network"]["NATGateways"] == [
        {"Name": "nat-hub", "Specification": "small", "Subnet": "snet-egress"}]


def test_set_appends_to_a_list_single_table(draft):
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "05_Network.ERAvailabilityZones[+]",
            "--value", "ap-southeast-1c")
    assert r.returncode == 0, r.stdout + r.stderr
    assert sheets_of(draft)["05_Network"]["ERAvailabilityZones"][-1] == "ap-southeast-1c"


def test_row_addressing_by_index_and_row_delete(draft):
    """Round-4 findings: keyless-table mistakes were unrecoverable (no
    delete verb), and rows whose names contain dots were unaddressable.
    Index addressing + `--null` row delete close both."""
    for name in ("nat-a", "nat-b"):
        r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
                "--field", "05_Network.NATGateways[+]",
                "--json", f'{{"Name": "{name}"}}')
        assert r.returncode == 0, r.stdout + r.stderr

    # write by 0-based index
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "05_Network.NATGateways[1].Specification",
            "--value", "small")
    assert r.returncode == 0, r.stdout + r.stderr
    assert sheets_of(draft)["05_Network"]["NATGateways"][1]["Specification"] == "small"

    # delete by name, then confirm the survivor; delete by index also works
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "05_Network.NATGateways[nat-a]", "--null")
    assert r.returncode == 0, r.stdout + r.stderr
    rows = sheets_of(draft)["05_Network"]["NATGateways"]
    assert [x["Name"] for x in rows] == ["nat-b"]
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "05_Network.NATGateways[0]", "--null")
    assert r.returncode == 0, r.stdout + r.stderr
    assert sheets_of(draft)["05_Network"]["NATGateways"] == []

    # a missing row refuses cleanly
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "05_Network.NATGateways[ghost]", "--null")
    assert r.returncode == 2 and "to delete" in r.stderr


def test_dotted_row_name_is_addressable(draft):
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft),
            "--field", "01_Foundation.TrustedServices[service.LTS].DelegatedAdmin",
            "--value", "acme-logarchive")
    assert r.returncode == 0, r.stdout + r.stderr
    rows = sheets_of(draft)["01_Foundation"]["TrustedServices"]
    lts = next(x for x in rows if x.get("Name") == "service.LTS")
    assert lts["DelegatedAdmin"] == "acme-logarchive"


@pytest.mark.parametrize("args,msg", [
    (("--field", "05_Network.NATGateways[+]", "--json", '{"Nope": 1}'),
     "no column 'Nope'"),
    (("--field", "05_Network.NATGateways[+]", "--value", "x"),
     "row append takes the row as JSON"),
    (("--field", "05_Network.NATGateways[+]", "--json", "{}"),
     "non-empty object"),
    (("--field", "05_Network.Settings[+]", "--json", "{}"),
     "scalar table"),
    (("--field", "05_Network.NATGateways[+].Name", "--json", '"x"'),
     "appends a whole row"),
])
def test_row_append_refuses_rather_than_guessing(draft, args, msg):
    before = draft.read_bytes()
    r = run("lz_pipeline.lzctl", "set", "--spec", str(draft), *args)
    assert r.returncode == 2, r.stdout + r.stderr
    assert msg in r.stderr
    assert draft.read_bytes() == before, "a refused append must not touch the spec"


# ── LZR-035: an answered target covered by an OPEN gap is owed, not dropped ─

def _lzr035(spec, declared, answered):
    from lz_pipeline import rules
    rules.set_decisions_context(declared=declared, answered=answered, loaded=True)
    try:
        return [f.message for f in rules.run_spec_rules(spec)
                if f.rule_id == "LZR-035"]
    finally:
        rules.set_decisions_context()


def test_answered_empty_table_is_a_dropped_answer_with_a_real_way_out():
    spec = sheets()
    spec["05_Network"]["NATGateways"] = []
    msgs = _lzr035(spec, (), {"05_Network.NATGateways": "C15"})
    assert any("NATGateways is empty" in m and "C15" in m for m in msgs)
    # the remediation must be executable: `gap add`, not "re-open" (state is
    # inside the provenance hash, so re-opening is not a thing anyone can do)
    assert all("re-open" not in m for m in msgs)
    assert any("lzctl gap add --field 05_Network.NATGateways" in m for m in msgs)


@pytest.mark.parametrize("declared", [
    "05_Network.NATGateways",          # a gap on the table itself
    "05_Network.NATGateways.Subnet",   # a gap on one of its columns
])
def test_covering_open_gap_silences_the_dropped_answer(declared):
    """The round-2 loop: prose answers intent (C15 'centralized egress'),
    the concrete rows are owed - registering the gap must clear the error,
    exactly as LZR-034 already honors declared scalars."""
    spec = sheets()
    spec["05_Network"]["NATGateways"] = []
    assert _lzr035(spec, {declared}, {"05_Network.NATGateways": "C15"}) == []


def test_table_level_gap_covers_an_answered_scalar():
    spec = sheets()
    spec["05_Network"]["EnterpriseRouter"]["er_asn"] = None
    path = "05_Network.EnterpriseRouter.er_asn"
    assert _lzr035(spec, set(), {path: "D5"}) != []
    assert _lzr035(spec, {"05_Network.EnterpriseRouter"}, {path: "D5"}) == []


def test_unrelated_gap_does_not_silence_a_dropped_answer():
    spec = sheets()
    spec["05_Network"]["NATGateways"] = []
    msgs = _lzr035(spec, {"08_DNS.ResolverRules"},
                   {"05_Network.NATGateways": "C15"})
    assert any("NATGateways is empty" in m for m in msgs)
