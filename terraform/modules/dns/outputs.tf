output "nameservers" {
  description = "Nameservers for this zone (already set by Cloud Domains)"
  value       = data.google_dns_managed_zone.main.name_servers
}
