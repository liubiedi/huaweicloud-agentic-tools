variable "environment" {
  type        = string
  default     = "shared"
  description = "Logical environment label (unused by the tracker; kept for module-call consistency)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags (provider default_tags supply the rest)."
}
