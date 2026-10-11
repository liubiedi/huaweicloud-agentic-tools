# ops-monitoring

Operations monitoring, deployed once per ops account: a central SMN
notification topic with subscriptions, plus CES alarms (custom rules and
Huawei's ready-made one-click bundles). Used by the 06-observability
environment.

## One-click alarm bundles

var.one_click_alarms turns on Huawei's curated alarm set for a service, one
entry per service namespace. The module looks up the bundle for that
namespace and applies it to every resource of that service; alarms notify
the central SMN topic. Off by default.

## Not included yet

Application monitoring (AOM) and function alarms (FGS) are stubbed out in
aom-fgs.tf and switched off. Enable and extend there when needed.

## Subscription identity

Each subscription is keyed `<protocol>-<endpoint>`, so a subscriber row is
addressed by what it is, not by its position: removing or reordering rows
touches only the rows that changed. A duplicate protocol+endpoint row would
collide on the key - the pipeline refuses it before build (LZR-044). An
estate created before this change (keys `<protocol>-<index>`) moves each
subscription once with `terraform state mv`; the pipeline's
`tools/migrate_smn_subscriber_keys.py` prints the list from the pulled state
and the env tfvars. A recreated email subscription is unconfirmed until the
recipient clicks the new link, which is why the move matters.
