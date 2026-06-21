output "prometheus_internal_ip" {
  value = google_compute_instance.prometheus.network_interface[0].network_ip
}
