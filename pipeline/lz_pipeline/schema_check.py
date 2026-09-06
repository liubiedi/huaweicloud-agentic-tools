"""Structural validation of a spec IR against schema.SHEETS.

Dependency-free (no jsonschema): the workbook schema in lz_spec/schema.py is
the source of truth; this module checks an IR's sheets/tables/columns/types
against it.

Severity model:
  error - wrong container shape (dict vs list), wrong value type after
          coercion, unknown table kind
  warn  - unknown sheet/table/column/field (forward-compatible additions),
          missing sheet/table (legitimately empty)
"""


from lz_spec import schema as wb_schema


_BOOL_STRS = {"true", "false", "1", "0", "yes", "no", "y", "n"}

# Sheets a complete spec may legitimately omit, so their absence is not news:
# 11_SGACL is reserved (its tables deploy nothing yet) and 10_VPN exists only
# for hybrid connectivity. Both are badged optional in the app. A warning that
# fires on every spec ever written trains readers to ignore the whole list.
OPTIONAL_SHEETS = {"10_VPN", "11_SGACL"}


def _type_ok(v, typ: str) -> bool:
    """Accept the value forms the builders can actually consume.

    parse_workbook() coerces scalar-table values but leaves object-table cells
    raw (builders apply _truthy()/int() at consumption), so bool columns hold
    real booleans OR "TRUE"/"FALSE" strings, and int columns hold numbers OR
    numeric strings.
    """
    if v is None:
        return True
    # An unresolved placeholder is LZR-032's to report; complaining about its
    # TYPE as well is a second error for one unfilled field.
    from .rules import is_placeholder
    if is_placeholder(v):
        return True
    t = (typ or "string").lower()
    if t == "bool":
        if isinstance(v, bool):
            return True
        return isinstance(v, str) and v.strip().lower() in _BOOL_STRS
    if t == "int":
        if isinstance(v, bool):
            return False
        if isinstance(v, (int, float)):
            return True
        if isinstance(v, str):
            try:
                float(v)
                return True
            except ValueError:
                return False
        return False
    if t == "csv-list":
        return isinstance(v, (list, str))
    if t == "json":
        return True
    return isinstance(v, (str, int, float, bool))


def check(ir: dict) -> tuple:
    """(errors, warnings) for an IR dict."""
    errors, warnings = [], []
    sheets = ir.get("sheets")
    if not isinstance(sheets, dict):
        return (["IR has no 'sheets' object"], [])

    known = {s.name: s for s in wb_schema.SHEETS if s.name not in wb_schema.INFO_SHEETS}
    for name in sheets:
        if name not in known:
            warnings.append(f"unknown sheet {name!r} (ignored by builders)")

    for sname, sdef in known.items():
        sdata = sheets.get(sname)
        if sdata is None:
            # _meta is bookkeeping, not a user sheet: assess's schema-shaped
            # skeleton rightly omits it, and warning about it put one
            # permanent cosmetic warning on every fresh draft (round 5).
            if sname not in OPTIONAL_SHEETS and sname != "_meta":
                warnings.append(f"sheet {sname!r} missing (treated as empty)")
            continue
        if not isinstance(sdata, dict):
            errors.append(f"{sname}: expected an object of tables, got {type(sdata).__name__}")
            continue
        tdefs = {t.name: t for t in sdef.tables}
        for tname in sdata:
            if tname not in tdefs:
                warnings.append(f"{sname}.{tname}: unknown table (ignored by builders)")
        for tname, tdef in tdefs.items():
            tdata = sdata.get(tname)
            if tdata is None:
                continue
            if tdef.kind == "scalar":
                if not isinstance(tdata, dict):
                    errors.append(f"{sname}.{tname}: scalar table must be an object, got {type(tdata).__name__}")
                    continue
                fields = {kv.name: kv for kv in tdef.rows}
                for k, v in tdata.items():
                    if k not in fields:
                        warnings.append(f"{sname}.{tname}.{k}: unknown field")
                    elif not _type_ok(v, fields[k].type):
                        errors.append(f"{sname}.{tname}.{k}: expected {fields[k].type}, got {type(v).__name__} ({v!r})")
            elif tdef.kind == "list-single":
                if not isinstance(tdata, list):
                    errors.append(f"{sname}.{tname}: list table must be an array, got {type(tdata).__name__}")
            elif tdef.kind == "object-table":
                if not isinstance(tdata, list):
                    errors.append(f"{sname}.{tname}: object table must be an array of rows, got {type(tdata).__name__}")
                    continue
                cols = {c[0]: c[1] for c in tdef.columns}
                cols.setdefault("Enabled", "bool")
                for i, row in enumerate(tdata):
                    if not isinstance(row, dict):
                        errors.append(f"{sname}.{tname}[{i}]: row must be an object")
                        continue
                    for k, v in row.items():
                        if k not in cols:
                            warnings.append(f"{sname}.{tname}[{i}].{k}: unknown column")
                        elif not _type_ok(v, cols[k]) and cols[k] in ("bool", "int"):
                            errors.append(f"{sname}.{tname}[{i}].{k}: expected {cols[k]}, got {type(v).__name__} ({v!r})")
            else:
                errors.append(f"{sname}.{tname}: unknown table kind {tdef.kind!r}")
    return errors, warnings
