variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "default_model_id" {
  description = "Model ID to use as the default backend"
  type        = string
}

variable "model_backends" {
  description = "Map of model_id to its instance group and health check"
  type = map(object({
    instance_group = string
    health_check   = string
  }))
}

variable "domain_suffix" {
  description = "Base domain suffix for this model's SSL cert"
  type        = string
}

variable "grafana_backend" {
  description = "Instance group and health check for Grafana"
  type = object({
    instance_group = string
    health_check   = string
  })
}
