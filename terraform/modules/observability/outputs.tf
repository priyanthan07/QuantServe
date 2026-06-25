output "prometheus_internal_ip" {
  value = google_compute_instance.prometheus.network_interface[0].network_ip
}

output "grafana_lb_ip" {
  description = "External IP of the Grafana load balancer"
  value       = google_compute_global_address.grafana.address
}

output "grafana_url" {
  description = "HTTPS URL for Grafana (reachable after DNS is pointed at grafana_lb_ip)"
  value       = "https://grafana.${var.domain_suffix}"
}
