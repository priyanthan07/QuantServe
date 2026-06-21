output "external_ip" {
  value = google_compute_global_address.lb.address
}

output "forwarding_rule_self_link" {
  value = google_compute_global_forwarding_rule.lb.self_link
}
