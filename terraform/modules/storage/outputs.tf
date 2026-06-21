output "base_models_bucket_name" {
  value = google_storage_bucket.base_models.name
}

output "quantized_models_bucket_name" {
  value = google_storage_bucket.quantized_models.name
}

output "evaluation_results_bucket_name" {
  value = google_storage_bucket.evaluation_results.name
}

output "model_registry_bucket_name" {
  value = google_storage_bucket.model_registry.name
}
