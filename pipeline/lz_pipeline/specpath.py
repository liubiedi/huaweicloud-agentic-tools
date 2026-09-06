"""Resolve a spec field path against the schema.

One vocabulary for the three places that name a field: `lzctl gap add
--field`, `lzctl set --field`, and the decisions file's `targets`. Before
this module each of them accepted free text, so a gap could target
"05_Network.HubSubnets and SpokeSubnets" - prose that resolves to nothing
and tracks nothing.

Accepted forms:
    Sheet.Table                      a whole table
    Sheet.Table.field                a scalar field
    Sheet.Table[row].Column          one column of one row
"""

import re

from lz_spec import schema as wb_schema

_ROW = re.compile(r"^([^\[\]]+)\[([^\[\]]*)\]$")


class PathError(ValueError):
    """The path does not name anything in the schema."""


def _tables():
    out = {}
    for sh in wb_schema.SHEETS:
        for t in sh.tables:
            out[f"{sh.name}.{t.name}"] = t
    return out


def _columns(t):
    """[(name, type)] as the JSON IR actually carries them.

    The schema auto-prepends an `Enabled` bool to every non-mandatory
    object table (gen_template does the same for the workbook), so rows
    copied from the example spec legitimately carry it - rejecting it here
    made the documented shape reference unusable for `set` (found by the
    round-3 benchmark runs)."""
    cols = [(c[0], (c[1] if len(c) > 1 else "string") or "string")
            if isinstance(c, (tuple, list))
            else (getattr(c, "name", c), getattr(c, "type", "string") or "string")
            for c in (t.columns or [])]
    if (t.kind == "object-table" and not getattr(t, "mandatory", False)
            and not any(n == "Enabled" for n, _ in cols)):
        cols.insert(0, ("Enabled", "bool"))
    return cols


def parse(path: str) -> dict:
    """{sheet, table, field, row, column, kind} - or raise PathError.

    `field` is set for a scalar target, `column`/`row` for an object-table
    cell; both are None when the path names the table itself.
    """
    raw = (path or "").strip()
    if not raw:
        raise PathError("empty path")
    if any(sep in raw for sep in (",", " and ", "/")):
        raise PathError(
            f"{raw!r} names more than one thing - give one path per "
            f"--field (repeat the flag for several)")

    # Split on dots OUTSIDE brackets only: row names may contain literal
    # dots (every 01_Foundation.TrustedServices row is named service.<X>),
    # and a naive split shredded them (round-4 finding).
    parts = re.split(r"\.(?![^\[]*\])", raw)
    if len(parts) < 2:
        raise PathError(f"{raw!r} is not a Sheet.Table path")

    tables = _tables()
    sheet, table = parts[0], parts[1]
    m = _ROW.match(table)
    row = None
    if m:
        table, row = m.group(1), m.group(2)
    key = f"{sheet}.{table}"
    if key not in tables:
        raise PathError(f"{raw!r}: no table {key!r} in the schema")
    t = tables[key]

    rest = ".".join(parts[2:])
    m = _ROW.match(rest) if rest else None
    if m:
        rest, row = m.group(1), m.group(2)

    if not rest:
        return {"sheet": sheet, "table": table, "field": None, "row": row,
                "column": None, "kind": t.kind}

    if t.kind == "scalar":
        names = [getattr(r, "name", r) for r in (t.rows or [])]
        if rest not in names:
            raise PathError(f"{raw!r}: {key} has no field {rest!r} "
                            f"(fields: {', '.join(map(str, names))})")
        return {"sheet": sheet, "table": table, "field": rest, "row": None,
                "column": None, "kind": "scalar"}

    cols = [n for n, _ in _columns(t)]
    if rest not in cols:
        raise PathError(f"{raw!r}: {key} has no column {rest!r} "
                        f"(columns: {', '.join(cols)})")
    return {"sheet": sheet, "table": table, "field": None, "row": row,
            "column": rest, "kind": t.kind}


def normalize(path: str) -> str:
    """Canonical `Sheet.Table[.field|.Column]` with any row index dropped.

    Comparing a declared target to a finding's location has to ignore which
    ROW carried the gap: a gap on SpokeVPCs[app-prod].CIDR declares the
    CIDR column, and every row of it is the same unknown.
    """
    p = parse(path)
    tail = p["field"] or p["column"]
    return f"{p['sheet']}.{p['table']}" + (f".{tail}" if tail else "")


def field_type(path: str) -> str:
    """Declared type of a scalar field or an object-table column ('string'
    when unknown, 'json' when the path names a whole table)."""
    p = parse(path)
    t = _tables()[f"{p['sheet']}.{p['table']}"]
    if p["column"]:
        for n, typ in _columns(t):
            if n == p["column"]:
                return typ
        return "string"
    if p["kind"] != "scalar" or not p["field"]:
        return "json"
    for r in (t.rows or []):
        if getattr(r, "name", r) == p["field"]:
            return getattr(r, "type", "string") or "string"
    return "string"


def required_scalars() -> list:
    """Scalar paths the schema gives no default for - a value must be
    supplied or the gap declared.

    An empty default usually means "no sensible default exists" (see
    kms_audit_alias) - EXCEPT where the field's own description says
    "Leave blank to ...": there, blank IS the documented final answer, and
    treating it as unsupplied forced agents to register gaps for values
    that were never unknown (round-4 finding, 9+ runs)."""
    out = []
    for sh in wb_schema.SHEETS:
        if sh.name in wb_schema.INFO_SHEETS or sh.name == "_meta":
            continue
        for t in sh.tables:
            if t.kind != "scalar":
                continue
            for r in (t.rows or []):
                name = getattr(r, "name", r)
                if getattr(r, "type", "string") != "string":
                    continue
                if getattr(r, "default", "") != "":
                    continue
                desc = getattr(r, "description", "") or ""
                if re.search(r"leave (?:this )?blank", desc, re.I):
                    continue
                out.append(f"{sh.name}.{t.name}.{name}")
    return out
