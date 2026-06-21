output "base_models_bucket" {
  description = "GCS bucket for base model downloads"
  value       = module.storage.base_models_bucket_name
}

output "quantized_models_bucket" {
  description = "GCS bucket for quantized model artifacts"
  value       = module.storage.quantized_models_bucket_name
}

output "evaluation_results_bucket" {
  description = "GCS bucket for evaluation and benchmark results"
  value       = module.storage.evaluation_results_bucket_name
}

output "model_registry_bucket" {
  description = "GCS bucket for model registry metadata"
  value       = module.storage.model_registry_bucket_name
}

output "load_balancer_ips" {
  description = "Map of model ID to load balancer IP address"
  value = {
    for model_id, _ in var.models :
    model_id => module.load_balancer[model_id].external_ip
  }
}

output "prometheus_internal_ip" {
  description = "Internal IP of the Prometheus/Grafana VM"
  value       = module.observability.prometheus_internal_ip
}
