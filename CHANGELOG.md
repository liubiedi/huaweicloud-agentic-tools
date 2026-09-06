# Changelog

## Unreleased

### Added

- **`null` is the declared unknown**: every typed slot accepts null for "not known yet"; `lzctl set` writes one value at a schema-validated path (`--value` typed coercion, `--json`, `--null`), and `lzctl set --field 'Sheet.Table[+]' --json '{...}'` appends a row with every column checked against the schema — the last spec write that used to need a hand-rolled JSON mutator. **LZR-034** errors on an unset required scalar no OPEN decision tracks; **LZR-035** errors on an ANSWERED decision whose target holds nothing — unless a registered OPEN gap covers the target (the answer settled intent; the concrete values are owed and block build); **LZR-036** errors on an enabled network plane with no VPCs. Validation at 0 errors with OPEN gaps outstanding is now a legitimate, reachable state; `lzctl build` still exits 3 until every OPEN item carries a resolution.

- **Decisions gate reaches the UI**: the app's **Decisions & gaps** view resolves OPEN decisions and fills gap values (resolution + who decided + why), writing only the `resolution` block so the provenance hash over the immutable decision set survives. `lzctl gap add` registers an agent-discovered gap as an OPEN item and refuses to re-stamp an already-edited set.
- **`lzctl status --json`**: the phase report as a machine contract, every phase derived from artifacts on disk rather than a stored pointer — edit the spec and the tree reports `recheck` on its own. `lzctl back <phase>` records a journaled re-entry (who, why, what it invalidates) and deletes nothing. Exit 0 on track / 2 recheck / 3 blocked.
- **Rendering design system** for agent replies (`skills/huawei-cloud-landing-zone/SKILL.md` + `rendering.md`): verdict first, exceptions only, one Next block with its runner/cloud/undo provenance, words only. Phases render zero-padded (`03-build`). The CLI emits data; the agent renders it.
- **LZR-032** fails validation on unresolved `REPLACE_WITH_` placeholders (VPN PSK exempt by design); **LZR-033** blocks `enable_hss` / `enable_dbss`, now documented as RESERVED.

### Changed

- **Round-4 fleet findings, fixed minimal** (40 real agent runs, two models): `lzctl assess` shapes its neutral draft from `schema.py` instead of the stale example fixture (fresh drafts now carry every sheet - 11_SGACL included - all fields, and the current schema_version); a blank schema default whose description says "Leave blank to ..." counts as a documented answer, not a missing value (LZR-034 stops demanding gaps for it); spec paths survive row names containing dots (`TrustedServices[service.LTS]`); rows are addressable by 0-based index and `set --field 'Sheet.Table[row]' --null` deletes one (the only row-level verb - a keyless-table mistake no longer needs `assess --force`); `set --help` documents the list-single one-element-per-`[+]` contract; D4's questionnaire wiring points at the real `identity_center_alias` sheet and D23's guidance says the commercial arrangement stays out of the spec; the skill states plainly that structural-integrity errors (email completeness, min-rows, uniqueness, references) are gap-proof by design.
- **Declared unknowns now clear every validation layer** (round-3 benchmark findings). `validate()`'s required and conditional-required errors, and LZR-036's enabled-but-empty network planes, are waived when a registered OPEN gap covers the target — the same contract LZR-034/035 already honored; `build` stays strict because its decisions gate demands resolutions first. `Enabled` is now part of the setter's column contract on toggled object tables (the schema always auto-prepended it; `specpath` didn't know, so rows copied from the example spec were refused). Questionnaire dumps (`*dump.json`) are excluded from exports and documented as secret-bearing working material — `lzctl intake` copies answers verbatim, pasted secrets included. `gap add --help` now says which flags `add` requires. Re-scoring the round-3 corpus with these fixes: 216 -> 174 errors, validator-clean runs 1/20 -> 2/20, and most remaining runs sit at 1-5 genuinely actionable errors.
- **One determinism baseline.** The goldens tree (`pipeline/lz_pipeline/tests/goldens/`, 1,609 lines), `test_goldens.py`, and `make_goldens.py` are gone: they byte-duplicated the generated slice of `terraform/envs-example`, which the harness's `regen-diff` check already compares against a fresh build. To bless an intended output change, rebuild envs-example in place from the example fixture and commit the diff (CONTRIBUTING.md §schema-changes). The second committed example-spec copy (`pipeline/lz_spec/lz.spec.example.json`, kept in sync only by a test) is also gone — the fixture at `pipeline/lz_pipeline/fixtures/example.spec.json` is the one example, and the app USER-GUIDE now says to copy it into `specs/` (the dropdown never read the deleted path).
- **`export_handover.py` folded into `export_v2.py`**. It existed only to be imported and have its exclusion globals reassigned at runtime; the exporter is now self-contained and the doctrine guard that anticipated the fold targets it directly. The secmaster feature strip was a six-operation mini-DSL driving one registry entry against one env — now straight-line code. Handover output verified byte-identical across 131 files.
- **`deps.json` has one owner**: `lzctl deps` (and `lzctl build`). `depsgraph.py` keeps its library API but no longer ships a second CLI; its topological sort is now `graphlib.TopologicalSorter`. LZR-008's remediation text names the current command.
- Removed flags nothing passed (`plan_triage --rules`, `export_v2 --no-docs`, `depsgraph --quiet`, the eval `--adapter`) and one-caller wrappers, duplicated emitter write loops, and an always-empty error-scoping layer. Generated env tree verified byte-identical across 144 files.

### Removed

- Derived artifacts no longer committed: eval `scores.json` / `scores-rescored.json` (nothing reads them back; `run_eval.py --rescore <dir>` regenerates them from the committed transcripts), superseded scratch runs, and archived copies of the bench scripts that had drifted from their `e2e_bench/` originals. `tests/evaluation/results/` and `releases/` are now gitignored; the runs of record predate the rule and remain.
- `fixtures/make_example.py` — a 368-line generator kept beside its committed output with zero callers, synchronized by hand.

- **Breaking (state layout)**: four env state keys carried a stale numbering (`07-security` wrote to `envs/10-security/`, `08-network-dns` to `envs/07-dns/`, `09-network-cfw` to `envs/08-cfw/`, `11-network-sgacl` to `envs/09-network-sgacl/`). Keys now match the env directory names, guarded by a regression test. Deployments created from 0.1.0 need a one-time `terraform init -migrate-state` per affected env.

## 0.1.0 — 2026-08-31

Initial public release.

### Capabilities

- **Spec pipeline**: JSON spec as the authoritative store (the Excel workbook is a generated artifact); `intake` → `assess` → `validate` → `build` with byte-identical regeneration enforced by the harness.
- **Runner (`lzctl`)**: ordered plan/apply from `deps.json`, plan triage (exit 0 clean / 2 changes / 3 destructive), state backup before every apply, drift sweeps, post-apply `verify` gate, `report` evidence bundles, `adopt` import helper, `preflight` environment checks.
- **Terraform library**: 15 plain-HCL modules + 12-env scaffold covering the 9 CAF governance domains, with a vendored-snapshot sync story (`tools/sync_modules.py`, `PROVENANCE.md`).
- **Agent skill** (`skills/huawei-cloud-landing-zone/`): phase-routed domain design rules over 27 topic assets; companion `questionnaire-to-spec` skill.
- **Delivery**: profile-driven artifact export (`export_v2`) with feature strips, release metadata, and the standalone runner shipped inside; generated customer doc set (`lzctl docs`).
- **Assessment chain**: schema-derived questionnaire with build-failing coverage check; mechanical dump; deterministic three-bucket assessment that never guesses.
- **Verification**: 7-check regression harness (`python -m lz_spec.verify_pipeline`) + pytest bridge; generated JSON Schema for model-agnostic spec validation.

### Safety additions in this assembly

- **Retry-once** on documented transient platform signatures only (`LZ_TRANSIENT_SIGNATURES`, default `LTS.2101,EPS.0004`) — re-plan + apply, never a stale-plan replay.
- **Destructive double-confirm**: exit-3 plans block apply; proceeding needs `--allow-destroy` plus a typed env-name confirmation that `--yes` never bypasses (`--destroy-confirm <env>` for CI).
- **Fail-loud region**: `Global.Settings.home_region` is required with no default — a missing region fails the build instead of deploying somewhere plausible.
- **Leak guard**: export tests derive forbidden customer tokens (including on-prem CIDR prefixes, domains, and email domains) from every non-example profile and scan example specs and exported artifacts.

### Hardening and tooling added during review

- E2E engineer-roleplay model benchmark (`tests/evaluation/e2e_bench/`, `--smoke` for a free setup check); run of record committed under `tests/evaluation/results/e2e-roleplay-20260831/`.
- Skill install routes: `npx skills` one-liner, Claude Code plugin marketplace (`.claude-plugin/`), manual copy.
- Plain-terms sweep of user-facing text: customer ID (was slug), `--spec` on build/docs (`--ir` kept as alias), platform rules, design rules, authoritative store.
- Documented where Claude coupling lives vs the model-independence claim (README + bench scope note).
- Cleanup: unreferenced cicd-plan.md removed; legacy import shim bypassed.
- Security-review hardening (two external rounds): app UI CSRF token + origin check + workspace-confined save paths; export refuses to clear non-export targets and fails closed on strip misses; apply blocked on placeholder VPN PSKs; secrets never .bak'd; atomic/owner-checked apply lock with per-env refresh; saved-plan staleness covers the modules tree; CI terraform validation made real; CFW rejects multiple domain groups per rule; sync_modules overlap guard.
