# ---------- Single global IP for all endpoints ----------

resource "google_compute_global_address" "api" {
  name    = "quantserve-api-ip-${var.environment}"
  project = var.project_id
}

# ---------- Single SSL cert for the root domain ----------

resource "google_compute_managed_ssl_certificate" "api" {
  name    = "quantserve-api-cert-${var.environment}"
  project = var.project_id

  managed {
    domains = ["${var.domain_suffix}"]
  }
}

# ---------- One backend service per model ----------

resource "google_compute_backend_service" "models" {
  for_each = var.model_backends

  name        = "quantserve-${each.key}-backend-${var.environment}"
  project     = var.project_id
  protocol    = "HTTP"
  port_name   = "vllm"
  timeout_sec = 300

  health_checks = [each.value.health_check]

  backend {
    group = each.value.instance_group
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ---------- Grafana backend service ----------

resource "google_compute_backend_service" "grafana" {
  name        = "quantserve-grafana-backend-${var.environment}"
  project     = var.project_id
  protocol    = "HTTP"
  port_name   = "grafana"
  timeout_sec = 30

  health_checks = [var.grafana_backend.health_check]

  backend {
    group = var.grafana_backend.instance_group
  }
}

# ---------- URL map — path-based routing ----------

resource "google_compute_url_map" "api" {
  name            = "quantserve-api-urlmap-${var.environment}"
  project         = var.project_id
  default_service = google_compute_backend_service.models[var.default_model_id].id

  host_rule {
    hosts        = ["${var.domain_suffix}"]
    path_matcher = "routes"
  }

  path_matcher {
    name            = "routes"
    default_service = google_compute_backend_service.models[var.default_model_id].id

    # Model path rules — strip the model prefix before forwarding to vLLM
    dynamic "path_rule" {
      for_each = var.model_backends
      content {
        paths   = ["/${path_rule.key}", "/${path_rule.key}/*"]
        service = google_compute_backend_service.models[path_rule.key].id

        route_action {
          url_rewrite {
            path_prefix_rewrite = "/"
          }
        }
      }
    }

    # Grafana — do NOT strip prefix. Grafana handles /grafana/* internally.
    path_rule {
      paths   = ["/grafana", "/grafana/*"]
      service = google_compute_backend_service.grafana.id
    }
  }
}

# ---------- HTTPS proxy ----------

resource "google_compute_target_https_proxy" "api" {
  name    = "quantserve-api-proxy-${var.environment}"
  project = var.project_id
  url_map = google_compute_url_map.api.id

  ssl_certificates = [google_compute_managed_ssl_certificate.api.id]
}

# ---------- Forwarding rule ----------

resource "google_compute_global_forwarding_rule" "api" {
  name        = "quantserve-api-fwd-${var.environment}"
  project     = var.project_id
  ip_address  = google_compute_global_address.api.address
  ip_protocol = "TCP"
  port_range  = "443"
  target      = google_compute_target_https_proxy.api.id
}
