variable "home_region" {
  type    = string
  default = "cn-east-3"
}

variable "master_access_key" {
  type      = string
  sensitive = true
}

variable "master_secret_key" {
  type      = string
  sensitive = true
}

variable "ops_monitoring_account_domain" {
  type = string
}

variable "tfstate_bucket" {
  type = string
}

variable "alert_email_endpoints" {
  type    = list(string)
  default = []
}

variable "alert_webhook_endpoints" {
  type = list(object({
    url      = string
    protocol = string
  }))
  default = []
}
