---
name: questionnaire-to-spec
description: Convert a filled LZ Assessment Questionnaire (xlsx) into a draft lz.spec.<customer>.json plus a decisions file the build gate enforces. Use when the user provides a completed assessment questionnaire or asks to turn questionnaire answers into a spec.
---

# Questionnaire → draft spec

Invocation: `/questionnaire-to-spec <filled.xlsx> customer=<id> [workspace=<dir>]`
(or any natural-language request that provides a filled questionnaire).

Input: a filled `HuaweiCloud-LZ-Assessment-Questionnaire.xlsx` (any path) and a
customer ID (lowercase, e.g. `acme`). **Inference rule:** take the workbook
from an explicitly attached file, an explicit path, or exactly one unambiguous
matching artifact in the workspace — ask only when multiple candidates exist.
Ask for the customer ID whenever it cannot be established safely; never
derive it from guesswork.

Output, under `<workspace>/specs/`:
- `lz.spec.<customer>.json` — the draft (starts NEUTRAL: every value unset)
- `lz.spec.<customer>.decisions.md` — human-readable decision agenda
- `lz.spec.<customer>.decisions.json` — machine-readable; **`lzctl build` refuses
  to run while it contains OPEN items without a recorded resolution**

This skill applies the huawei-cloud-landing-zone skill's intake design rules
(assets/intake-questionnaire, assets/discovery-protocol); load that skill alongside.

**The contract: you decide and ask; the pipeline executes and gates; the human
confirms in the app.** Facts are copied verbatim by `lzctl intake`;
classification and the neutral draft come from `lzctl assess`; your judgment
lands only in reviewable artifacts (the spec diff, decision resolutions) —
never in bypassed gates. Every value the customer must supply or approve is
entered by them in `lz-app` (step 6), not typed by you into JSON.

## Steps

1. **Intake (mechanical, no interpretation):**
   `lzctl intake <filled.xlsx> -o <jobtmp>/dump.json`
   The dump has every answer joined to its wiring `targets`
   (`Sheet.Table[.field]`) and `default_if_silent`.

2. **Assess (deterministic, never guesses):**
   `lzctl assess <jobtmp>/dump.json --customer <customer> --workspace <workspace>`
   This writes the three outputs above. The draft is a schema-shaped skeleton
   with every table empty and every scalar blank — it FAILS `lzctl validate`
   until you interpret answers into it. That failure is the design: no
   deployable value exists that nobody decided.

3. **Interpret answers into the draft** (your job — the only step with judgment):
   - **Every spec write is mechanical — `lzctl set`, never a hand-rolled JSON
     mutator.** Scalars: `lzctl set --spec <spec> --field
     "05_Network.Settings.spoke_private_supernet" --value 10.20.0.0/14`
     (typed coercion; `--json` for lists and exact types; `--null` to declare
     a value not known yet). One cell: `--field "Sheet.Table[<row-name>].Column"`.
     A new row: `--field "Sheet.Table[+]" --json '{"Column": ...}'`. Every
     path and column is validated against the schema, so a misspelled key
     refuses instead of landing where no builder reads and no validator looks.
   - **Appendix rows are facts — copy VERBATIM from the dump JSON.** Never
     retype or "normalize" CIDRs, IPs, emails, account or team names. Rows
     map near-1:1: Appendix A → `01_Foundation` accounts/OUs, B → `05_Network`
     CIDR tables + `spoke_private_supernet`, C → `03_Identity` groups/users/
     permission sets/assignments.
   - **Prose answers are interpreted** against their `targets`. Consult the
     packaged `example.spec.json` for field shapes and `schema.py` for
     meanings — copy STRUCTURE from the example, never its values.
   - **Resource names are inferred, not asked one by one.** Derive every
     resource `Name`-class value (VPCs, subnets, EIPs, NATs, buckets, vaults,
     log groups, endpoints, ...) from the customer's stated naming convention,
     applied consistently across all sheets; honor service limits (bucket
     names lowercase + globally unique). No stated convention → use the
     question's documented default pattern and record the convention as a
     DEFAULTED item so the customer reviews it once, not per resource. Names
     are proposals — a name the customer wrote explicitly (any appendix row)
     stays verbatim and is never "normalized" to the pattern.
   - **Enterprise-project and tag design are inferred the same way.** Derive
     the EP layout (`02_Finance.CostCenters` rows + `AppPermissionSets`
     scoping) from the workload/environment/cost-allocation answers, and the
     tag plan — key naming, `Global.MasterDefaultTags`, `TagPolicies` /
     `MandatoryTags` entries — from the tagging answer, keeping tag keys and
     EP names consistent with the resource-naming convention. Each inferred
     design lands as ONE reviewable DEFAULTED item (the layout / the key
     set), not one per resource.
   - **DEFAULTED items** (silent with a documented `default_if_silent`):
     apply the stated default to the draft. They never block the build, but
     the customer reviews them via the decisions .md.
   - **OPEN items — never invent facts.** A value the spec needs that no
     answer provides (a CIDR, an email pattern, a retention number) stays
     unset in the draft. It is resolved only by editing its entry in
     `lz.spec.<customer>.decisions.json`:
     `"resolution": {"status": "ANSWERED", "approved_by": "<person>", "reason": "<the obtained answer>"}`
     (or `"ACCEPTED_DEFAULT"` when the customer signs off on a proposed
     default). Record who decided — the gate exists so this is auditable.
     **Only `resolution` fields are editable**: the decision set itself is
     hash-bound into the spec's `provenance` block (its origin record), so deleting or altering an item
     (or the whole list) blocks `build` exactly like leaving it unresolved.
   - **Gaps you discover are OPEN too — register them.** `assess` can only
     classify what the questionnaire asked; interpretation surfaces required
     values no question covers — an on-prem resolver IP, a peer gateway's
     public IP, a WAF origin address, a certificate ID. A fully answered
     questionnaire (0 OPEN) is therefore NOT proof the spec is complete.
     Leave the field null (`lzctl set --field <path> --null`) — never a
     placeholder or a plausible-looking value; null is how this spec spells
     "not known yet" — and register each one:

         lzctl gap add --spec <spec> --field "08_DNS.ResolverRules[fwd-onprem].TargetIPs" \
                       --question "On-prem AD DNS server IPs (D9) - network team"

     That appends a real OPEN decision (`G1`, `G2`, …) and re-stamps the
     spec's provenance, so the gap blocks `build` until somebody resolves it
     and records who decided. It is the ONLY sanctioned way to grow a
     decision set — hand-editing still fails the hash, and `gap add` refuses
     to re-stamp a set that was already altered. This covers ANSWERED
     questions too: an answer that settles intent ("centralized egress via
     the hub") without the concrete rows its target table needs would
     otherwise validate as a dropped answer (LZR-035) — register the gap on
     the concrete target and the intent stays honored while the missing
     values stay owed.
   - **Sweep cross-references.** Accounts/VPCs/groups you add invalidate any
     row referencing names that don't exist — `lzctl validate` enforces
     referential integrity and lists what you missed.
   - **Sweep for no-ops.** A field the schema marks *Deferred* or *RESERVED*
     (e.g. `07_Security.Settings.enable_hss` / `enable_dbss`) accepts your
     value and deploys nothing. Setting one is not delivering the control —
     record it as a follow-up in the decisions .md instead of reporting it as
     configured.

4. **Secrets:** never write real credentials/PSKs into the spec. VPN PSK
   fields get a reference (`secret://...`) or a `REPLACE_WITH_...` placeholder
   — platform rule LZR-027 is an **error** on any literal-looking PSK. If the customer
   pasted a secret into an answer, leave it out of the spec, flag it in the
   decisions file, and never re-emit the pasted value anywhere. Know that the
   intake dump still holds it: `lzctl intake` copies answers VERBATIM, so a
   pasted secret lives on in `<jobtmp>/dump.json`. Treat the dump as
   sensitive working material — keep it under jobtmp, never in a deliverable
   (exports refuse to package `*dump.json`), and delete it once the spec is
   accepted.

5. **Validate** (must pass with 0 errors; warnings go into the decisions file):
   `lzctl validate <workspace>/specs/lz.spec.<customer>.json`
   0 errors is reachable WITH gaps outstanding: a null field whose OPEN
   decision names it (LZR-034), and an answered-but-valueless target covered
   by a registered gap (LZR-035), are declared unknowns, not errors — the
   OPEN items still block `build`. An error that survives is real work left.
   **Deliberate exception: structural-integrity errors are gap-proof.**
   Account-email completeness, minimum row counts, uniqueness, and
   referential integrity always need a real value or a removed row — a gap
   never clears them, by design. A spec whose only surviving errors are
   structural (e.g. no mailbox pattern was ever agreed) is an honest
   stopping point: report it as blocked, don't fight the validator.

6. **Hand the draft to a human in the app — the review and gap-entry gate.**
   The customer reviews the draft and fills its gaps in the UI, never by
   hand-editing JSON, and never by you guessing on their behalf:

       lz-app --workspace <workspace>        # serves http://127.0.0.1:8600

   Start it in the BACKGROUND, or just give the operator the command — it
   serves until stopped, so never block the session on it. Then tell them
   exactly what to do:
   - pick `lz.spec.<customer>.json` in the top-right dropdown → **Load**;
   - open **Decisions & gaps** (top of the left rail): every OPEN decision
     gets a resolution (ANSWERED / ACCEPTED_DEFAULT + who decided + why), and
     every gap links to the sheet holding its null field;
   - work the rest sheet by sheet — the rail is in build order, reference
     columns are dropdowns fed by the tables they point at, and each table
     carries its MANDATORY / OPTIONAL-billable / AUTO / RESERVED badge;
   - press **Validate** — errors link to the offending sheet — then **Save**.

   Then STOP and wait for them. When they hand it back, re-read the saved
   spec before doing anything else: it is now the source of truth and your
   in-memory copy is stale. What they changed is reviewable as a diff of the
   spec file; fold anything surprising into the decisions .md rather than
   silently accepting it.

7. **Report:** answered/defaulted/open counts, what was interpreted, the gaps
   you raised, which OPEN items still block the build, the validation result,
   and the app command with the review agenda for the human.

The draft does not build until (a) validation is clean, (b) every OPEN item in
`lz.spec.<customer>.decisions.json` carries a resolution (`lzctl build` exits 3
otherwise), and (c) no `REPLACE_WITH_` sentinel survives anywhere in the spec
(rule LZR-032, an error at validate — the PSK field is the one exemption, and
preflight blocks that placeholder before it can become a live tunnel key). All
three are machine-enforced; none of them is yours to vouch for.
