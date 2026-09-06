"""Declarative spec of the LDZ Excel workbook.

The workbook generator (gen_template.py) and parser (build_envs.py) both read
SHEETS to know what to write / what to expect. Adding a field here flows
through to the template and the env builder once the corresponding passthrough
exists in build_envs.py.

Three table kinds:
  scalar       - one row per field, columns: Field/Type/Default/Sample/Description/Value
  list-single  - rows of a single Value column (list of primitives)
  object-table - rows of multiple columns (list of objects); optional tables
                 have an "Enabled" boolean as the first column.

Mandatory items (always created by the module) have no Enabled column.
"""

from dataclasses import dataclass, field
from typing import Any

from lz_spec.ep_actions import EP_ACTIONS, ESSENTIAL_ACTIONS


# ────────────────────────────────────────────────────────────────────────────
# Dataclasses
# ────────────────────────────────────────────────────────────────────────────

@dataclass
class KV:
    """A scalar field row."""
    name: str
    type: str           # string | bool | int | csv-list | json
    default: Any
    sample: Any
    description: str


@dataclass
class Table:
    """A table on a sheet.

    kind = "scalar"       -> rows is list[KV]
    kind = "list-single"  -> rows is empty; sample_rows holds example values;
                             column header is fixed to "Value"
    kind = "object-table" -> columns is list[(name, type, description)];
                             sample_rows is list[dict]; mandatory flag suppresses
                             the auto-prepended Enabled column.
    """
    name: str
    kind: str
    description: str = ""
    rows: list = field(default_factory=list)        # for scalar
    columns: list = field(default_factory=list)     # for object-table: (name, type, desc)
    sample_rows: list = field(default_factory=list) # for list-single (list[str]) or object-table (list[dict])
    mandatory: bool = False                          # object-table: suppresses Enabled column


@dataclass
class Sheet:
    name: str
    description: str
    tables: list


# ────────────────────────────────────────────────────────────────────────────
# Sheet definitions
# ────────────────────────────────────────────────────────────────────────────

INDEX = Sheet(
    name="Index",
    description="Workbook map for reference only. No input is required on this sheet.",
    tables=[
        Table(
            name="SheetIndex",
            kind="object-table",
            description="Sheets follow the deployment sequence. Complete and apply them from top to bottom.",
            mandatory=True,
            columns=[
                ("Apply",     "string", "Apply order"),
                ("Sheet",     "string", "Tab to fill"),
                ("FeedsEnv",  "string", "Env directory that consumes this sheet"),
                ("Module",    "string", "Underlying Terraform module"),
                ("Notes",     "string", "Hints"),
            ],
            sample_rows=[
                {"Apply": "—", "Sheet": "Global",          "FeedsEnv": "all (+ 00-bootstrap)", "Module": "—",  "Notes": "Region, Terraform state bucket, and default tags"},
                {"Apply": "1", "Sheet": "01_Foundation",   "FeedsEnv": "01-foundation",        "Module": "01", "Notes": "Organization, OUs, accounts, and Identity Center bootstrap"},
                {"Apply": "2", "Sheet": "02_Finance",      "FeedsEnv": "02-finance",           "Module": "08", "Notes": "Cost-center enterprise projects"},
                {"Apply": "3", "Sheet": "03_Identity",     "FeedsEnv": "03-identity",          "Module": "02", "Notes": "Identity Center users and groups, permission sets, and IAM baseline"},
                {"Apply": "4", "Sheet": "04_Perimeter",    "FeedsEnv": "04-perimeter",         "Module": "04", "Notes": "Service control policies and predefined tags for each account"},
                {"Apply": "5", "Sheet": "05_Network",      "FeedsEnv": "05-network",           "Module": "03", "Notes": "Hub and spoke networking, including ER, CFW, NAT, ELB, and EIPs. Deploy this before observability because it creates firewall and flow-log streams used by log aggregation."},
                {"Apply": "6", "Sheet": "06_Observability","FeedsEnv": "06-observability",     "Module": "06+07+12", "Notes": "CTS, OBS, KMS, LTS, SMN, CES, and organization-wide log aggregation. For a greenfield deployment, re-apply after DNS so the DNS query-log source exists."},
                {"Apply": "7", "Sheet": "07_Security",     "FeedsEnv": "07-security",          "Module": "05+13", "Notes": "SecMaster, Basic Anti-DDoS for EIPs, and dedicated WAF in the hub DMZ. Deploy after network and observability."},
                {"Apply": "8", "Sheet": "08_DNS",          "FeedsEnv": "08-network-dns",       "Module": "DNS", "Notes": "Public and private DNS zones, records, hybrid resolver endpoints, forwarding rules, and access logs"},
                {"Apply": "9", "Sheet": "09_CFW",          "FeedsEnv": "09-network-cfw",       "Module": "CFW", "Notes": "Cloud Firewall address, domain, and service groups, plus internet and VPC ACL rules, allowlists, and blocklists"},
                {"Apply": "10", "Sheet": "10_VPN",         "FeedsEnv": "10-network-vpn",       "Module": "VPN", "Notes": "Enterprise site-to-cloud VPN gateways, customer gateways, and IPsec connections. Apply after the network environment."},
                {"Apply": "11", "Sheet": "11_SGACL",       "FeedsEnv": "11-network-sgacl",     "Module": "15", "Notes": "Workload security groups and rules for each account. Network ACL tables are reserved for future use."},
            ],
        ),
    ],
)


GLOBAL = Sheet(
    name="Global",
    description="Workspace-wide inputs. Do not store AK/SK credentials in this workbook. Provide them through $env:HW_ACCESS_KEY and $env:HW_SECRET_KEY.",
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            description="Required for every environment.",
            rows=[
                KV("home_region",         "string", "ap-southeast-3", "ap-southeast-3",   "Primary Huawei Cloud deployment region ID."),
                KV("state_bucket_name",   "string", "",               "example-lz-tfstate",   "Globally unique OBS bucket name for Terraform state. Created by 00-bootstrap."),
            ],
        ),
        Table(
            name="MasterDefaultTags",
            kind="object-table",
            mandatory=True,
            description=(
                "Default tags applied to supported resources in the management account and all"
                " member accounts through cross-account provider aliases. Each row is one "
                "key/value pair. Add or remove rows as needed, for example owner, costcenter, "
                "bu, env, or compliance. Organization account resources created in "
                "01-foundation are intentionally untagged because that environment does not "
                "use provider default tags."
            ),
            columns=[
                ("Key",   "string", "Tag key."),
                ("Value", "string", "Tag value."),
            ],
            sample_rows=[
                {"Key": "project", "Value": "landing-zone"},
                {"Key": "owner",   "Value": "cloud-platform-team"},
                {"Key": "env",     "Value": "prd"},
                {"Key": "bu",      "Value": "bu1"},
            ],
        ),
    ],
)


M1_ORG = Sheet(
    name="01_Foundation",
    description="Environment 01-foundation (module 1): organization, OUs, accounts, and Identity Center bootstrap.",
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            description="Organization-level settings. The core logging and security accounts are required and are defined in the CoreAccounts table.",
            rows=[
                KV("identity_center_alias",       "string", "",                                "lz-portal",                       "Optional Identity Center alias. Leave blank to use no alias."),
                KV("cross_account_agency_name",   "string", "OrganizationAccountAccessAgency", "OrganizationAccountAccessAgency", "Trust agency name created automatically in each provisioned account."),
                KV("create_enterprise_project",   "bool",   False,                             True,                               "Create the bootstrap enterprise project. Module 8 creates the additional cost-center enterprise projects."),
                KV("enterprise_project_name",     "string", "landing-zone",                    "landing-zone",                    "Name of the bootstrap enterprise project."),
                KV("enforce_tag_keys_scp",        "bool",   False,                             True,                               "Add a ninth guardrail to the consolidated SCP in 04-perimeter. It blocks create actions when request tag keys are outside the TagPolicies TagKey set. Tag policies alone report non-compliance; this control enforces it."),
            ],
        ),
        Table(
            name="EnabledPolicyTypes",
            kind="object-table",
            description="Organization root policy types. Only the two rows below are valid. Toggle Enabled and do not add additional rows.",
            mandatory=True,  # don't auto-add an Enabled column; we put it explicitly
            columns=[
                ("Name",        "string", "Policy type name (do not edit)"),
                ("Enabled",     "bool",   "TRUE to enable at org root"),
                ("Description", "string", "Effect (do not edit)"),
            ],
            sample_rows=[
                {"Name": "service_control_policy", "Enabled": True, "Description": "Required for all SCPs in M4 to attach"},
                {"Name": "tag_policy",             "Enabled": True, "Description": "Required for M1 default tag policy + any custom TagPolicies"},
            ],
        ),
        Table(
            name="OrganizationalUnits",
            kind="object-table",
            description=(
                "Each row creates an organizational unit. Delete rows you do not need. "
                "Parent='root' or blank places the OU under the organization root. "
                "Parent='<OUName>' nests it under another OU in this table. Cycles fail during"
                " planning. Do not add a row for the organization root."
            ),
            mandatory=True,  # no Enabled column — presence in the table = enabled
            columns=[
                ("Name",        "string", "OU name (also used as the Terraform map key)"),
                ("Parent",      "string", "'root' / blank = under org root; or another OU's Name"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[
                {"Name": "Workloads", "Parent": "root",      "Description": "Application accounts"},
                {"Name": "Sandbox",   "Parent": "root",      "Description": "Experimental accounts (delete row to skip)"},
                {"Name": "Prod",      "Parent": "Workloads", "Description": "Production tier nested under Workloads"},
                {"Name": "NonProd",   "Parent": "Workloads", "Description": "Non-prod tier nested under Workloads"},
            ],
        ),
        Table(
            name="CoreAccounts",
            kind="object-table",
            description="Required core accounts for logging and security. At minimum, include lz-infra and lz-security.",
            mandatory=True,
            columns=[
                ("Name",        "string", "Account name (used as map key)"),
                ("Email",       "string", "UNIQUE email per Huawei requirement"),
                ("OU",          "string", "OU name from OrganizationalUnits; '' = root"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[
                {"Name": "lz-infra",    "Email": "lz-log-archive@example.com", "OU": "", "Description": "Log archive + ops + network hub"},
                {"Name": "lz-security", "Email": "lz-security@example.com",    "OU": "", "Description": "Security operations"},
            ],
        ),
        Table(
            name="WorkloadAccounts",
            kind="object-table",
            description="Workload accounts. Each row creates an account with a cross-account access agency. Delete rows you do not need.",
            mandatory=True,  # no Enabled column — presence in the table = create
            columns=[
                ("Name",        "string", "Account name"),
                ("Email",       "string", "UNIQUE email"),
                ("OU",          "string", "OU placement (must match an OU Name or be blank for root)"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[
                {"Name": "lz-app-prod",    "Email": "lz-app-prod@example.com",    "OU": "Workloads", "Description": "Production application account"},
                {"Name": "lz-app-nonprod", "Email": "lz-app-nonprod@example.com", "OU": "Workloads", "Description": "Non-production application account"},
            ],
        ),
        Table(
            name="TrustedServices",
            kind="object-table",
            description=(
                "Huawei Organizations trusted services. Toggle Enabled for each service. "
                "DelegatedAdmin is an account name from CoreAccounts or WorkloadAccounts. "
                "Leave it blank to keep administration in the management account. Add rows "
                "only for supported services added after this template was generated, and "
                "verify the service principal first."
            ),
            mandatory=True,  # explicit Enabled column below; no auto-prepend
            columns=[
                ("Name",           "string", "Service principal — exactly as listed by the Huawei discovery data source"),
                ("Enabled",        "bool",   "TRUE to enable org-wide integration"),
                ("DelegatedAdmin", "string", "Optional — account Name to be the delegated admin for this service; blank = none"),
                ("Description",    "string", "What enabling this service does"),
            ],
            sample_rows=[
                {"Name": "service.CTS",            "Enabled": True,  "DelegatedAdmin": "",            "Description": "BASELINE — org-wide CTS trail aggregation (required by M6 org tracker)"},
                {"Name": "service.IdentityCenter", "Enabled": True,  "DelegatedAdmin": "",            "Description": "BASELINE — org-wide IAM Identity Center / SSO"},
                {"Name": "service.RAM",            "Enabled": True,  "DelegatedAdmin": "",            "Description": "BASELINE — org-wide Resource Access Manager sharing"},
                {"Name": "service.RMSMultiAccountSetup", "Enabled": False, "DelegatedAdmin": "",        "Description": "Config (RMS) multi-account setup — org-wide compliance rules / conformance packs"},
                {"Name": "service.SecMaster",      "Enabled": False, "DelegatedAdmin": "lz-security", "Description": "Org-wide SecMaster (Pattern B+) — delegate to security account"},
                {"Name": "service.HSS",            "Enabled": False, "DelegatedAdmin": "lz-security", "Description": "Org-wide Host Security Service"},
                {"Name": "service.DSC",            "Enabled": False, "DelegatedAdmin": "lz-security", "Description": "Org-wide Data Security Center"},
                {"Name": "service.CFW",            "Enabled": False, "DelegatedAdmin": "",            "Description": "Org-wide Cloud Firewall (unified EIP protection)"},
                {"Name": "service.AOM",            "Enabled": False, "DelegatedAdmin": "",            "Description": "Org-wide Application Operations Management (Prometheus)"},
                {"Name": "service.CES",            "Enabled": False, "DelegatedAdmin": "",            "Description": "Org-wide Cloud Eye dashboards"},
                {"Name": "service.LTS",            "Enabled": False, "DelegatedAdmin": "",            "Description": "Org-wide log aggregation (referenced by M6)"},
                {"Name": "service.CBR",            "Enabled": False, "DelegatedAdmin": "",            "Description": "Org-wide Cloud Backup and Recovery policies"},
                {"Name": "service.COC",            "Enabled": False, "DelegatedAdmin": "",            "Description": "Org-wide Cloud Operations Center (max 1 delegated admin)"},
                {"Name": "service.AccessAnalyzer", "Enabled": False, "DelegatedAdmin": "",            "Description": "Org-wide IAM Access Analyzer (max 1 delegated admin)"},
                {"Name": "service.RFS",            "Enabled": False, "DelegatedAdmin": "",            "Description": "Org-wide Resource Formation Service (multi-account orchestration)"},
            ],
        ),
        Table(
            name="TagPolicies",
            kind="object-table",
            description=(
                "Custom tag policies in addition to the default policy. Each row defines one "
                "required tag key. TagValue is a comma-separated list of allowed values; leave"
                " it blank to allow any value while enforcing key presence and casing. Scope "
                "is a comma-separated list of '<service>:<resourceType>'; leave it blank to "
                "apply to all taggable resource types. Tag policies report non-compliance. Use"
                " the module 4 SCP guardrail when you need hard enforcement."
            ),
            mandatory=True,  # every row gets shipped
            columns=[
                ("Name",     "string",   "Policy name (lowercase-hyphenated; becomes the Huawei policy resource name)"),
                ("TagKey",   "string",   "Tag key (lowercase — keys are normalized to lowercase to match the applied tags)"),
                ("TagValue", "csv-list", "Comma-separated allowed values; blank = any value allowed"),
                ("Scope",    "csv-list", "Comma-separated '<service>:<resourceType>' list; blank = all services"),
            ],
            sample_rows=[
                {"Name": "enforce-env-values",        "TagKey": "env",   "TagValue": "production,staging,development,sandbox", "Scope": ""},
                {"Name": "enforce-costcenter-casing", "TagKey": "costcenter", "TagValue": "",                                 "Scope": ""},
                {"Name": "enforce-bu-values",         "TagKey": "bu",    "TagValue": "finance,engineering,sales",              "Scope": ""},
                {"Name": "enforce-owner-on-compute",  "TagKey": "owner", "TagValue": "",                                       "Scope": "ecs:instance,cce:cluster,rds:db"},
            ],
        ),
    ],
)


M2_IDENTITY = Sheet(
    name="03_Identity",
    description="Environment 03-identity (module 2): Identity Center configuration and the per-account IAM baseline.",
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            rows=[
                KV("enable_identity_center_content", "bool", True,  True,  "Create Identity Center users, groups, and permission sets in the management account."),
                KV("enable_iam_baseline",            "bool", True,  True,  "Apply per-account IAM hardening, including password, login, operation-protection policies, and agencies."),
                KV("session_duration",               "string","PT8H","PT8H","ISO 8601 duration for permission-set sessions."),
                KV("ic_min_password_length",         "int",  12,    14,    "Minimum password length for Identity Center local users."),
                KV("ic_password_max_age_days",       "int",  90,    90,    "Password expiry period, in days, for Identity Center local users."),
                KV("ic_mfa_required",                "bool", True,  True,  "Require MFA for Identity Center users."),
                KV("iam_session_timeout_minutes",    "int",  60,    60,    "Per-account IAM console session timeout."),
                KV("iam_lockout_duration_minutes",   "int",  15,    15,    "Per-account IAM lockout duration after failed sign-in attempts."),
            ],
        ),
        Table(
            name="Groups",
            kind="object-table",
            description="IC workforce groups.",
            mandatory=True,
            columns=[
                ("Name",        "string", "Group name"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[
                {"Name": "lz-admins",     "Description": "Full landing zone administrators"},
                {"Name": "lz-developers", "Description": "Workload developers"},
                {"Name": "lz-security",   "Description": "Security operations"},
                {"Name": "lz-billing",    "Description": "Billing readers"},
                {"Name": "lz-readonly",   "Description": "Read-only access"},
            ],
        ),
        Table(
            name="Users",
            kind="object-table",
            description="Identity Center users. GroupNames is a comma-separated list and each value must match a group in the Groups table.",
            mandatory=True,
            columns=[
                ("UserName",    "string",   "Login name"),
                ("DisplayName", "string",   "Display name"),
                ("FamilyName",  "string",   "Family name"),
                ("GivenName",   "string",   "Given name"),
                ("Email",       "string",   "Email"),
                ("GroupNames",  "csv-list", "Comma-separated group names"),
            ],
            sample_rows=[
                {"UserName": "alice", "DisplayName": "Alice Liu", "FamilyName": "Liu", "GivenName": "Alice", "Email": "alice@example.com", "GroupNames": "lz-admins"},
            ],
        ),
        Table(
            name="PermissionSets",
            kind="object-table",
            description="Permission sets. SystemPolicies is a comma-separated list of Huawei Cloud v2012 policy names.",
            mandatory=True,
            columns=[
                ("Name",            "string",   "PS name"),
                ("Description",     "string",   "Purpose"),
                ("SessionDuration", "string",   "ISO-8601; '' = inherit Settings.session_duration"),
                ("SystemPolicies",  "csv-list", "Comma-separated v2012 system policy names"),
            ],
            sample_rows=[
                {"Name": "LzAdministrator",    "Description": "Full admin",     "SessionDuration": "PT8H", "SystemPolicies": "FullAccess"},
                {"Name": "LzDeveloper",        "Description": "Developer",      "SessionDuration": "PT8H", "SystemPolicies": "Tenant Guest,Server Administrator"},
                {"Name": "LzSecurityAuditor",  "Description": "Security audit", "SessionDuration": "PT8H", "SystemPolicies": "Security Administrator"},
                {"Name": "LzBillingViewer",    "Description": "Billing RO",     "SessionDuration": "PT8H", "SystemPolicies": "BSS Administrator"},
                {"Name": "LzReadOnly",         "Description": "Read only",      "SessionDuration": "PT8H", "SystemPolicies": "Tenant Guest"},
            ],
        ),
        Table(
            name="AccountAssignments",
            kind="object-table",
            description="Bindings between groups, permission sets, and accounts. AccountName must match an account defined in module 1.",
            mandatory=True,
            columns=[
                ("AccountName",   "string", "Account name (from M1 CoreAccounts/WorkloadAccounts)"),
                ("GroupName",     "string", "Group name from Groups"),
                ("PermissionSet", "string", "PS name from PermissionSets"),
            ],
            sample_rows=[
                {"AccountName": "lz-app-prod", "GroupName": "lz-admins", "PermissionSet": "LzAdministrator"},
            ],
        ),
        Table(
            name="AppPermissionSets",
            kind="object-table",
            description=(
                "Application-scoped Identity Center permission sets. CustomPolicy contains a "
                "complete v5.0 custom identity policy with enterprise project IDs. See "
                "EP_Scoping for the supported pattern. Account and EnterpriseProjects document"
                " the target member account and enterprise projects. Use one row per "
                "permission set and leave the table empty if application-scoped permission "
                "sets are not required."
            ),
            columns=[
                ("Name",               "string",   "Permission set name (also the resource key), e.g. App-Admin"),
                ("Account",            "string",   "Member account (Name from 01_Foundation) whose enterprise projects scope the policy"),
                ("EnterpriseProjects", "csv-list", "Comma-separated EP names in Account to scope g:EnterpriseProjectId to"),
                ("SessionDuration",    "string",   "ISO-8601 session duration (default PT8H)"),
                ("Description",        "string",   "Permission set description"),
                ("CustomPolicy",       "json",     "Complete v5.0 custom identity policy JSON, attached verbatim (EP IDs baked in; see EP_Scoping sheet). Blank = permission set created without a custom policy."),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "App-Admin", "Account": "lz-app", "EnterpriseProjects": "app-prd-ep,app-uat-ep", "SessionDuration": "PT8H", "Description": "Full management scoped to the app enterprise projects"},
            ],
        ),
        Table(
            name="RegisteredRegions",
            kind="list-single",
            description="Regions where Identity Center can issue session credentials. Leave blank to use the home region only.",
            sample_rows=["ap-southeast-3"],
        ),
        Table(
            name="ServiceAgencies",
            kind="object-table",
            description="Per-account service agencies that allow Huawei Cloud services to act in the account. Policies is a comma-separated list.",
            mandatory=True,
            columns=[
                ("Name",             "string",   "Agency name"),
                ("Description",      "string",   "Purpose"),
                ("DelegatedService", "string",   "service.<NAME> (e.g. service.CTS)"),
                ("Policies",         "csv-list", "Comma-separated system policy names"),
                ("AllResources",     "bool",     "TRUE for org-wide; FALSE requires ProjectName"),
                ("ProjectName",      "string",   "Required when AllResources=FALSE"),
            ],
            sample_rows=[
                {"Name": "cts-to-lz-audit-bucket",   "Description": "Allow CTS to write to lz-audit",    "DelegatedService": "service.CTS", "Policies": "OBS OperateAccess", "AllResources": True, "ProjectName": ""},
                {"Name": "lts-to-lz-archive-bucket", "Description": "Allow LTS to write to lz-archive",  "DelegatedService": "service.LTS", "Policies": "OBS OperateAccess", "AllResources": True, "ProjectName": ""},
            ],
        ),
    ],
)


M3_NETWORK = Sheet(
    name="05_Network",
    description="Environment 05-network (module 3): hub and spoke networking, including ER, VPCs, CFW, NAT, ELB, EIPs, and RAM sharing. Hub and spoke resources deploy together in one apply, and spoke attachments connect to the ER created in the same run.",
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            description="Hub-wide settings and the landing zone enterprise project. ER and CFW have dedicated settings tables; NAT, ELB, and EIP support multiple instances.",
            rows=[
                KV("enable_hub",                       "bool",   True,        True,        "Create the hub network, including ER, VPCs, CFW, NAT, and ELB."),
                KV("enable_spoke",                     "bool",   True,        True,        "Create spoke VPCs in workload accounts."),
                KV("hub_account",                      "string", "lz-infra",  "lz-infra",  "Account name from module 1 where hub network resources are deployed. The environment assumes this account's OrganizationAccountAccessAgency."),
                KV("spoke_private_supernet",           "string", None,        "10.0.0.0/8","Supernet covering all hub and spoke private CIDRs. The SNAT VPC receives a route for this supernet through the ER to provide a return path to spoke networks. The supernet must not overlap the SNAT VPC subnets."),
                KV("enterprise_project_name",          "string", None,        "landing-zone","Landing zone enterprise project for the hub account. Supported hub resources are assigned to it. The value must match a CostCenters.Name in Sheet 02. Leave blank to use the default enterprise project."),
                KV("snat_vpc_attachment",              "string", "vpc-dmz-att","vpc-dmz-att","Hub ER VPC attachment that hosts the egress NAT gateway. The er-outbound route table sends 0.0.0.0/0 to this attachment after firewall inspection. Leave blank when no outbound default route is required."),
                KV("subnet_dns_servers",               "csv-list", None,      "10.0.32.2,10.0.32.3", "DNS server IPs, maximum two, applied to every hub and spoke subnet through DHCP. Point these to the 08_DNS inbound resolver endpoint IPs when centralized hybrid DNS is used. Leave blank to use Huawei Cloud default DNS."),
                KV("enable_vpc_flow_logs",             "bool",   False,       True,        "Create a VPC flow log for every hub and spoke VPC, with a dedicated LTS group and stream named '<vpc>-flowlog'. Add corresponding LogConverge rows in 06_Observability to archive these logs. Apply 05-network before re-applying 06-observability so the source streams exist."),
                KV("flow_log_retention_days",          "int",    90,          90,          "Hot LTS retention, in days, for each VPC flow-log group and stream."),
            ],
        ),
        Table(
            name="EnterpriseRouter",
            kind="scalar",
            description="The single hub Enterprise Router. Availability zones are defined in the ERAvailabilityZones table.",
            rows=[
                KV("er_name",                          "string", "lz-hub-er",         "lz-hub-er",         "Name of the hub Enterprise Router."),
                KV("er_asn",                           "int",    64512,        64512,       "Autonomous system number for the Enterprise Router."),
                KV("er_flow_log_name",                 "string", "lz-hub-er-flow-log","lz-hub-er-flow-log","Name of the Enterprise Router flow log."),
                KV("er_auto_accept_shared_attachments","bool",   True,        True,        "Automatically accept ER attachments from principals that receive the shared ER through RAM."),
                KV("er_share_name",                    "string", "lz-hub-er-share",  "lz-hub-er-share",  "Name of the RAM resource share for ER attachments."),
            ],
        ),
        Table(
            name="CloudFirewall",
            kind="scalar",
            description="The single hub Cloud Firewall.",
            rows=[
                KV("cfw_name",                         "string", "lz-hub-cfw",       "lz-hub-cfw",       "Name of the hub Cloud Firewall."),
                KV("cfw_flavor",                       "string", "standard",  "standard",  "standard | professional."),
                KV("cfw_ips_protection_mode",          "int",    "",          2,           "IPS protection mode for the hub firewall: 0 observe, 1 strict, 2 medium, or 3 loose. Leave blank to manage this setting in the console."),
                KV("cfw_ips_patch_enabled",            "bool",   "",          True,        "IPS virtual patching for the hub firewall. Leave blank to manage this setting in the console."),
                KV("inspection_cidr_reservation",      "string", "10.0.99.0/24","10.0.99.0/24","CIDR used by Cloud Firewall for its ER-mode inspection attachment. It must not overlap any VPC CIDR."),
                KV("cfw_charging_mode",                "string", "pay-per-use", "pay-per-use", "Cloud Firewall billing mode: pay-per-use or subscription."),
                KV("cfw_period_unit",                  "string", "month",     "month",     "Subscription period unit: month or year. Used only when cfw_charging_mode is subscription."),
                KV("cfw_period",                       "int",    1,           1,           "Subscription period count, for example 1. Used only when cfw_charging_mode is subscription."),
                KV("cfw_auto_renew",                   "bool",   False,       False,       "Automatically renew the Cloud Firewall subscription at the end of the billing period."),
                KV("cfw_lts_log_enable",               "bool",   True,        True,        "Send Cloud Firewall logs to LTS. The hub module creates the log group and streams below."),
                KV("cfw_lts_log_group_name",           "string", "lz-hub-cfw",       "lz-hub-cfw",       "Name of the LTS log group created for Cloud Firewall logs."),
                KV("cfw_lts_traffic_stream_name",      "string", "cfw-traffic",      "cfw-traffic",      "LTS stream for Cloud Firewall traffic and flow logs. This stream is also used for the ER attachment flow log."),
                KV("cfw_lts_access_stream_name",       "string", "cfw-access",       "cfw-access",       "LTS stream for Cloud Firewall access logs."),
                KV("cfw_lts_attack_stream_name",       "string", "cfw-attack",       "cfw-attack",       "LTS stream for Cloud Firewall attack logs."),
            ],
        ),
        Table(
            name="ERAvailabilityZones",
            kind="list-single",
            description="Availability zones used by the Enterprise Router, one per row. Use the full Huawei Cloud AZ identifiers returned by the API, such as ap-southeast-3a and ap-southeast-3e.",
            sample_rows=["ap-southeast-3a", "ap-southeast-3e"],
        ),
        Table(
            name="HubVPCs",
            kind="object-table",
            mandatory=True,
            description="Hub VPCs. Subnets are defined in HubSubnets and linked by VPCName. vpc-dmz is required when enable_hub is TRUE.",
            columns=[
                ("VPCName", "string", "VPC name (vpc-dmz, vpc-access, vpc-shared)"),
                ("CIDR",    "string", "VPC CIDR"),
            ],
            sample_rows=[
                {"VPCName": "vpc-dmz",    "CIDR": "10.0.0.0/20"},
                {"VPCName": "vpc-access", "CIDR": "10.0.16.0/23"},
                {"VPCName": "vpc-shared", "CIDR": "10.0.32.0/22"},
            ],
        ),
        Table(
            name="HubSubnets",
            kind="object-table",
            mandatory=True,
            description="Subnets linked to HubVPCs by VPCName. Availability zones are not pinned because Huawei Cloud places subnets automatically.",
            columns=[
                ("VPCName", "string", "FK -> HubVPCs.VPCName"),
                ("Name",    "string", "Subnet name"),
                ("CIDR",    "string", "Subnet CIDR"),
            ],
            sample_rows=[
                {"VPCName": "vpc-dmz",    "Name": "dmz-nat",       "CIDR": "10.0.0.0/24"},
                {"VPCName": "vpc-dmz",    "Name": "dmz-elb",       "CIDR": "10.0.2.0/24"},
                {"VPCName": "vpc-dmz",    "Name": "dmz-er-attach", "CIDR": "10.0.15.0/28"},
                {"VPCName": "vpc-access", "Name": "access-dc",     "CIDR": "10.0.16.0/26"},
                {"VPCName": "vpc-access", "Name": "access-er-attach","CIDR": "10.0.17.0/28"},
                {"VPCName": "vpc-shared", "Name": "shared-dns",    "CIDR": "10.0.32.0/24"},
                {"VPCName": "vpc-shared", "Name": "shared-er-attach","CIDR": "10.0.35.0/28"},
            ],
        ),
        Table(
            name="HubERAttachments",
            kind="object-table",
            mandatory=True,
            description=(
                "HUB ER VPC attachments — one row per hub-account attachment. Each joins a hub VPC to the ER via a "
                "subnet, and is AUTO-associated to the inbound RT + AUTO-propagated to the outbound RT (Settings."
                "inbound/outbound_route_table); the VPC also auto-gets its default route to the ER (or NAT, for the "
                "SNAT VPC). AutoAddRoute=TRUE lets the ER auto-create the VPC-side route back to the ER. The egress "
                "attachment is named in Settings.snat_vpc_attachment. (Spoke attachments live in SpokeERAttachments.)"
            ),
            columns=[
                ("Name",         "string", "Attachment name (auto-wired; Settings.snat_vpc_attachment target)"),
                ("VPC",          "string", "FK -> HubVPCs.VPCName"),
                ("Subnet",       "string", "Subnet name (from HubSubnets) carrying the attachment. Blank = VPC's first subnet."),
                ("AutoAddRoute", "bool",   "TRUE = ER auto-creates the VPC-side return route (auto_create_vpc_routes)"),
                ("Description",  "string", "Purpose"),
            ],
            sample_rows=[
                {"Name": "vpc-dmz-att",    "VPC": "vpc-dmz",    "Subnet": "dmz-er-attach",    "AutoAddRoute": False, "Description": "DMZ ER attachment"},
                {"Name": "vpc-access-att", "VPC": "vpc-access", "Subnet": "access-er-attach", "AutoAddRoute": False, "Description": "Access ER attachment"},
                {"Name": "vpc-shared-att", "VPC": "vpc-shared", "Subnet": "shared-er-attach", "AutoAddRoute": False, "Description": "Shared ER attachment"},
            ],
        ),
        # ER route tables are FIXED (not spec input): er-inbound (all VPC
        # attachments associate; 0/0 -> CFW), er-outbound (all VPC attachments
        # propagate; CFW associates; 0/0 -> snat_vpc_attachment), er-hybrid
        # (VPN/DC attachments; DefaultToCFW so on-prem traffic is inspected).
        # Hard-coded in build_05_network; 10_VPN references them by name.
        Table(
            name="EIPs",
            kind="object-table",
            mandatory=True,
            description=(
                "Elastic IPs, one per row. Each EIP has dedicated bandwidth. NAT and ELB "
                "resources reference EIPs by Name. BilledBy controls bandwidth metering."
            ),
            columns=[
                ("Name",          "string", "EIP name (referenced by SNATRules/DNATRules/ELBs)"),
                ("Type",          "string", "Public IP type: 5_bgp (dynamic BGP) | 5_sbgp (static BGP)"),
                ("BilledBy",      "string", "Bandwidth metering: bandwidth | traffic"),
                ("BandwidthSize", "int",    "Bandwidth size (Mbit/s)"),
                ("Description",   "string", "Purpose"),
            ],
            sample_rows=[
                {"Name": "nat-eip-1",     "Type": "5_bgp", "BilledBy": "bandwidth", "BandwidthSize": 100, "Description": "Hub NAT egress EIP"},
                {"Name": "ingress-eip-1", "Type": "5_bgp", "BilledBy": "bandwidth", "BandwidthSize": 100, "Description": "Public ingress ELB EIP"},
            ],
        ),
        Table(
            name="NATGateways",
            kind="object-table",
            mandatory=True,
            description=(
                "Public NAT gateways in the hub, one per row. SNATRules and DNATRules "
                "reference the gateway by Name. A typical hub uses one NAT gateway in the DMZ "
                "VPC."
            ),
            columns=[
                ("Specification", "string", "Small | Medium | Large | Extra-large"),
                ("Name",          "string", "NAT gateway name (FK target for SNAT/DNAT rows)"),
                ("VPC",           "string", "FK -> HubVPCs.VPCName the NAT deploys into"),
                ("Subnet",        "string", "FK -> HubSubnets.Name the NAT deploys into"),
            ],
            sample_rows=[
                {"Specification": "Small", "Name": "lz-hub-nat", "VPC": "vpc-dmz", "Subnet": "dmz-nat"},
            ],
        ),
        Table(
            name="ELBs",
            kind="object-table",
            mandatory=True,
            description=(
                "Dedicated IPv4 load balancers in the hub, billed pay-per-use. AZ is a "
                "comma-separated list. EIP references an entry in EIPs for public access; "
                "leave it blank for an internal load balancer. IPAsBackend enables cross-VPC "
                "IP backends."
            ),
            columns=[
                ("Name",            "string", "ELB name"),
                ("AZ",              "string", "AZ ids, comma-separated (e.g. az1,az5)"),
                ("VPC",             "string", "FK -> HubVPCs.VPCName"),
                ("FrontendSubnet",  "string", "FK -> HubSubnets.Name for the ELB's IPv4 VIP"),
                ("BackendSubnet",   "string", "FK -> HubSubnets.Name for backend members (blank = none)"),
                ("IPAsBackend",     "bool",   "TRUE = allow IP-as-backend (cross-VPC backends)"),
                ("EIP",             "string", "FK -> EIPs.Name for public access (blank = internal-only)"),
            ],
            sample_rows=[
                {"Name": "lz-ingress-elb", "AZ": "az1,az5", "VPC": "vpc-dmz", "FrontendSubnet": "dmz-elb", "BackendSubnet": "dmz-elb", "IPAsBackend": False, "EIP": "ingress-eip-1"},
            ],
        ),
        Table(
            name="SNATRules",
            kind="object-table",
            mandatory=True,
            description="SNAT rules. CIDR is the source subnet translated to the named EIP through the named NAT gateway. Leave NATName blank when only one NAT gateway exists.",
            columns=[
                ("NATName",     "string", "FK -> NATGateways.Name (blank = sole NAT)"),
                ("CIDR",        "string", "Source CIDR"),
                ("EIP",         "string", "FK -> EIPs.Name"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[
                {"NATName": "lz-hub-nat", "CIDR": "10.1.0.0/16", "EIP": "nat-eip-1", "Description": "lz-app-prod egress"},
            ],
        ),
        Table(
            name="DNATRules",
            kind="object-table",
            mandatory=True,
            description="DNAT rules that map a named EIP to an internal target. Leave NATName blank when only one NAT gateway exists.",
            columns=[
                ("NATName",      "string", "FK -> NATGateways.Name (blank = sole NAT)"),
                ("EIP",          "string", "FK -> EIPs.Name"),
                ("ExternalPort", "int",    "External port"),
                ("InternalIP",   "string", "Internal target IP"),
                ("InternalPort", "int",    "Internal port"),
                ("Protocol",     "string", "tcp | udp"),
                ("Description",  "string", "Purpose"),
            ],
            sample_rows=[
                {"NATName": "lz-hub-nat", "EIP": "nat-eip-1", "ExternalPort": 443, "InternalIP": "10.0.2.10", "InternalPort": 443, "Protocol": "tcp", "Description": "HTTPS ingress"},
            ],
        ),
        Table(
            name="RAMSharePrincipals",
            kind="list-single",
            description=(
                "Principals that receive access to the shared hub ER. Use one account name "
                "from module 1, a raw 32-character account ID, or an OU ID per row. Leave the "
                "table empty to derive principals from the workload OU and workload accounts."
            ),
            sample_rows=[],
        ),
        # ════════════════════════════════════════════════════════════════════
        # Spokes — deployed together with the hub in this one env/apply.
        # Each spoke attaches to the hub ER (same run) and auto-associates to
        # Settings.inbound_route_table + auto-propagates into outbound_route_table,
        # exactly like the hub VPCs.
        # ════════════════════════════════════════════════════════════════════
        Table(
            name="SpokeVPCs",
            kind="object-table",
            mandatory=True,
            description=(
                "Spoke VPCs, typically one per workload account. Subnets are defined in "
                "SpokeSubnets and linked by VPCName, while ER attachments are defined in "
                "SpokeERAttachments. The baseline security group and flow log are derived from"
                " VPCName. The spoke provider applies Global default tags, and the Tags column"
                " can override individual keys. Include the full mandatory tag set when "
                "row-specific values are required."
            ),
            columns=[
                ("AccountName", "string", "Spoke account name (must match M1)"),
                ("VPCName",     "string", "VPC name"),
                ("CIDR",        "string", "VPC CIDR"),
                ("Tags",        "string", "Per-VPC tags, comma-delimited key=value (e.g. CostCenter=app,Owner=appteam). Also applied to the spoke ER attachment."),
            ],
            sample_rows=[
                {"AccountName": "lz-app-prod",    "VPCName": "lz-app-prod-vpc",    "CIDR": "10.1.0.0/16", "Tags": "CostCenter=app-prod,Owner=appteam"},
                {"AccountName": "lz-app-nonprod", "VPCName": "lz-app-nonprod-vpc", "CIDR": "10.2.0.0/16", "Tags": "CostCenter=app-nonprod,Owner=appteam"},
                {"AccountName": "lz-security",    "VPCName": "lz-security-vpc",     "CIDR": "10.3.0.0/16", "Tags": "CostCenter=security,Owner=secteam"},
            ],
        ),
        Table(
            name="SpokeSubnets",
            kind="object-table",
            mandatory=True,
            description="Subnets linked to SpokeVPCs by VPCName. Availability zones are not pinned. The first subnet in each VPC carries the spoke ER attachment. Subnet tags are set explicitly rather than inherited from Global default tags.",
            columns=[
                ("VPCName", "string", "FK -> SpokeVPCs.VPCName"),
                ("Name",    "string", "Subnet name"),
                ("CIDR",    "string", "Subnet CIDR"),
                ("Tags",    "string", "Per-subnet tags, comma-delimited key=value (e.g. CostCenter=app,Tier=db)"),
            ],
            sample_rows=[
                {"VPCName": "lz-app-prod-vpc", "Name": "spoke-er-attach", "CIDR": "10.1.0.0/28", "Tags": "CostCenter=app-prod,Tier=mgmt"},
                {"VPCName": "lz-app-prod-vpc", "Name": "workload",        "CIDR": "10.1.1.0/24", "Tags": "CostCenter=app-prod,Tier=workload"},
                {"VPCName": "lz-app-prod-vpc", "Name": "db",              "CIDR": "10.1.11.0/24", "Tags": "CostCenter=app-prod,Tier=db"},
            ],
        ),
        Table(
            name="SpokeERAttachments",
            kind="object-table",
            mandatory=True,
            description=(
                "SPOKE ER VPC attachments — one row per spoke VPC (created in the spoke's own member account). Mirrors "
                "HubERAttachments. Each is AUTO-associated to the inbound RT + AUTO-propagated to the outbound RT, and "
                "the spoke VPC auto-gets 0.0.0.0/0 -> ER. AutoAddRoute=TRUE lets the ER auto-create the VPC-side route. "
                "Use a distinct Name scheme (e.g. spoke-*) to tell hub vs spoke attachments apart. OMIT the row for a "
                "SpokeVPCs entry to create that spoke UNATTACHED (isolated sandbox: VPC/subnets/SG exist, no ER "
                "attachment/route — unreachable from the hub and other spokes)."
            ),
            columns=[
                ("Name",         "string", "Attachment name (blank = att-<VPC>)"),
                ("VPC",          "string", "FK -> SpokeVPCs.VPCName"),
                ("Subnet",       "string", "Subnet name (from SpokeSubnets) carrying the attachment. Blank = VPC's first subnet."),
                ("AutoAddRoute", "bool",   "TRUE = ER auto-creates the VPC-side return route (auto_create_vpc_routes)"),
                ("Description",  "string", "Purpose"),
            ],
            sample_rows=[
                {"Name": "spoke-lz-app-prod-att", "VPC": "lz-app-prod-vpc", "Subnet": "spoke-er-attach", "AutoAddRoute": False, "Description": "lz-app-prod spoke attachment"},
            ],
        ),
    ],
)

# Present the tables top-to-bottom in resource DEPLOY order (fill + apply down the
# sheet): hub VPCs/subnets -> ER (instance, attachments) -> CFW -> ER routing ->
# EIP/NAT/ELB -> RAM share -> spokes. (VPC route tables are auto-wired.)
_M3_TABLE_ORDER = [
    "Settings",
    "HubVPCs",
    "HubSubnets",
    "EnterpriseRouter",
    "ERAvailabilityZones",
    "HubERAttachments",
    "CloudFirewall",
    "EIPs",
    "NATGateways",
    "SNATRules",
    "DNATRules",
    "ELBs",
    "RAMSharePrincipals",
    "SpokeVPCs",
    "SpokeSubnets",
    "SpokeERAttachments",
]
assert {t.name for t in M3_NETWORK.tables} == set(_M3_TABLE_ORDER), \
    "M3_NETWORK tables and _M3_TABLE_ORDER are out of sync"
M3_NETWORK.tables.sort(key=lambda t: _M3_TABLE_ORDER.index(t.name))


M_DNS = Sheet(
    name="08_DNS",
    description=(
        "Env 08-network-dns (DNS module): Cloud DNS — public + private zones with record sets, plus the "
        "hybrid resolver (inbound + outbound endpoints, outbound forwarding rules, query access "
        "logging). Applied AFTER 05-network: zones/endpoints/rules reference 05_Network VPCs and "
        "subnets by NAME (resolved from the 05-network state). All resources deploy into ONE "
        "account (Settings.dns_account). Needed Terraform resources: dns_zone, dns_recordset, "
        "dns_private_zone_associate, dns_endpoint, dns_resolver_rule, dns_resolver_rule_associate, "
        "dns_resolver_access_log.\n"
        "HOW PRIVATE DNS RESOLVES ORG-WIDE: a private zone is only visible to VPCs explicitly "
        "associated to it, and association is SAME-ACCOUNT only (the provider has no zone sharing). "
        "The LZ therefore uses the HUB-RESOLVER pattern: every hub + spoke subnet's DHCP hands out "
        "the INBOUND endpoint IPs (05_Network Settings.subnet_dns_servers), so all queries resolve "
        "through the resolver VPC — private zones, the on-prem forwarding rules (associate each "
        "ResolverRules row to the resolver VPC!), and public fall-through (Recursive=TRUE). Zone "
        "names are arbitrary domains (internal TLDs fine); records must sit at/under the zone apex — "
        "use additional zones for other apexes."
    ),
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            description="Account and enterprise project used for DNS resources. The environment assumes the selected account's OrganizationAccountAccessAgency.",
            rows=[
                KV("dns_account",             "string", "lz-infra", "lz-infra",      "Account name from module 1 where DNS resources are deployed, usually the shared-services or hub account that owns the resolver VPC."),
                KV("enterprise_project_name", "string", "",         "landing-zone",  "Enterprise project for private zones, resolver endpoints, and forwarding rules. Must match a CostCenters.Name in Sheet 02. Leave blank to use the default enterprise project."),
            ],
        ),
        Table(
            name="PublicZones",
            kind="object-table",
            description=(
                "Public DNS zones. Use one row per zone and toggle Enabled. Record sets are "
                "defined in RecordSets. Zone names must end with a trailing dot, for example "
                "'example.com.'. Huawei Cloud provides the authoritative name servers, which "
                "must be delegated at your registrar."
            ),
            columns=[
                ("Name",        "string", "Zone apex FQDN with trailing dot (e.g. example.com.)"),
                ("Email",       "string", "SOA contact email (blank = Huawei default)"),
                ("TTL",         "int",    "Zone SOA TTL in seconds (blank = 300)"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "example-ext.example.com.", "Email": "hostmaster@example.com", "TTL": 300, "Description": "Public-facing apex zone"},
            ],
        ),
        Table(
            name="PrivateZones",
            kind="object-table",
            description=(
                "Private DNS zones (resolvable only inside associated VPCs). One row per zone; toggle "
                "Enabled. VPCs is a comma-separated list of VPC NAMES (05_Network hub or spoke VPCs) to "
                "associate — the FIRST is the zone's primary router (huaweicloud_dns_zone.router); the "
                "rest are attached via huaweicloud_dns_private_zone_associate. Name ends with a trailing "
                "dot. Records live in RecordSets keyed by Zone. Recursive = the proxy_pattern: FALSE "
                "(default) = AUTHORITY (the zone owns its whole namespace in-VPC; names you don't record "
                "return NXDOMAIN); TRUE = RECURSIVE (names not in the zone fall through to public DNS - "
                "use this to override only a few names under a broad domain, e.g. a private "
                "myhuaweicloud.com zone that overrides just one endpoint)."
            ),
            columns=[
                ("Name",        "string",   "Private zone FQDN with trailing dot (e.g. internal.example.)"),
                ("VPCs",        "csv-list", "VPC names to associate (from 05_Network). First = primary router; rest via private_zone_associate."),
                ("TTL",         "int",      "Zone SOA TTL in seconds (blank = 300)"),
                ("Recursive",   "bool",     "TRUE = proxy_pattern RECURSIVE (unmatched names fall through to public); blank/FALSE = AUTHORITY"),
                ("Description", "string",   "Purpose"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "internal.example.", "VPCs": "vpc-shared", "TTL": 300, "Recursive": False, "Description": "Internal service-discovery zone (authoritative)"},
            ],
        ),
        Table(
            name="RecordSets",
            kind="object-table",
            description=(
                "DNS record sets for the public and private zones above. Use one row per "
                "record and toggle Enabled. Zone must match a PublicZones or PrivateZones "
                "name. Name is the record FQDN with a trailing dot. Records is a "
                "comma-separated list of values appropriate to the record type."
            ),
            columns=[
                ("Zone",        "string",   "FK -> PublicZones.Name or PrivateZones.Name"),
                ("Name",        "string",   "Record FQDN with trailing dot, within the zone"),
                ("Type",        "string",   "A | AAAA | CNAME | MX | TXT | NS | SRV | CAA"),
                ("Records",     "csv-list", "Comma-separated record values"),
                ("TTL",         "int",      "Record TTL in seconds (blank = 300)"),
                ("Description", "string",   "Purpose"),
            ],
            sample_rows=[
                {"Enabled": False, "Zone": "internal.example.", "Name": "app.internal.example.", "Type": "A", "Records": "10.0.32.10", "TTL": 300, "Description": "App service A record"},
            ],
        ),
        Table(
            name="ResolverEndpoints",
            kind="object-table",
            description=(
                "Hybrid-DNS resolver endpoints (huaweicloud_dns_endpoint), one row each; toggle Enabled. "
                "Direction = 'inbound' (lets on-premises resolvers query Huawei private zones — point "
                "on-prem forwarders at the endpoint IPs) or 'outbound' (lets cloud VPCs forward queries "
                "out via ResolverRules). VPC + Subnets name where the endpoint's resolver IPs live. "
                "Huawei REQUIRES >=2 resolver IPs: either list >=2 Subnets (ideally different AZs for HA), "
                "OR list 1 Subnet and >=2 IPs. One ip_addresses block is created per IP (or per subnet "
                "when IPs is blank)."
            ),
            columns=[
                ("Name",      "string",   "Endpoint name"),
                ("Direction", "string",   "inbound | outbound"),
                ("VPC",       "string",   "FK -> 05_Network VPC name hosting the endpoint subnets"),
                ("Subnets",   "csv-list", "Subnet name(s) within VPC (>=1). Use >=2 (different AZs) for HA, or 1 with >=2 IPs."),
                ("IPs",       "csv-list", "Optional fixed IPs. Provide >=2 here to satisfy the min when using a single subnet; blank = auto-assign (needs >=2 subnets)."),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "lz-dns-inbound",  "Direction": "inbound",  "VPC": "vpc-shared", "Subnets": "shared-dns-az1,shared-dns-az2", "IPs": ""},
                {"Enabled": False, "Name": "lz-dns-outbound", "Direction": "outbound", "VPC": "vpc-shared", "Subnets": "shared-dns-az1,shared-dns-az2", "IPs": ""},
            ],
        ),
        Table(
            name="ResolverRules",
            kind="object-table",
            description=(
                "Outbound resolver forwarding rules. Use one row per rule and toggle Enabled. "
                "Queries under DomainName are forwarded through the named outbound endpoint to"
                " TargetIPs. VPCs is a comma-separated list of VPC names associated with the "
                "rule. DomainName must end with a trailing dot."
            ),
            columns=[
                ("Name",       "string",   "Resolver rule name"),
                ("Endpoint",   "string",   "FK -> ResolverEndpoints.Name (must be Direction=outbound)"),
                ("DomainName", "string",   "Domain to forward, trailing dot (e.g. corp.onprem.)"),
                ("TargetIPs",  "csv-list", "Comma-separated target DNS server IPs (on-prem/external)"),
                ("VPCs",       "csv-list", "VPC names (from 05_Network) to associate the rule with"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "fwd-onprem", "Endpoint": "lz-dns-outbound", "DomainName": "corp.onprem.", "TargetIPs": "192.168.0.10,192.168.0.11", "VPCs": "vpc-shared"},
            ],
        ),
        Table(
            name="AccessLogs",
            kind="object-table",
            description=(
                "DNS resolver query logging to LTS. Use one row per configuration and toggle "
                "Enabled. LTSGroup and LTSStream are created for query logs. VPCs is a "
                "comma-separated list of VPCs whose resolver queries are logged."
            ),
            columns=[
                ("Name",      "string",   "Label for this access-log config (informational)"),
                ("LTSGroup",  "string",   "LTS log group name to write query logs to"),
                ("LTSStream", "string",   "LTS log stream (topic) name to write query logs to"),
                ("VPCs",      "csv-list", "VPC names (from 05_Network) whose DNS queries are logged"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "dns-query-log", "LTSGroup": "lz-dns-logs", "LTSStream": "dns-queries", "VPCs": "vpc-shared"},
            ],
        ),
    ],
)


M4_PERIMETER = Sheet(
    name="04_Perimeter",
    description="Module 4: data-perimeter service control policies, identity guardrails, predefined tags, and Config setup. Feeds the 04-perimeter environment.",
    tables=[
        Table(
            name="SCPs",
            kind="object-table",
            description=(
                "Landing Zone service control policies. Each row represents one policy. "
                "Enabled creates the policy, and Enforce promotes it from dry-run to enforced."
                " Fill only the settings that apply to that policy and leave the remaining "
                "cells blank. Do not rename the Policy keys."
            ),
            columns=[
                ("Policy",            "string",   "Policy key (fixed — do not rename)"),
                ("Enforce",           "bool",     "TRUE = attach the SCP (LIVE/enforced); FALSE = created but not attached (staged/inert)"),
                ("Name",              "string",   "Explicit SCP name"),
                ("AllowedOrgPath",    "string",   "RAM-share / RMS-aggregation only: '<org-id>/<root-id>/*'. Blank = derive from org_id + root_id."),
                ("MandatoryTags",     "csv-list", "require_mandatory_tags only: required tag keys (e.g. Project,Owner,Environment,BU)."),
                ("ExceptionTagKey",   "string",   "deny_public_obs only: exception RESOURCE-tag key. BLANK = no exception (public denied outright). Create the bucket private + tagged first, THEN its ACL/policy can be made public."),
                ("ExceptionTagValue", "string",   "deny_public_obs only: exception tag value (default 'approved')."),
                ("AdminPrincipalURNs","csv-list", "protect_cts_tracker only: principal URN(s) allowed to modify CTS. BLANK = no exception."),
                ("AllowedRegions",    "csv-list", "deny_outside_allowed_region only: allowed region code(s) e.g. ap-southeast-3."),
            ],
            sample_rows=[
                {"Enabled": True, "Policy": "deny_leave_org",                    "Enforce": False, "Name": "deny-leave-organization"},
                {"Enabled": True, "Policy": "deny_root_user",                    "Enforce": False, "Name": "deny-root-user"},
                {"Enabled": True, "Policy": "deny_unauthorized_ram_share",       "Enforce": False, "Name": "deny-unauthorized-ram-share",       "AllowedOrgPath": ""},
                {"Enabled": True, "Policy": "deny_unauthorized_rms_aggregation", "Enforce": False, "Name": "deny-unauthorized-rms-aggregation", "AllowedOrgPath": ""},
                {"Enabled": True, "Policy": "require_mandatory_tags",            "Enforce": False, "Name": "deny-create-without-mandatory-tags", "MandatoryTags": "Project,Owner,Environment,BU"},
                {"Enabled": True, "Policy": "deny_public_obs",                   "Enforce": False, "Name": "deny-public-obs",                    "ExceptionTagKey": "public-access", "ExceptionTagValue": "approved"},
                {"Enabled": True, "Policy": "protect_cts_tracker",               "Enforce": False, "Name": "protect-cts-tracker",                "AdminPrincipalURNs": ""},
                {"Enabled": True, "Policy": "deny_outside_allowed_region",       "Enforce": False, "Name": "deny-outside-allowed-region",        "AllowedRegions": "ap-southeast-3"},
            ],
        ),
        Table(
            name="PredefinedTags",
            kind="object-table",
            description=(
                "TMS predefined tag dictionary applied to the management account and every "
                "module 1 account. Values is a comma-separated list; leave it blank for "
                "free-form values. New accounts added in module 1 receive the same predefined "
                "tags when the environment is rebuilt."
            ),
            columns=[
                ("Key",    "string",   "Tag key"),
                ("Values", "csv-list", "Comma-separated allowed values; '' = free-form"),
            ],
            sample_rows=[
                {"Enabled": True, "Key": "project", "Values": ""},
                {"Enabled": True, "Key": "owner",   "Values": ""},
                {"Enabled": True, "Key": "env",     "Values": "production,staging,development,shared"},
                {"Enabled": True, "Key": "bu",      "Values": ""},
            ],
        ),
        Table(
            name="ConfigSetup",
            kind="scalar",
            description=(
                "Config service (RMS) org setup. Config is a GLOBAL service: org-wide resources "
                "(aggregator, conformance packs below) run from ONE account — set ConfigAdminAccount "
                "to the account they deploy on, typically the service.RMSMultiAccountSetup delegated "
                "admin (Sheet 01 TrustedServices). build_envs generates a provider alias + module "
                "call for that account. Leave ConfigAdminAccount blank to skip all Config setup. The "
                "resource recorder is the per-account 'turn Config on' tracker (records to an OBS "
                "bucket / SMN); the org aggregator pulls every member's compliance data into the "
                "admin account for a single-pane view."
            ),
            rows=[
                KV("config_admin_account",      "string", "", "lz-security",       "Account name from Sheet 01 that hosts organization-wide Config. Leave blank to skip Config setup. This should match the delegated administrator for RMS multi-account setup."),
                KV("enable_config_recorder",    "bool",   True, True,              "Create the Config resource recorder in the administrator account. A recorder is required before rules or conformance packages can evaluate resources."),
                KV("recorder_agency_name",      "string", "lz-config-recorder-trust-agency", "lz-config-recorder-trust-agency", "Name of the recorder trust agency created by Terraform. Use a name different from the system rms_tracker_trust_agency to avoid a naming conflict."),
                KV("create_recorder_agency",    "bool",   True, True,              "TRUE creates the v5 trust agency. FALSE references an existing agency using recorder_agency_name."),
                KV("recorder_bucket_name",      "string", "", "example-config-snapshots", "OBS bucket used for Config recorder snapshots. Required when enable_config_recorder is TRUE."),
                KV("create_recorder_bucket",    "bool",   True, True,              "TRUE creates a private, versioned, KMS-encrypted bucket with public access blocked. FALSE uses the existing bucket named in recorder_bucket_name."),
                KV("recorder_bucket_region",    "string", "", "ap-southeast-3",    "Region of the Config recorder OBS bucket. Leave blank to use home_region."),
                KV("recorder_all_supported",    "bool",   True, True,              "TRUE records all supported resource types. FALSE restricts recording to a custom set that is not exposed in this workbook."),
                KV("recorder_smn_topic_urn",    "string", "", "",                  "Optional SMN topic URN for Config change notifications. Leave blank to use OBS delivery only."),
                KV("enable_config_aggregator",  "bool",   True, True,              "Create an organization-type resource aggregator in the administrator account for multi-account compliance visibility."),
                KV("aggregator_name",           "string", "lz-org-aggregator", "example-org-aggregator", "Name of the organization resource aggregator."),
            ],
        ),
        Table(
            name="ConfigConformancePacks",
            kind="object-table",
            description=(
                "Config (RMS) conformance packages provide detective controls. They "
                "continuously evaluate resources and report violations, complementing the "
                "preventive SCPs above. Set Enabled=TRUE for each package you want to deploy "
                "organization-wide. TemplateKey identifies the predefined package template; "
                "leave it blank to resolve the template by name from the Config catalog."
            ),
            columns=[
                ("Package",     "string",   "Conformance package (fixed name — do not rename)"),
                ("Category",    "string",   "Cloud best practice | Industry standard | Security config guide"),
                ("Name",        "string",   "Org conformance-pack resource name (the one name it carries org-wide). Blank = slug of Package."),
                ("TemplateKey", "string",   "Predefined template key; blank = resolve by name from the templates data source"),
                ("Vars",        "csv-list", "Optional parameter overrides as 'key=value' (comma-separated); values are JSON-encoded as strings. Needed where a template default is invalid — e.g. PCI DSS needs 'trackBucket=<cts-audit-bucket>' (default '' fails minLength 3). Blank = template defaults."),
                ("Description", "string",   "What the package evaluates"),
                ("ExcludedAccounts", "csv-list", "Accounts to EXEMPT from this pack - they skip the rule rollout entirely (fewer resources, and avoids a member whose RFS deployment keeps failing, e.g. Huawei edge-WAF 418 on read-back). Account Names from Sheet 01 OR raw 32-hex domain IDs, comma-separated. The management (master) account is always excluded automatically. Blank = no extra exemptions."),
            ],
            sample_rows=[
                # ── Best practices on the cloud ──
                {"Enabled": True,  "Package": "Landing Zone",                              "Category": "Cloud best practice",    "TemplateKey": "Operational-Best-Practices-for-Landing-Zone.tf.json",                                           "Description": "Landing Zone basic scenarios (multi-account org, network, identity, data perimeter, security, audit, O&M, cost)."},
                {"Enabled": False, "Package": "Network Security",                          "Category": "Cloud best practice",    "TemplateKey": "Operational-Best-Practices-for-Huawei-Cloud-Network-Security.tf.json",                          "Description": "Huawei Cloud network-security compliance practices."},
                {"Enabled": False, "Package": "Compute Services",                          "Category": "Cloud best practice",    "TemplateKey": "Operational-Best-Practices-for-Compute-Services.tf.json",                                       "Description": "Compute-services baseline (encryption, lifecycle, recommended config)."},
                {"Enabled": False, "Package": "Network and Data Security",                 "Category": "Cloud best practice",    "TemplateKey": "Operational-Best-Practices-for-Internet-and-Data-Security.tf.json",                             "Description": "Network + data security best practices."},
                {"Enabled": False, "Package": "Architecture Security Best Practices",      "Category": "Cloud best practice",    "TemplateKey": "Architecture-Security-Pillar-Operational-Best-Practices.tf.json",                               "Description": "Architecture security pillar operational best practices."},
                {"Enabled": False, "Package": "Idle Asset Management",                     "Category": "Cloud best practice",    "TemplateKey": "Operational-Best-Practices-for-Idle-Asset-Management.tf.json",                                  "Description": "Detects idle/unattached resources (cost + hygiene)."},
                {"Enabled": False, "Package": "Web Application Firewall",                  "Category": "Cloud best practice",    "TemplateKey": "Operational-Best-Practices-for-WAF.tf.json",                                                    "Description": "WAF coverage / protection-policy best practices."},
                {"Enabled": False, "Package": "Content Delivery Network",                 "Category": "Cloud best practice",    "TemplateKey": "Operational-Best-Practices-for-CDN.tf.json",                                                    "Description": "CDN security and configuration best practices."},
                # ── Industry standards ──
                {"Enabled": False, "Package": "PCI DSS",                                  "Category": "Industry standard",      "TemplateKey": "PCI-DSS-Compliance-Check.tf.json",                                                              "Description": "Payment Card Industry Data Security Standard controls."},
                {"Enabled": False, "Package": "SWIFT CSP",                                "Category": "Industry standard",      "TemplateKey": "SWIFT-CSP-Compliance-Check.tf.json",                                                            "Description": "SWIFT Customer Security Programme controls."},
                {"Enabled": False, "Package": "ENISA Requirements",                       "Category": "Industry standard",      "TemplateKey": "ENISA-Cybersecurity-Guide-Compliance-Check.tf.json",                                            "Description": "EU Agency for Cybersecurity (ENISA) requirements for SMEs."},
                {"Enabled": False, "Package": "Germany C5",                               "Category": "Industry standard",      "TemplateKey": "Germany-C5-Compliance-Check.tf.json",                                                           "Description": "Germany Cloud Computing Compliance Criteria Catalogue (C5)."},
                {"Enabled": False, "Package": "Hong Kong Monetary Authority",             "Category": "Industry standard",      "TemplateKey": "Hong-Kong-Monetary-Authority-Compliance-Check.tf.json",                                         "Description": "HKMA requirements for financial institutions."},
                {"Enabled": False, "Package": "Singapore Financial Industry (MAS TRMG)",   "Category": "Industry standard",      "TemplateKey": "Operational-Best-Practices-for-MAS-TRMG.tf.json",                                               "Description": "MAS Technology Risk Management Guidelines (Singapore)."},
                {"Enabled": False, "Package": "Classified Protection of Cybersecurity L3 (2.0)", "Category": "Industry standard", "TemplateKey": "Classified-Protection-of-Cybersecurity-Compliance-Check.tf.json",                          "Description": "China DJCP/MLPS Level 3 (2.0) classified protection."},
                # ── Security configuration guides ──
                {"Enabled": False, "Package": "Huawei Cloud Security Config Guide (Level 1)", "Category": "Security config guide", "TemplateKey": "Huawei-Cloud-Security-Configuration-Guide-Check-level-1.tf.json",                            "Description": "Baseline (L1) config guidance for key Huawei Cloud services."},
                {"Enabled": False, "Package": "Huawei Cloud Security Config Guide (Level 2)", "Category": "Security config guide", "TemplateKey": "Huawei-Cloud-Security-Configuration-Guide-Check-level-2.tf.json",                            "Description": "Enhanced (L2) config guidance for key Huawei Cloud services."},
            ],
        ),
    ],
)


M_CFW = Sheet(
    name="09_CFW",
    description=(
        "Env 09-network-cfw (CFW module): Cloud Firewall rule plane on the hub firewall created in "
        "05-network — object groups (IP address groups, app/network domain name groups, service "
        "groups), internet-border rules (EIP/NAT ACL rules + black/white lists) and VPC-border "
        "rules (protection ACL rules + black/white lists). Applied AFTER 05-network: the firewall "
        "instance ID is read from the 05-network state and its protect-object IDs (0=internet / "
        "north-south, 1=VPC / east-west) are resolved via the cfw_firewalls data source. Runs in "
        "Settings.cfw_account (the hub account). Required Terraform resources: cfw_address_group "
        "(+_member), cfw_domain_name_group, cfw_service_group (+_member), cfw_acl_rule, "
        "cfw_black_white_list."
    ),
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            description="Account that hosts the hub Cloud Firewall. This must match 05_Network Settings.hub_account. The environment assumes the account's OrganizationAccountAccessAgency and reads the firewall ID from 05-network state.",
            rows=[
                KV("cfw_account", "string", "lz-infra", "lz-infra", "Account name from module 1 that owns the hub Cloud Firewall. This must match 05_Network Settings.hub_account."),
                KV("enable_anti_virus", "bool", False, True, "Enable antivirus protection for the internet protected object across supported protocols, with blocking action."),
                KV("enable_reverse_shell_defense", "bool", False, True, "Set reverse-shell advanced IPS rules on the internet protected object to enabled and blocking. Re-applying Terraform reasserts this setting."),
                KV("alarm_topic_name", "string", "", "lz-infra-sg-prd-cs-smntopic-01", "SMN topic name in the Cloud Firewall account for firewall alarm notifications. Required when any alarm toggle below is enabled."),
                KV("enable_attack_alarm", "bool", False, True, "Notify the alarm topic for CRITICAL and HIGH attack detections, at all times and for every occurrence."),
                KV("enable_traffic_alarm", "bool", False, True, "Notify the alarm topic when firewall bandwidth utilization exceeds 80%."),
                KV("enable_eip_unprotected_alarm", "bool", False, True, "Notify the alarm topic when an EIP is not protected by the firewall."),
                KV("enable_threat_intel_alarm", "bool", False, True, "Notify the alarm topic for CRITICAL and HIGH threat-intelligence detections."),
            ],
        ),
        Table(
            name="AddressGroups",
            kind="object-table",
            description=(
                "User-defined IP address groups. Use one row per group and toggle Enabled. "
                "Border selects the internet or VPC protected object. Members is a "
                "comma-separated list of IP addresses, CIDRs, or ranges."
            ),
            columns=[
                ("Name",        "string",   "Address group name"),
                ("Border",      "string",   "internet | vpc — which protected object the group lives on. USE internet: groups bound to the vpc object work in rules but are INVISIBLE in the console object-group list (confirmed live 2026-07-08); rules on either border accept internet-bound groups"),
                ("AddressType", "string",   "ipv4 | ipv6 (default ipv4)"),
                ("Members",     "csv-list", "Comma-separated IPs / CIDRs / ranges"),
                ("Description", "string",   "Purpose"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "corp-cidrs", "Border": "internet", "AddressType": "ipv4", "Members": "10.0.0.0/8,192.168.0.0/16", "Description": "Corporate networks"},
            ],
        ),
        Table(
            name="DomainGroups",
            kind="object-table",
            description=(
                "Domain name groups. Use one row per group and toggle Enabled. Type can be "
                "application for HTTP/HTTPS/TLS-SNI matching or network for domain-to-IP "
                "resolution. Border selects the protected object. Domains is a comma-separated"
                " list."
            ),
            columns=[
                ("Name",        "string",   "Domain group name"),
                ("Border",      "string",   "internet | vpc"),
                ("Type",        "string",   "application | network"),
                ("Domains",     "csv-list", "Comma-separated domain names (e.g. *.example.com,api.example.com)"),
                ("Description", "string",   "Purpose"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "app-domains", "Border": "internet", "Type": "application", "Domains": "*.example.com",          "Description": "Allowed app domains"},
                {"Enabled": False, "Name": "net-domains", "Border": "internet", "Type": "network",     "Domains": "mirror.internal.example", "Description": "Network domain set"},
            ],
        ),
        Table(
            name="ServiceGroups",
            kind="object-table",
            description=(
                "User-defined service groups. Use one row per group and toggle Enabled. "
                "Members is a comma-separated list in 'protocol/srcport/dstport' format. "
                "Protocol may be tcp, udp, icmp, or icmpv6; ports may be a single value, a "
                "range, or 'any'."
            ),
            columns=[
                ("Name",        "string",   "Service group name"),
                ("Border",      "string",   "internet | vpc. USE internet — vpc-bound groups are invisible in the console list (see AddressGroups.Border)"),
                ("Members",     "csv-list", "Comma-separated 'protocol/srcport/dstport' entries"),
                ("Description", "string",   "Purpose"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "web-svc", "Border": "internet", "Members": "tcp/any/80,tcp/any/443", "Description": "Web ports"},
            ],
        ),
        Table(
            name="ACLRules",
            kind="object-table",
            description=(
                "CFW ACL rules (huaweicloud_cfw_acl_rule). One row per rule; toggle Enabled. Kind "
                "selects the protected object + rule type: 'eip' (internet border, EIP rule), 'nat' "
                "(internet border, NAT rule) or 'vpc' (VPC border, protection rule). Action = allow | "
                "deny. Source / Destination are comma-separated tokens: a bare IP/CIDR, "
                "'addrgroup:<Name>' (AddressGroups), 'domaingroup:<Name>' (DomainGroups; destination "
                "only), or 'any'. Service is comma-separated: 'any', an inline 'protocol/srcport/"
                "dstport', 'svcgroup:<Name>' (ServiceGroups), or 'app:<APP>' (L7 application, e.g. "
                "app:HTTPS). Rules are added in row order; reorder in the console if precedence matters."
            ),
            columns=[
                ("Name",        "string",   "Rule name"),
                ("Kind",        "string",   "eip | nat | vpc"),
                ("Action",      "string",   "allow | deny"),
                ("Source",      "csv-list", "Comma-separated: IP/CIDR | addrgroup:<Name> | any"),
                ("Destination", "csv-list", "Comma-separated: IP/CIDR | addrgroup:<Name> | domaingroup:<Name> | any"),
                ("Service",     "csv-list", "Comma-separated: any | protocol/srcport/dstport | svcgroup:<Name> | app:<APP>"),
                ("Status",      "string",   "enable | disable (default enable)"),
                ("Description", "string",   "Purpose"),
                ("Direction",   "string",   "inbound | outbound — internet border (eip/nat) only; blank = nat->outbound, eip->inbound. Inbound rules cannot use domain groups (CFW.00400028). Ignored for vpc."),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "allow-web-egress", "Kind": "eip", "Action": "allow", "Source": "addrgroup:corp-cidrs", "Destination": "any", "Service": "svcgroup:web-svc", "Status": "enable", "Description": "Allow corp web egress", "Direction": "outbound"},
                {"Enabled": False, "Name": "deny-vpc-lateral", "Kind": "vpc", "Action": "deny",  "Source": "any",                  "Destination": "any", "Service": "any",            "Status": "enable", "Description": "Default east-west deny"},
            ],
        ),
        Table(
            name="BlackWhiteLists",
            kind="object-table",
            description=(
                "Cloud Firewall allowlists and blocklists. Use one row per entry and toggle "
                "Enabled. Direction determines whether the source or destination address is "
                "matched. Port applies only to TCP and UDP entries."
            ),
            columns=[
                ("Name",        "string", "Label (informational — the resource has no name)"),
                ("Border",      "string", "internet | vpc"),
                ("ListType",    "string", "blacklist | whitelist"),
                ("Direction",   "string", "source | destination"),
                ("Protocol",    "string", "tcp | udp | icmp | icmpv6 | any"),
                ("AddressType", "string", "ipv4 | ipv6 | domain"),
                ("Address",     "string", "Single IP / CIDR / domain"),
                ("Port",        "string", "Destination port (tcp/udp only); blank otherwise"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "block-bad-ip", "Border": "internet", "ListType": "blacklist", "Direction": "source", "Protocol": "any", "AddressType": "ipv4", "Address": "203.0.113.0/24", "Port": "", "Description": "Known-bad source range"},
            ],
        ),
    ],
)


M_SGACL = Sheet(
    name="11_SGACL",
    description=(
        "Env 11-network-sgacl (secgroups module 15): workload security groups + rules, one "
        "module call per member account named in SecurityGroups.Account (assume_role provider). "
        "Groups are created with delete_default_rules=true - NO implicit allows; every permit "
        "(including egress) is an explicit SGRules row. Security groups are region-scoped (no "
        "VPC binding); attaching them to ECS NICs is the workload/migration team's step. "
        "SG-to-SG references (Remote = sg:<Name>) work only within one account. The "
        "NetworkACLs / ACLRules tables are RESERVED for subnet network ACLs - not implemented "
        "yet; enabled rows there fail validation (LZR-031). Required Terraform resources: "
        "networking_secgroup, networking_secgroup_rule."
    ),
    tables=[
        Table(
            name="SecurityGroups",
            kind="object-table",
            description=(
                "Security groups created with default rules removed. Use one row per group and"
                " toggle Enabled. Account must match a 01_Foundation account name. Tags uses a"
                " comma-separated k=v list and should include the mandatory project, bu, "
                "owner, and env tags."
            ),
            columns=[
                ("Account",     "string",  "Owning member account name (01_Foundation)"),
                ("Name",        "string",  "Security group name"),
                ("Description", "string",  "Purpose"),
                ("Tags",        "string",  "k=v,k=v - mandatory tag set required by the tag SCP"),
            ],
            sample_rows=[
                {"Enabled": False, "Account": "workload-a", "Name": "app-sg-01", "Description": "App tier", "Tags": "project=app,bu=corp,owner=Platform,env=prd"},
                {"Enabled": False, "Account": "workload-a", "Name": "db-sg-01",  "Description": "DB tier",  "Tags": "project=app,bu=corp,owner=Platform,env=prd"},
            ],
        ),
        Table(
            name="SGRules",
            kind="object-table",
            description=(
                "Security group rules (huaweicloud_networking_secgroup_rule). One row per rule; "
                "toggle Enabled. SG names a SecurityGroups row (rules inherit its account). "
                "Remote: a CIDR, sg:<Name> (another group in the SAME account) or self. Ports: "
                "single (443), range (5985-5986), list (80,443) or blank = all ports. Protocol "
                "tcp | udp | icmp | any (icmp ignores Ports). Groups have no default rules, so "
                "give every group an explicit egress row (standard: any/0.0.0.0/0 - CFW governs "
                "the destinations)."
            ),
            columns=[
                ("SG",          "string", "SecurityGroups.Name this rule belongs to"),
                ("Direction",   "string", "ingress | egress"),
                ("Protocol",    "string", "tcp | udp | icmp | any (default any)"),
                ("Ports",       "string", "443 | 5985-5986 | 80,443 | blank = all"),
                ("Remote",      "string", "CIDR | sg:<Name> (same account) | self"),
                ("Action",      "string", "allow | deny (default allow)"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[
                {"Enabled": False, "SG": "app-sg-01", "Direction": "ingress", "Protocol": "tcp", "Ports": "443",  "Remote": "10.0.0.0/8",   "Action": "allow", "Description": "Users to app"},
                {"Enabled": False, "SG": "db-sg-01",  "Direction": "ingress", "Protocol": "tcp", "Ports": "1433", "Remote": "sg:app-sg-01", "Action": "allow", "Description": "App to MSSQL"},
                {"Enabled": False, "SG": "app-sg-01", "Direction": "egress",  "Protocol": "any", "Ports": "",     "Remote": "0.0.0.0/0",    "Action": "allow", "Description": "Egress all (CFW governs destinations)"},
            ],
        ),
        Table(
            name="NetworkACLs",
            kind="object-table",
            description=(
                "RESERVED - subnet network ACLs (huaweicloud_vpc_network_acl) are not implemented "
                "yet. Keep this table empty: enabled rows fail validation (LZR-031). When "
                "implemented, ACLs will associate to spoke subnets as a second, subnet-level "
                "enforcement layer (stateful; unmatched traffic denied once associated)."
            ),
            columns=[
                ("Account",     "string",   "Owning member account name"),
                ("Name",        "string",   "Network ACL name"),
                ("VPC",         "string",   "Spoke VPC name (05_Network)"),
                ("Subnets",     "csv-list", "Subnet names to associate"),
                ("Description", "string",   "Purpose"),
            ],
            sample_rows=[],
        ),
        Table(
            name="ACLRules",
            kind="object-table",
            description=(
                "RESERVED - rules for NetworkACLs; not implemented yet. Keep empty (LZR-031)."
            ),
            columns=[
                ("ACL",         "string", "NetworkACLs.Name"),
                ("Direction",   "string", "ingress | egress"),
                ("Action",      "string", "allow | deny"),
                ("Protocol",    "string", "tcp | udp | icmp | any"),
                ("Source",      "string", "Source CIDR"),
                ("SourcePorts", "string", "Source ports (blank = all)"),
                ("Destination", "string", "Destination CIDR"),
                ("DestPorts",   "string", "Destination ports (blank = all)"),
                ("Description", "string", "Purpose"),
            ],
            sample_rows=[],
        ),
    ],
)


M_VPN = Sheet(
    name="10_VPN",
    description=(
        "Environment 10-network-vpn: enterprise site-to-cloud VPN gateways, customer gateways,"
        " and IPsec connections. Apply after 05-network because gateway attachments are "
        "resolved from the 05-network state. The environment runs in Settings.vpn_account."
    ),
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            description="Account hosting the VPN, usually the 05-network hub account. The environment assumes this account's OrganizationAccountAccessAgency.",
            rows=[
                KV("vpn_account",             "string", "lz-infra", "lz-infra",     "Account name from module 1 where VPN resources are deployed, usually the hub account."),
                KV("enterprise_project_name", "string", "",         "landing-zone", "Enterprise project for VPN resources. Must match a CostCenters.Name in Sheet 02. Leave blank to use the default enterprise project."),
            ],
        ),
        Table(
            name="Gateways",
            kind="object-table",
            description=(
                "S2C VPN gateways (huaweicloud_vpn_gateway). One row per gateway; toggle Enabled. "
                "Attachment = 'vpc' (bind to a 05_Network VPC) or 'er' (bind to the hub Enterprise "
                "Router). EITHER WAY, VPC + ConnectSubnet are REQUIRED: for vpc they are the gateway's "
                "vpc_id + connect_subnet; for er they are the access_vpc_id + access_subnet_id (the "
                "gateway's interconnection plane — Huawei rejects an ER gateway without one). "
                "NetworkType = public (2 EIPs are created at BandwidthSize Mbit/s) or private. HAMode = "
                "active-active | active-standby. AZs: LEAVE BLANK to auto-select 2 AZs that actually stock "
                "the chosen flavor+attachment (recommended — hardcoding AZs that don't offer the flavor "
                "causes 'VPN.0001: resource not enough'). Only set AZs to pin specific zones. ASN is the "
                "gateway BGP ASN. Flavor blank = API default (Professional1)."
            ),
            columns=[
                ("Name",          "string",   "Gateway name"),
                ("Attachment",    "string",   "vpc | er"),
                ("VPC",           "string",   "REQUIRED. 05_Network VPC name (vpc attach -> vpc_id; er attach -> access_vpc_id)"),
                ("ConnectSubnet", "string",   "REQUIRED. Subnet name within VPC (vpc attach -> connect_subnet; er attach -> access_subnet_id)"),
                ("LocalSubnets",  "csv-list", "vpc attachment only: local CIDRs the gateway advertises to on-prem"),
                ("NetworkType",   "string",   "public | private (default public)"),
                ("HAMode",        "string",   "active-active | active-standby (default active-standby)"),
                ("Flavor",        "string",   "Gateway flavor (e.g. Basic, Professional1); blank = API default"),
                ("AZs",           "csv-list", "Blank = auto-select 2 valid AZs for flavor+attachment (recommended). Only fill to pin zones (e.g. ap-southeast-3a,ap-southeast-3b)."),
                ("ASN",           "int",      "Gateway BGP ASN (default 64512)"),
                ("BandwidthSize", "int",      "public only: bandwidth (Mbit/s) for each created EIP"),
                ("ERAssocRouteTable", "string", "er attach only: FIXED ER route table (er-inbound | er-outbound | er-hybrid) the gateway's ER attachment ASSOCIATES to — the table that steers traffic ARRIVING from on-prem (use er-hybrid so DC traffic is CFW-inspected). Blank = no association."),
                ("ERPropRouteTable",  "string", "er attach only: FIXED ER route table (er-inbound | er-outbound | er-hybrid) the attachment PROPAGATES into — where on-prem routes land (BGP-learned, or PeerSubnets for static tunnels; typically er-outbound). This is the ONLY way on-prem routes enter ER — static routes to VPN attachments are rejected (ER.04006105). Blank = no propagation."),
                ("EIPChargeMode", "string", "public only: EIP billing mode - bandwidth (default) or traffic. FORCENEW on the gateway: to switch on a LIVE gateway, change billing in the EIP console first, then set this to match and refresh state - never apply the diff."),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "lz-s2c-vpngw", "Attachment": "er", "VPC": "vpc-shared", "ConnectSubnet": "shared-vpn", "LocalSubnets": "", "NetworkType": "public", "HAMode": "active-standby", "Flavor": "Professional1", "AZs": "", "ASN": 64512, "BandwidthSize": 100, "ERAssocRouteTable": "er-hybrid", "ERPropRouteTable": "er-outbound"},
            ],
        ),
        # GatewayRoutes (static ER routes -> VPN attachment) WITHDRAWN 2026-07:
        # Huawei ER rejects static routes to VPN attachments (ER.04006105 — allowed
        # types: vpc/peering/cfw/connect/5G). On-prem routes enter ER route tables
        # exclusively via the gateway's PROPAGATION (ERPropRouteTable): BGP-learned
        # prefixes, or the connection's PeerSubnets for static-type tunnels.
        Table(
            name="CustomerGateways",
            kind="object-table",
            description=(
                "Customer gateways representing on-premises VPN devices. Use one row per "
                "device and toggle Enabled. IP is the device's public IP. ASN is used when "
                "RouteMode is bgp. RouteMode can be static or bgp."
            ),
            columns=[
                ("Name",      "string", "Customer gateway name"),
                ("IP",        "string", "On-premises public IP"),
                ("ASN",       "int",    "On-prem BGP ASN (for RouteMode=bgp; default 65000)"),
                ("RouteMode", "string", "static | bgp"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "onprem-dc1", "IP": "203.0.113.10", "ASN": 65000, "RouteMode": "bgp"},
            ],
        ),
        Table(
            name="Connections",
            kind="object-table",
            description=(
                "IPsec VPN connections (huaweicloud_vpn_connection) — the tunnels binding a Gateway to "
                "a CustomerGateway. One row per connection; toggle Enabled. Gateway / CustomerGateway "
                "are FKs to the tables above. VPNType = policy | static | bgp. PeerSubnets is a "
                "comma-separated list of on-prem CIDRs. HARole = master | slave (which gateway EIP the "
                "tunnel binds to; active-standby gateways use master, active-active use both). PSK is "
                "the IPsec pre-shared key (SENSITIVE - written to the gitignored tfvars, never commit)."
            ),
            columns=[
                ("Name",            "string",   "Connection name"),
                ("Gateway",         "string",   "FK -> Gateways.Name"),
                ("CustomerGateway", "string",   "FK -> CustomerGateways.Name"),
                ("VPNType",         "string",   "policy | static | bgp"),
                ("PeerSubnets",     "csv-list", "On-prem CIDRs reachable over the tunnel"),
                ("HARole",          "string",   "master | slave (default master)"),
                ("PSK",             "string",   "IPsec pre-shared key (sensitive)"),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "lz-s2c-conn-dc1", "Gateway": "lz-s2c-vpngw", "CustomerGateway": "onprem-dc1", "VPNType": "bgp", "PeerSubnets": "192.168.0.0/16", "HARole": "master", "PSK": "REPLACE_WITH_STRONG_PSK"},
            ],
        ),
    ],
)


M5_SECURITY = Sheet(
    name="07_Security",
    description="Environment 07-security: SecMaster in the security account, plus Basic Anti-DDoS for hub EIPs and a dedicated WAF in the hub DMZ.",
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            rows=[
                KV("security_account",         "string", "lz-security",  "lz-security",  "Account name from module 1 where the SecMaster workspace is deployed."),
                KV("secmaster_workspace_name", "string", "lz-secmaster", "lz-secmaster", "Name of the SecMaster workspace."),
                KV("enable_hss",               "bool",   False,           False,           "RESERVED - Host Security Service is not implemented; the flag is wired to the module but deploys nothing. Keep FALSE (LZR-033) and record the requirement as a decision."),
                KV("hss_quota_count",          "int",    0,               0,               "RESERVED - see enable_hss. Number of HSS quotas to purchase once the service is implemented."),
                KV("enable_dbss",              "bool",   False,           False,           "RESERVED - Database Security Service is not implemented; the flag is wired to the module but deploys nothing. Keep FALSE (LZR-033) and record the requirement as a decision."),
                KV("enable_member_workspaces", "bool",   False,           False,           "Reserved for a future Pattern B upgrade."),
            ],
        ),
        Table(
            name="SecMasterModules",
            kind="list-single",
            description="SecMaster functional modules to enable.",
            sample_rows=["security_governance", "alert_management"],
        ),
        Table(
            name="AlertRules",
            kind="object-table",
            description="Baseline SecMaster detection rules.",
            columns=[
                ("Name",        "string", "Rule name"),
                ("Description", "string", "Purpose"),
                ("Severity",    "string", "tips | low | medium | high | fatal"),
                ("RuleType",    "string", "e.g. log"),
                ("Query",       "string", "Detection query"),
            ],
            sample_rows=[],
        ),
        Table(
            name="AntiDDoS",
            kind="object-table",
            description=(
                "Basic (Cloud Native) Anti-DDoS traffic-cleaning per EIP — pay-per-use tuning of the free "
                "per-EIP protection; nothing is purchased and 'destroy' just resets the default threshold. "
                "EIP references a 05_Network EIPs row by Name (resolved from 05-network state; deployed into "
                "the hub account). AlarmTopic optionally names a 06_Observability SMN topic for cleaning "
                "alarms (resolved from 06-observability state; blank = no notification). CNAD Advanced / AAD "
                "need pre-purchased instances and are configured in console, not here."
            ),
            columns=[
                ("Name",          "string", "Row name (unique)"),
                ("EIP",           "string", "FK -> 05_Network EIPs.Name (the protected EIP)"),
                ("ThresholdMbps", "int",    "Traffic-cleaning threshold: 10|30|50|70|100|120|150|200|250|300|1000"),
                ("AlarmTopic",    "string", "SMN topic NAME from 06_Observability (in the hub account). Blank = no alarm."),
            ],
            sample_rows=[
                {"Enabled": False, "Name": "nat-egress",  "EIP": "eip-nat", "ThresholdMbps": 300, "AlarmTopic": ""},
                {"Enabled": False, "Name": "elb-ingress", "EIP": "eip-elb", "ThresholdMbps": 300, "AlarmTopic": ""},
            ],
        ),
        Table(
            name="WAF",
            kind="scalar",
            description=(
                "Dedicated WAF instance deployed in the hub DMZ VPC. Domains in the table "
                "below route through this WAF. VPC, subnet, and security-group names are "
                "resolved from the 05_Network state."
            ),
            rows=[
                KV("enable_waf",             "bool",   False, False, "Create the dedicated WAF instance, policy, and protected domains."),
                KV("waf_instance_name",      "string", "lz-waf", "lz-waf", "Name of the dedicated WAF instance."),
                KV("waf_specification_code", "string", "waf.instance.professional", "waf.instance.professional", "waf.instance.professional (WI-500) | waf.instance.enterprise (WI-100)."),
                KV("waf_availability_zone",  "string", "",    "ap-southeast-3a", "Required when WAF is enabled. Availability zone for the WAF engine ECS."),
                KV("waf_vpc",                "string", "",    "vpc-dmz",  "Required when WAF is enabled. HubVPCs name from 05_Network for the DMZ VPC."),
                KV("waf_subnet",             "string", "",    "dmz-elb",  "Required when WAF is enabled. HubSubnets name from 05_Network within the selected VPC."),
                KV("waf_policy_name",        "string", "lz-waf-policy", "lz-waf-policy", "Shared WAF protection policy attached to all configured domains."),
            ],
        ),
        Table(
            name="WAFDomains",
            kind="object-table",
            description=(
                "Domains protected by the dedicated WAF. Origin is usually the private VIP of "
                "the hub ingress ELB or another backend reachable from the WAF VPC. "
                "CertificateId is required when ClientProtocol is HTTPS."
            ),
            columns=[
                ("Domain",         "string", "Protected domain, e.g. app.example.com (or *.example.com)"),
                ("ClientProtocol", "string", "Browser -> WAF: HTTP | HTTPS (default HTTP)"),
                ("ServerProtocol", "string", "WAF -> origin: HTTP | HTTPS (default HTTP)"),
                ("OriginAddress",  "string", "Origin server IP/hostname (e.g. the ingress ELB VIP)"),
                ("OriginPort",     "int",    "Origin port (default 80)"),
                ("CertificateId",  "string", "WAF certificate ID (HTTPS only; blank for HTTP)"),
            ],
            sample_rows=[
                {"Enabled": False, "Domain": "app.example.com", "ClientProtocol": "HTTP", "ServerProtocol": "HTTP", "OriginAddress": "10.0.2.10", "OriginPort": 80, "CertificateId": ""},
            ],
        ),
    ],
)


M6_AUDIT = Sheet(
    name="06_Observability",
    description="Environment 06-observability (modules 6 and 7): CTS, OBS, KMS, and LTS for audit, plus SMN and Cloud Eye for operations.",
    tables=[
        Table(
            name="AuditSettings",
            kind="scalar",
            rows=[
                KV("cts_admin_account",       "string", "", "lz-security", "Required. Delegated administrator account from 01_Foundation where the central audit resources are deployed, including the organization CTS tracker, audit bucket, KMS key, and CTS log group and stream."),
                KV("audit_retention_days",       "int", 365,  365,   "Retention period for objects in the CTS audit bucket."),
                KV("audit_cold_after_days",      "int", 0,    90,    "Number of days before CTS audit objects move to the COLD storage class. Use 0 to disable transition."),
                KV("lts_hot_retention_days",     "int", 90,   90,    "Hot retention period for the CTS LTS log stream."),
                KV("audit_bucket_name",       "string", "", "{account-name}-sg-prd-ldz-audit-01", "Required. Globally unique CTS audit OBS bucket name. Supports the {account-name} token."),
                KV("kms_audit_alias",         "string", "", "{account-name}-sg-prd-ldz-audit-key", "Required. KMS alias for the audit bucket key. Supports {account-name}."),
                KV("cts_log_group_name",      "string", "", "{account-name}-sg-prd-ldz-cts-lg",   "CTS LTS log group name. Supports {account-name}."),
                KV("cts_log_stream_name",     "string", "", "{account-name}-sg-prd-ldz-cts-ls",   "CTS LTS log stream name. Supports {account-name}."),
                KV("kms_pending_days",           "int", 7,    30,    "KMS pending-deletion window. Production environments should use 30 days."),
                KV("audit_bucket_force_destroy","bool", False, False, "Use with caution. TRUE allows Terraform to delete a non-empty audit bucket when the bucket name changes. This deletes stored audit logs and should remain FALSE unless a deliberate recreation is required."),
                KV("cts_no_transfer_accounts","string", "", "lz-app,lz-infra", "Comma-separated account names from 01_Foundation that receive a CTS tracker without OBS or LTS transfer. Use this only when local CTS visibility is required in addition to the central organization tracker. Exclude cts_admin_account. Leave blank when no account needs this."),
            ],
        ),
        Table(
            name="LogAggregation",
            kind="scalar",
            description=(
                "Organization-wide LTS log aggregation. Member-account log streams converge "
                "into the delegated LTS administrator account, then transfer to an archive OBS"
                " bucket on a schedule. Hot retention is controlled by "
                "converged_retention_days and archive retention by archive_retention_days."
            ),
            rows=[
                KV("enable_log_aggregation",   "bool",   True,  True,  "Enable the log aggregation stack, including convergence, target log groups, archive bucket, and scheduled transfers. The administrator account is derived from the delegated LTS administrator configured in 01_Foundation."),
                KV("archive_bucket_name",      "string", "",    "{account-name}-sg-prd-ldz-obs-logarchive-01", "Globally unique archive OBS bucket name for LTS transfers. Supports {account-name}. Leave blank to use the generated default."),
                KV("kms_archive_alias",        "string", "",    "{account-name}-sg-prd-ldz-logarchive-key", "KMS alias for the archive bucket key. Supports {account-name}. Leave blank to use the generated default."),
                KV("archive_retention_days",   "int",    365,   365,   "Archive bucket object retention period, in days."),
                KV("archive_cold_after_days",  "int",    0,     90,    "Number of days before archive objects move to the COLD storage class. Use 0 to disable transition."),
                KV("converged_retention_days", "int",    90,    90,    "Hot retention period, in days, for converged LTS groups and streams."),
                KV("transfer_period",          "int",    30,    30,    "OBS transfer interval. Valid values depend on transfer_period_unit."),
                KV("transfer_period_unit",     "string", "min", "min", "OBS transfer interval unit: min or hour."),
                KV("archive_bucket_force_destroy", "bool", False, False, "Use with caution. TRUE allows Terraform to delete a non-empty archive bucket when its name changes. This deletes archived logs."),
            ],
        ),
        Table(
            name="LogConverge",
            kind="object-table",
            description=(
                "NO INPUT NEEDED: leave EMPTY and every LZ-created stream is derived on build — the CTS "
                "stream (cts_admin_account), DNS query logs (08_DNS AccessLogs, dns_account), the CFW "
                "traffic/access/attack streams (hub_account) and one <vpc>-flowlog per VPC. Add rows only "
                "to CURATE (extra app-team streams, or to exclude a source) — a non-empty table is "
                "authoritative and fully replaces the derivation. Account is the SOURCE account name "
                "(from 01_Foundation); SourceGroup/SourceStream are LTS group/stream NAMES in that account "
                "(resolved to IDs via generated per-account lookups). TargetGroup blank = "
                "agg-<account>-<sourcegroup>. Rows whose Account IS the LTS admin transfer straight to the "
                "archive bucket (no converge)."
            ),
            columns=[
                ("Account",      "string", "SOURCE account name (from 01_Foundation) owning the log group"),
                ("SourceGroup",  "string", "LTS log group NAME in that account"),
                ("SourceStream", "string", "LTS log stream NAME within SourceGroup"),
                ("TargetGroup",  "string", "Converged group name in the admin account. Blank = agg-<account>-<sourcegroup>."),
                ("Description",  "string", "What the stream carries"),
            ],
            sample_rows=[
                {"Enabled": False, "Account": "lz-security", "SourceGroup": "lz-cts",     "SourceStream": "lz-cts",      "TargetGroup": "", "Description": "Org CTS event stream"},
                {"Enabled": False, "Account": "lz-infra",    "SourceGroup": "lz-hub-cfw", "SourceStream": "cfw-traffic", "TargetGroup": "", "Description": "CFW traffic/flow logs"},
                {"Enabled": False, "Account": "lz-infra",    "SourceGroup": "lz-hub-cfw", "SourceStream": "cfw-attack",  "TargetGroup": "", "Description": "CFW attack logs"},
            ],
        ),
    ],
)


M7_OPS = Sheet(
    name="07_OpsMonitoring_MERGED_INTO_05",  # not rendered; tables merged into 06_Observability below
    description="Merged into 06_Observability.",
    tables=[
        Table(
            name="OpsSettings",
            kind="scalar",
            rows=[
                KV("accounts",                "string", "", "all", "Required. Comma-separated accounts from 01_Foundation that receive operational monitoring resources, or 'all'. Each account receives its own SMN topic, subscriptions, and one-click alarms."),
                KV("topic_name",              "string", "{account-name}-lz-alerts", "{account-name}-lz-alerts", "SMN topic name. Supports {account-name}."),
            ],
        ),
        Table(
            name="Subscribers",
            kind="object-table",
            description="SMN subscribers. Email subscribers must confirm the subscription outside Terraform.",
            columns=[
                ("Protocol", "string", "email | sms | http | https | functionstage | callnotify | dms"),
                ("Endpoint", "string", "Address (email / phone / URL)"),
            ],
            sample_rows=[
                {"Enabled": True, "Protocol": "email", "Endpoint": "lz-oncall@example.com"},
            ],
        ),
        Table(
            name="OneClickNamespaces",
            kind="object-table",
            description="Cloud Eye one-click monitoring bundles. Toggle Enabled for each service. Enabled bundles notify the configured SMN topic and apply to existing and future resources for that service. EventEnabled controls event alarm rules.",
            columns=[
                ("Namespace",    "string", "Cloud Eye namespace (SYS.*)."),
                ("EventEnabled", "bool",   "Include event alarms for this bundle."),
                ("Description",  "string", "Service the namespace covers."),
            ],
            # Catalog = the live huaweicloud_ces_one_click_alarms data source for the
            # tenant/region (ap-southeast-3). All disabled by default; set Enabled=TRUE
            # to deploy. one_click_alarm_id is auto-resolved from Namespace.
            sample_rows=[
                {"Enabled": False, "Namespace": "SYS.APIC",                "EventEnabled": True, "Description": "API Connect"},
                {"Enabled": False, "Namespace": "SYS.APIG",                "EventEnabled": True, "Description": "API Gateway"},
                {"Enabled": False, "Namespace": "SYS.AS",                  "EventEnabled": True, "Description": "Auto Scaling"},
                {"Enabled": False, "Namespace": "SYS.BMS",                 "EventEnabled": True, "Description": "Bare Metal Server"},
                {"Enabled": False, "Namespace": "SYS.CBH",                 "EventEnabled": True, "Description": "Cloud Bastion Host"},
                {"Enabled": False, "Namespace": "SYS.CBR",                 "EventEnabled": True, "Description": "Cloud Backup and Recovery"},
                {"Enabled": False, "Namespace": "SYS.CC",                  "EventEnabled": True, "Description": "Cloud Connect"},
                {"Enabled": False, "Namespace": "SYS.CDM",                 "EventEnabled": True, "Description": "Cloud Data Migration"},
                {"Enabled": False, "Namespace": "SYS.CDN",                 "EventEnabled": True, "Description": "Content Delivery Network"},
                {"Enabled": False, "Namespace": "SYS.CFW",                 "EventEnabled": True, "Description": "Cloud Firewall"},
                {"Enabled": False, "Namespace": "SYS.CloudTable",          "EventEnabled": True, "Description": "CloudTable Service"},
                {"Enabled": False, "Namespace": "SYS.CPH",                 "EventEnabled": True, "Description": "Cloud Phone"},
                {"Enabled": False, "Namespace": "SYS.CSG",                 "EventEnabled": True, "Description": "Cloud Storage Gateway"},
                {"Enabled": False, "Namespace": "SYS.DATAARTS_MIGRATION",  "EventEnabled": True, "Description": "DataArts Studio (migration)"},
                {"Enabled": False, "Namespace": "SYS.DAYU",                "EventEnabled": True, "Description": "DataArts / Data Ingestion"},
                {"Enabled": False, "Namespace": "SYS.DBPROXY",             "EventEnabled": True, "Description": "Database Proxy"},
                {"Enabled": False, "Namespace": "SYS.DBSS",                "EventEnabled": True, "Description": "Database Security Service"},
                {"Enabled": False, "Namespace": "SYS.DCAAS",               "EventEnabled": True, "Description": "Direct Connect"},
                {"Enabled": False, "Namespace": "SYS.DCS",                 "EventEnabled": True, "Description": "Distributed Cache Service"},
                {"Enabled": False, "Namespace": "SYS.DDM",                 "EventEnabled": True, "Description": "Distributed Database Middleware"},
                {"Enabled": False, "Namespace": "SYS.DDMS",                "EventEnabled": True, "Description": "DDM Service"},
                {"Enabled": False, "Namespace": "SYS.DDS",                 "EventEnabled": True, "Description": "Document Database Service"},
                {"Enabled": False, "Namespace": "SYS.DLI",                 "EventEnabled": True, "Description": "Data Lake Insight"},
                {"Enabled": False, "Namespace": "SYS.DMS",                 "EventEnabled": True, "Description": "Distributed Message Service"},
                {"Enabled": False, "Namespace": "SYS.DRS",                 "EventEnabled": True, "Description": "Data Replication Service"},
                {"Enabled": False, "Namespace": "SYS.DWS",                 "EventEnabled": True, "Description": "Data Warehouse Service"},
                {"Enabled": False, "Namespace": "SYS.ECS",                 "EventEnabled": True, "Description": "Elastic Cloud Server"},
                {"Enabled": False, "Namespace": "SYS.EFS",                 "EventEnabled": True, "Description": "Elastic File Service"},
                {"Enabled": False, "Namespace": "SYS.EIP",                 "EventEnabled": True, "Description": "Elastic IP / bandwidth"},
                {"Enabled": False, "Namespace": "SYS.ELB",                 "EventEnabled": True, "Description": "Elastic Load Balance"},
                {"Enabled": False, "Namespace": "SYS.ER",                  "EventEnabled": True, "Description": "Enterprise Router"},
                {"Enabled": False, "Namespace": "SYS.ES",                  "EventEnabled": True, "Description": "Elasticsearch / CSS"},
                {"Enabled": False, "Namespace": "SYS.EVS",                 "EventEnabled": True, "Description": "Elastic Volume Service"},
                {"Enabled": False, "Namespace": "SYS.FRS",                 "EventEnabled": True, "Description": "Face Recognition Service"},
                {"Enabled": False, "Namespace": "SYS.GAUSSDB",             "EventEnabled": True, "Description": "GaussDB(for MySQL) / TaurusDB"},
                {"Enabled": False, "Namespace": "SYS.GAUSSDBV5",           "EventEnabled": True, "Description": "GaussDB"},
                {"Enabled": False, "Namespace": "SYS.GES",                 "EventEnabled": True, "Description": "Graph Engine Service"},
                {"Enabled": False, "Namespace": "SYS.IRS",                 "EventEnabled": True, "Description": "Image Recognition Service"},
                {"Enabled": False, "Namespace": "SYS.IVS",                 "EventEnabled": True, "Description": "Intelligent Video Service"},
                {"Enabled": False, "Namespace": "SYS.ModelArts",           "EventEnabled": True, "Description": "ModelArts"},
                {"Enabled": False, "Namespace": "SYS.MODERATION",          "EventEnabled": True, "Description": "Content Moderation"},
                {"Enabled": False, "Namespace": "SYS.NAT",                 "EventEnabled": True, "Description": "NAT Gateway"},
                {"Enabled": False, "Namespace": "SYS.NLP",                 "EventEnabled": True, "Description": "Natural Language Processing"},
                {"Enabled": False, "Namespace": "SYS.NoSQL",               "EventEnabled": True, "Description": "GeminiDB (NoSQL)"},
                {"Enabled": False, "Namespace": "SYS.OBS",                 "EventEnabled": True, "Description": "Object Storage Service"},
                {"Enabled": False, "Namespace": "SYS.OCR",                 "EventEnabled": True, "Description": "Optical Character Recognition"},
                {"Enabled": False, "Namespace": "SYS.RDS",                 "EventEnabled": True, "Description": "Relational Database Service"},
                {"Enabled": False, "Namespace": "SYS.ROMA",                "EventEnabled": True, "Description": "ROMA Connect"},
                {"Enabled": False, "Namespace": "SYS.SFS",                 "EventEnabled": True, "Description": "Scalable File Service"},
                {"Enabled": False, "Namespace": "SYS.SIS",                 "EventEnabled": True, "Description": "Speech Interaction Service"},
                {"Enabled": False, "Namespace": "SYS.UPredict",            "EventEnabled": True, "Description": "Prediction Service"},
                {"Enabled": False, "Namespace": "SYS.VPC",                 "EventEnabled": True, "Description": "Virtual Private Cloud"},
                {"Enabled": False, "Namespace": "SYS.VPN",                 "EventEnabled": True, "Description": "Virtual Private Network"},
                {"Enabled": False, "Namespace": "SYS.WAF",                 "EventEnabled": True, "Description": "Web Application Firewall"},
                {"Enabled": False, "Namespace": "SYS.Workspace",           "EventEnabled": True, "Description": "Workspace"},
            ],
        ),
    ],
)


M8_FINANCIAL = Sheet(
    name="02_Finance",
    description="Environment 02-finance (module 8): cost-center enterprise projects.",
    tables=[
        Table(
            name="Settings",
            kind="scalar",
            rows=[
                KV("enable_multi_ep",            "bool", True,  True,  "Create cost-center enterprise projects for 02-finance."),
            ],
        ),
        Table(
            name="CostCenters",
            kind="object-table",
            description=(
                "Cost-center enterprise projects in addition to the bootstrap enterprise "
                "project from module 1. Accounts lists where each project is created. Use "
                "comma-separated account names from 01_Foundation, 'master' for the management"
                " account, or 'all' for the management account and every 01_Foundation "
                "account. Leave blank for the management account only."
            ),
            columns=[
                ("Name",                  "string",   "EP name (map key within each account)"),
                ("Description",           "string",   "Purpose"),
                ("EnterpriseProjectType", "string",   "prod | dev | uat"),
                ("Accounts",              "csv-list", "Target accounts: names, 'master', or 'all'. Blank = master."),
            ],
            sample_rows=[
                {"Enabled": True, "Name": "finance",     "Description": "Finance BU",     "EnterpriseProjectType": "prod", "Accounts": "master"},
                {"Enabled": True, "Name": "engineering", "Description": "Engineering BU", "EnterpriseProjectType": "prod", "Accounts": "lz-app-prod,lz-app-nonprod"},
            ],
        ),
    ],
)


# 06_Observability is one env (06-observability) running modules 6 + 7, so the
# ops tables are merged into the audit sheet.
M6_AUDIT.tables = M6_AUDIT.tables + M7_OPS.tables

# Workbook format version. Bump when the sheet/table/column contract changes;
# the parser accepts a missing _meta sheet as "1.0" (pre-versioning workbooks).
SCHEMA_VERSION = "2.2"

META = Sheet(
    name="_meta",
    description="Workbook metadata. Do not edit schema_version because the parser and "
                "migration tooling use it to identify the template format.",
    tables=[
        Table(
            name="Meta",
            kind="scalar",
            description="Generated by the template tooling. The customer_name field may be updated.",
            rows=[
                KV("schema_version", "string", SCHEMA_VERSION, SCHEMA_VERSION,
                   "Template format version set by the generator. Do not edit."),
                KV("customer_name", "string", "", "example-corp",
                   "Short customer identifier used in generated documentation and release metadata."),
            ],
        ),
    ],
)

EP_SCOPING = Sheet(
    name="EP_Scoping",
    description=(
        "Reference only. This sheet explains how to scope an Identity Center permission set to"
        " enterprise projects and lists IAM v5 actions that support the g:EnterpriseProjectId "
        "condition. No input is required."
    ),
    tables=[
        Table(
            name="HowTo",
            kind="object-table",
            mandatory=True,
            description=(
                "Recommended pattern for an enterprise-project-scoped permission-set custom "
                "policy, based on Huawei IAM v5 condition behavior and tenant validation."
            ),
            columns=[
                ("Topic",    "string", "What the rule covers"),
                ("Guidance", "string", "The rule"),
            ],
            sample_rows=[
                {"Topic": "Pattern",
                 "Guidance": "Use two statements. First, allow the service actions the "
                             "workload requires. Second, deny enterprise-project-aware actions"
                             " when g:EnterpriseProjectId does not match an approved project "
                             "ID. Requests for approved projects remain allowed, requests for "
                             "other projects are denied, and requests without an enterprise "
                             "project ID continue to the Allow statement."},
                {"Topic": "Why use Deny with NotEquals",
                 "Guidance": "Do not use Allow with StringEquals for this pattern. Many list "
                             "and console bootstrap calls do not include "
                             "enterprise_project_id, so a restrictive Allow condition can "
                             "block normal console use."},
                {"Topic": "Keep IfExists",
                 "Guidance": "Without IfExists, the Deny also matches requests where the "
                             "condition key is absent, which blocks "
                             "enterprise-project-independent actions."},
                {"Topic": "EP IDs, not names",
                 "Guidance": "Condition values must be enterprise project UUIDs, not names."},
                {"Topic": "Only supported actions can be scoped",
                 "Guidance": "The Deny statement only affects actions that receive "
                             "g:EnterpriseProjectId. Actions outside the glossary remain "
                             "governed by the broader Allow statement, so review "
                             "service-specific gaps before relying on project scoping."},
                {"Topic": "Keep top-level list actions available",
                 "Guidance": "The console may send enterprise_project_id=all_granted_eps when "
                             "browsing all enterprise projects. Avoid applying the Deny "
                             "condition to list actions unless that behavior has been tested."},
                {"Topic": "Policy mechanics",
                 "Guidance": "Use policy version 5.0 and canonical action names. Keep the "
                             "policy focused on services the workload actually needs so it "
                             "stays within policy size limits."},
                {"Topic": "Validator behavior",
                 "Guidance": "The console reports INVALID_ACTION errors with row and column "
                             "details and may stop after the first few issues. Service codes "
                             "can differ from product names, so validate action names against "
                             "the IAM documentation."},
                {"Topic": "Alias expansion",
                 "Guidance": "Legacy alias names map onto canonical actions in OTHER services, and wildcards "
                             "match alias names too: rds:*:* silently grants the GaussDB actions aliased to "
                             "rds names — close with an unconditional Deny on gaussdb:*:* if unused. In a Deny, "
                             "an action name that doubles as an alias denies everything it maps to "
                             "(vpc:securityGroups:get also denies vpc:securityGroups:list) — keep "
                             "all_granted_eps in the condition values so alias-dragged list actions still work "
                             "under 'All enterprise projects'. Heed the console's USING_ALIAS_IN_ACTION "
                             "warnings, but check direction: denying kps:SSHKeyPair:unbind would break ECS "
                             "keypair unbinding (same action, canonical name)."},
                {"Topic": "No partial-verb wildcards",
                 "Guidance": "Partial-verb wildcards such as eps:*:list* may pass validation "
                             "but not match at runtime. Use complete service wildcards or "
                             "exact action names."},
                {"Topic": "Test checklist",
                 "Guidance": "Test the full lifecycle inside the scoped project, confirm "
                             "access to another project is denied, verify list pages still "
                             "load, and confirm the member account receives policy updates "
                             "after changes."},
            ],
        ),
        Table(
            name="EPActionGlossary",
            kind="object-table",
            mandatory=True,
            description=(
                "Every IAM 5 action whose Condition Key column includes g:EnterpriseProjectId "
                "(Huawei service-authorization-iam5 reference + api-dns/Permission.html, "
                "snapshot 2026-08-01; source pages in lz_spec/ep_actions.py). Check any action "
                "you put in an EP-conditioned Deny against this list — actions absent here "
                "cannot be EP-scoped. Essential=TRUE marks the minimal policy subset: the "
                "per-main-resource entry gate (the detail read the console needs to open a "
                "resource). Denying the gate blocks console access to out-of-scope resources; "
                "direct-API mutations on known IDs are not covered by this tier."
            ),
            columns=[
                ("Service",   "string", "IAM 5 service code"),
                ("Action",    "string", "Canonical action name (not the Alias form)"),
                ("Essential", "bool",   "In the curated deny subset used by generated policies"),
            ],
            sample_rows=[
                {"Service": svc, "Action": a, "Essential": a in ESSENTIAL_ACTIONS}
                for svc, data in EP_ACTIONS.items()
                for a in data["actions"]
            ],
        ),
    ],
)


# Sheets in DISPLAY order (sequential sheet numbers; renumbered 2026-07-26 —
# Security moved after Observability). Sheet numbers are display-only: the
# sheet -> deploy-env mapping lives in lz_pipeline/core/cli._SHEET_ENV and the
# env dir numbers are historical (deployed state; never renumber those).
SHEETS = [
    INDEX,
    GLOBAL,             # all envs (+ 00-bootstrap)
    M1_ORG,             # 01_Foundation     -> 01-foundation
    M8_FINANCIAL,       # 02_Finance        -> 02-finance
    M2_IDENTITY,        # 03_Identity       -> 03-identity
    M4_PERIMETER,       # 04_Perimeter      -> 04-perimeter
    M3_NETWORK,         # 05_Network        -> 05-network (hub + spokes, one apply)
    M6_AUDIT,           # 06_Observability  -> 06-observability (modules 6 + 7 + 12)
    M5_SECURITY,        # 07_Security       -> 07-security
    M_DNS,              # 08_DNS            -> 08-network-dns (zones + hybrid resolver)
    M_CFW,              # 09_CFW            -> 09-network-cfw (firewall rule plane)
    M_VPN,              # 10_VPN            -> 10-network-vpn (S2C VPN; hub IDs via remote state)
    M_SGACL,            # 11_SGACL          -> 11-network-sgacl (workload SGs; ACL tables reserved)
    EP_SCOPING,         # EP_Scoping        -> reference only (no env)
    META,               # _meta             -> parser/migration metadata (no env)
]

# Informational sheets: generated content, never parsed as spec input.
# Parser/validators/app skip these; the template writer emits them as-is.
INFO_SHEETS = {"Index", "EP_Scoping"}


def get_meta(spec: dict) -> dict:
    """Workbook metadata with defaults for pre-versioning workbooks."""
    meta = dict(spec.get("_meta", {}).get("Meta") or {})
    meta.setdefault("schema_version", "1.0")
    if not meta.get("schema_version"):
        meta["schema_version"] = "1.0"
    return meta
