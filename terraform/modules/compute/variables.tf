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

variable "model_id" {
  description = "Unique identifier for this model (e.g. qwen3-8b-w4a16)"
  type        = string
}

variable "gpu_type" {
  description = "GPU accelerator type (e.g. nvidia-l4)"
  type        = string
}

variable "machine_type" {
  description = "GCP machine type (e.g. g2-standard-4)"
  type        = string
}

variable "min_replicas" {
  type    = number
  default = 1
}

variable "max_replicas" {
  type    = number
  default = 3
}

variable "disk_size_gb" {
  type    = number
  default = 100
}

variable "vllm_args" {
  description = "Additional vLLM CLI arguments"
  type        = string
  default     = ""
}

variable "subnet_self_link" {
  type = string
}

variable "serving_sa_email" {
  type = string
}

variable "quantized_models_bucket" {
  type = string
}

variable "serving_image_url" {
  description = "Artifact Registry URL for the vLLM serving Docker image"
  type        = string
}

variable "model_registry_bucket" {
  description = "GCS bucket for the model registry (used to resolve the latest artifact path at boot)"
  type        = string
}
