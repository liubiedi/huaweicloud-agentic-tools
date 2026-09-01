# 08-financial

Financial management. Three parts, each behind an enable flag:

- enable_multi_ep (master account): creates the cost-center enterprise
  projects.
- enable_predefined_tags (per account): loads the standard tag dictionary
  into TMS so the tags show up as suggestions in the console.
- enable_bulk_tag_resources (per account, optional): applies tags to
  resources that already exist.

## Cost centers

var.cost_centers is a map keyed by enterprise project name (for example
finance, engineering). Each entry has a description and an optional project
type (default prod).
