output "external_ip" {
  description = "Single external IP for all endpoints"
  value       = google_compute_global_address.api.address
}
