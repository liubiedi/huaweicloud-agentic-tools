"""Round-3 benchmark fixes: required-field errors honor covering OPEN gaps,
the Enabled row-toggle is part of the setter's column contract, and
questionnaire dumps never ship in an export.
"""

import json
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
FIXTURE = REPO / "pipeline" / "lz_pipeline" / "fixtures" / "example.spec.json"


def sheets():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))["sheets"]


# ── required errors vs declared gaps (the WAF case from run 11) ────────────

def _gap(*targets):
    return {"items": [{"ref": "G1", "state": "OPEN", "question": "q",
                       "targets": list(targets), "resolution": None}]}


def test_conditional_required_waived_by_covering_gap():
    from lz_pipeline.core.cli import check_spec
    spec = sheets()
    spec["07_Security"]["WAF"].update({
        "enable_waf": True, "waf_vpc": None, "waf_subnet": None,
        "waf_availability_zone": None})

    plain = [e for e in check_spec(spec) if "required when enable_waf" in e]
    assert len(plain) == 3, plain

    dec = _gap("07_Security.WAF.waf_vpc", "07_Security.WAF.waf_subnet",
               "07_Security.WAF.waf_availability_zone")
    covered = [e for e in check_spec(spec, decisions=dec)
               if "required when enable_waf" in e]
    assert covered == []


def test_table_level_gap_covers_its_fields():
    from lz_pipeline.core.cli import check_spec
    spec = sheets()
    spec["07_Security"]["WAF"].update({"enable_waf": True, "waf_vpc": None,
                                       "waf_subnet": None,
                                       "waf_availability_zone": None})
    covered = [e for e in check_spec(spec, decisions=_gap("07_Security.WAF"))
               if "required when enable_waf" in e]
    assert covered == []


def test_settings_omitting_message_form_is_matched():
    """validate() prints "Global.home_region is required" without the
    Settings table; the declared target carries it."""
    from lz_pipeline.rules import drop_declared_unknowns
    errs = ["Global.home_region is required"]
    assert drop_declared_unknowns(errs, {"Global.Settings.home_region"}) == []
    assert drop_declared_unknowns(errs, {"Global.Settings.state_bucket_name"}) == errs


def test_structural_errors_are_never_waivable():
    from lz_pipeline.rules import drop_declared_unknowns
    errs = ["01_Foundation.CoreAccounts must have at least 2 rows (log + security)"]
    assert drop_declared_unknowns(errs, {"01_Foundation.CoreAccounts"}) == errs


def test_no_decisions_means_no_waiving():
    from lz_pipeline.core.cli import check_spec
    spec = sheets()
    spec["Global"]["Settings"]["home_region"] = None
    assert any("home_region is required" in e for e in check_spec(spec))


def test_enabled_plane_with_declared_rows_is_not_silent_emptiness():
    """LZR-036: enable_hub on + HubVPCs empty is an error - unless an OPEN
    gap declares the rows owed (sparse profiles withhold CIDRs by design)."""
    from lz_pipeline import rules
    spec = sheets()
    spec["05_Network"]["Settings"]["enable_hub"] = True
    spec["05_Network"]["Settings"]["enable_spoke"] = True
    spec["05_Network"]["HubVPCs"] = []
    spec["05_Network"]["SpokeVPCs"] = []
    rules.set_decisions_context(declared={"05_Network.HubVPCs"}, loaded=True)
    try:
        msgs = [f.message for f in rules.run_spec_rules(spec)
                if f.rule_id == "LZR-036"]
    finally:
        rules.set_decisions_context()
    assert not any("HubVPCs" in m for m in msgs)          # declared -> waived
    assert any("SpokeVPCs" in m for m in msgs)            # undeclared -> error
    assert any("lzctl gap add" in m for m in msgs)        # executable way out


# ── Enabled is a real column on toggled tables (run 22/24/29 defect) ───────

def test_enabled_is_part_of_the_row_contract():
    from lz_pipeline import specpath
    # the example spec's own rows carry it; the setter must accept it
    assert specpath.field_type("02_Finance.CostCenters[x].Enabled") == "bool"
    assert specpath.field_type("04_Perimeter.SCPs[x].Enabled") == "bool"
    p = specpath.parse("04_Perimeter.PredefinedTags[x].Enabled")
    assert p["column"] == "Enabled"


def test_enabled_rejected_where_the_schema_forbids_it():
    """Mandatory tables have no toggle (presence in the table = enabled)."""
    from lz_spec import schema
    from lz_pipeline import specpath
    victim = next(f"{sh.name}.{t.name}"
                  for sh in schema.SHEETS for t in sh.tables
                  if t.kind == "object-table" and getattr(t, "mandatory", False)
                  and not any((c[0] if isinstance(c, (tuple, list)) else c) == "Enabled"
                              for c in (t.columns or [])))
    with pytest.raises(specpath.PathError):
        specpath.parse(f"{victim}[x].Enabled")


def test_example_rows_pass_the_setter_contract():
    """Every key in every example object-table row must resolve as a column -
    the example is the documented shape reference (round-3 runs burned time
    on the mismatch)."""
    from lz_spec import schema
    from lz_pipeline import specpath
    spec = sheets()
    bad = []
    for sh in schema.SHEETS:
        for t in sh.tables:
            if t.kind != "object-table":
                continue
            for row in (spec.get(sh.name, {}).get(t.name) or []):
                if not isinstance(row, dict):
                    continue
                for k in row:
                    try:
                        specpath.parse(f"{sh.name}.{t.name}[x].{k}")
                    except specpath.PathError:
                        bad.append(f"{sh.name}.{t.name}.{k}")
    assert not bad, sorted(set(bad))


# ── round-4 fleet findings ─────────────────────────────────────────────────

def test_neutral_skeleton_covers_the_whole_schema():
    """assess's draft used to be a neutralized copy of the example fixture,
    so sheets/fields the fixture predated (11_SGACL, half of CloudFirewall)
    were silently absent from every fresh draft."""
    from lz_pipeline.lzctl import _skeleton
    from lz_spec import schema as wb
    sk = _skeleton()
    assert "11_SGACL" in sk and sk["11_SGACL"]["SecurityGroups"] == []
    cfw = sk["05_Network"]["CloudFirewall"]
    declared = {getattr(r, "name", r) for t in
                [x for s in wb.SHEETS if s.name == "05_Network" for x in s.tables
                 if x.name == "CloudFirewall"] for r in (t.rows or [])}
    assert set(cfw) == declared and all(v is None for v in cfw.values())


def test_leave_blank_fields_are_not_required():
    """A blank default whose description says "Leave blank to ..." is a
    documented answer, not a missing value - LZR-034 must not demand a gap
    for it. Fields with no sanctioned blank stay required."""
    from lz_pipeline.specpath import required_scalars
    req = set(required_scalars())
    assert "01_Foundation.Settings.identity_center_alias" not in req
    assert "04_Perimeter.ConfigSetup.recorder_smn_topic_urn" not in req
    assert "06_Observability.AuditSettings.cts_no_transfer_accounts" not in req
    assert "06_Observability.AuditSettings.kms_audit_alias" in req


def test_row_names_may_contain_dots():
    """Every 01_Foundation.TrustedServices row is named service.<X>; the
    path splitter must not shred the bracket content."""
    from lz_pipeline import specpath
    p = specpath.parse("01_Foundation.TrustedServices[service.LTS].DelegatedAdmin")
    assert p["row"] == "service.LTS" and p["column"] == "DelegatedAdmin"
    assert specpath.normalize(
        "01_Foundation.TrustedServices[service.LTS].DelegatedAdmin"
    ) == "01_Foundation.TrustedServices.DelegatedAdmin"


# ── questionnaire dumps never ship (run 29's PSK survived in the dump) ─────

def test_export_never_ships_a_questionnaire_dump():
    from lz_pipeline.export_v2 import EXCLUDE_NAMES, excluded
    assert excluded(Path("jobtmp/dump.json"), EXCLUDE_NAMES)
    assert excluded(Path("runs/x/answers.dump.json"), EXCLUDE_NAMES)
    assert not excluded(Path("02-finance/terraform.tfvars.json"), EXCLUDE_NAMES)
