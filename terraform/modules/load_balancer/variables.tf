variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "model_id" {
  type = string
}

variable "instance_group" {
  description = "Self link of the managed instance group"
  type        = string
}

variable "health_check" {
  description = "Self link of the health check"
  type        = string
}
