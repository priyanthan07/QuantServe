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

output "api_ip" {
  description = "Single external IP for all endpoints"
  value       = module.load_balancer.external_ip
}

output "model_urls" {
  description = "Endpoint URL for each model"
  value = {
    for model_id, _ in var.models :
    model_id => "https://${var.domain_suffix}/${model_id}/v1"
  }
}

output "grafana_url" {
  value = "https://${var.domain_suffix}/grafana"
}

output "prometheus_internal_ip" {
  description = "Internal IP of the Prometheus/Grafana VM"
  value       = module.observability.prometheus_internal_ip
}

output "dns_nameservers" {
  description = "Nameservers for this zone (already set by Cloud Domains)"
  value       = module.dns.nameservers
}
