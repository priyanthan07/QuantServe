output "prometheus_internal_ip" {
  value = google_compute_instance.prometheus.network_interface[0].network_ip
}

output "grafana_instance_group" {
  value = google_compute_instance_group.grafana.id
}

output "grafana_health_check" {
  value = google_compute_health_check.grafana.id
}
