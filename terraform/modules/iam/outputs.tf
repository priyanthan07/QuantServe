output "pipeline_sa_email" {
  value = google_service_account.pipeline.email
}

output "serving_sa_email" {
  value = google_service_account.serving.email
}

output "observability_sa_email" {
  value = google_service_account.observability.email
}
