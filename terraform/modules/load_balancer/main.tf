# ---------- External IP ----------

resource "google_compute_global_address" "lb" {
  name    = "quantserve-${var.model_id}-ip-${var.environment}"
  project = var.project_id
}

# ---------- Backend Service ----------

resource "google_compute_backend_service" "vllm" {
  name        = "quantserve-${var.model_id}-backend-${var.environment}"
  project     = var.project_id
  protocol    = "HTTP"
  port_name   = "vllm"
  timeout_sec = 300 # LLM requests can be long-running

  health_checks = [var.health_check]

  backend {
    group = var.instance_group
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ---------- URL Map ----------

resource "google_compute_url_map" "lb" {
  name            = "quantserve-${var.model_id}-urlmap-${var.environment}"
  project         = var.project_id
  default_service = google_compute_backend_service.vllm.id
}

# ---------- HTTPS Proxy ----------
# Uses Google-managed SSL certificate.

resource "google_compute_managed_ssl_certificate" "lb" {
  name    = "quantserve-${var.model_id}-cert-${var.environment}"
  project = var.project_id

  managed {
    # Replace with your actual domain when ready.
    # Until then, access via IP with HTTP target proxy instead.
    domains = ["${var.model_id}.${var.domain_suffix}"]
  }
}

resource "google_compute_target_https_proxy" "lb" {
  name    = "quantserve-${var.model_id}-proxy-${var.environment}"
  project = var.project_id
  url_map = google_compute_url_map.lb.id

  ssl_certificates = [google_compute_managed_ssl_certificate.lb.id]
}

# ---------- Forwarding Rule ----------

resource "google_compute_global_forwarding_rule" "lb" {
  name        = "quantserve-${var.model_id}-fwd-${var.environment}"
  project     = var.project_id
  ip_address  = google_compute_global_address.lb.address
  ip_protocol = "TCP"
  port_range  = "443"
  target      = google_compute_target_https_proxy.lb.id
}
