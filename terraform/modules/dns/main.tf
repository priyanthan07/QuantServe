# Reference the existing Cloud DNS zone created by Cloud Domains.
# Do NOT create a new zone — Cloud Domains already created one.
data "google_dns_managed_zone" "main" {
  name    = var.dns_zone_name
  project = var.project_id
}

# Root domain A record → shared LB IP
resource "google_dns_record_set" "api" {
  name         = "${var.domain_suffix}."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.main.name
  project      = var.project_id
  rrdatas      = [var.api_lb_ip]
}
