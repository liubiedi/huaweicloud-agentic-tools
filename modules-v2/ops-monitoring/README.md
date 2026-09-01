# 07-ops-monitoring

Operations monitoring, deployed once per ops account: a central SMN
notification topic with subscriptions, plus CES alarms (custom rules and
Huawei's ready-made one-click bundles).

## One-click alarm bundles

var.one_click_alarms turns on Huawei's curated alarm set for a service, one
entry per service namespace. The module looks up the bundle for that
namespace and applies it to every resource of that service; alarms notify
the central SMN topic. Off by default.

## Not included yet

Application monitoring (AOM) and function alarms (FGS) are stubbed out in
aom-fgs.tf and switched off. Enable and extend there when needed.
