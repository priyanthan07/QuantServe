variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "csr_repo_name" {
  description = "Cloud Source Repository name connected to this project"
  type        = string
}

variable "base_models_bucket" {
  type = string
}

variable "quant_models_bucket" {
  type = string
}

variable "eval_results_bucket" {
  type = string
}

variable "model_registry_bucket" {
  type = string
}

variable "pipeline_sa_email" {
  type = string
}

variable "apis_enabled" {
  type    = any
  default = null
}
