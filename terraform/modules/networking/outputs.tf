output "network_self_link" {
  value = google_compute_network.main.self_link
}

output "pipeline_subnet_self_link" {
  value = google_compute_subnetwork.pipeline.self_link
}

output "serving_subnet_self_link" {
  value = google_compute_subnetwork.serving.self_link
}

output "observability_subnet_self_link" {
  value = google_compute_subnetwork.observability.self_link
}
