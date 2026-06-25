variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_self_link" {
  type = string
}

variable "observability_sa_email" {
  type = string
}

variable "models" {
  type = map(any)
}

variable "vllm_instance_groups" {
  type = map(string)
}

variable "alert_notification_channel_email" {
  type    = string
  default = ""
}

variable "ttft_p99_slo_seconds" {
  type    = number
  default = 3.0
}

# ADD THIS:
variable "domain_suffix" {
  description = "Base domain suffix. Grafana will be at grafana.DOMAIN_SUFFIX"
  type        = string
}
