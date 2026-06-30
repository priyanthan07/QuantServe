variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for compute instances"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "csr_repo_name" {
  description = "Cloud Source Repository name. Create at: console.cloud.google.com/source/repos"
  type        = string
}

variable "domain_suffix" {
  description = "Root domain you own. e.g. dev-quantserve.com"
  type        = string
}

variable "dns_zone_name" {
  description = "Name of the existing Cloud DNS zone created by Cloud Domains"
  type        = string
}

variable "default_model_id" {
  description = "Model to use as the default backend for unmatched paths. Must be a key in the models map."
  type        = string
}

# ---------- Serving models ----------
# Each entry defines a model to be served.
# The key is used as the model identifier throughout the system.

variable "models" {
  description = "Map of models to serve. Key = model ID, value = config."
  type = map(object({
    gpu_type          = string # e.g. "nvidia-l4"
    machine_type      = string # e.g. "g2-standard-4"
    min_replicas      = number
    max_replicas      = number
    disk_size_gb      = number
    vllm_args         = string # extra vLLM CLI flags
  }))
  default = {}
}

# ---------- Observability ----------

variable "alert_notification_channel_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = ""
}

variable "ttft_p99_slo_seconds" {
  description = "TTFT p99 SLO threshold in seconds for alerting"
  type        = number
  default     = 3.0
}
