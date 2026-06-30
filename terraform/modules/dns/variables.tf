variable "project_id" {
  type = string
}

variable "dns_zone_name" {
  description = "Name of the existing Cloud DNS zone created by Cloud Domains"
  type        = string
}

variable "domain_suffix" {
  type = string
}

variable "api_lb_ip" {
  description = "Single IP for all model endpoints and Grafana"
  type        = string
}
