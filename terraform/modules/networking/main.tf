resource "google_compute_network" "main" {
  name                    = "quantserve-${var.environment}"
  project                 = var.project_id
  auto_create_subnetworks = false
}

# ---------- Subnets ----------

resource "google_compute_subnetwork" "pipeline" {
    name = "quantserve-pipeline-${var.environment}"
    project = var.project_id
    region = var.region
    network = google_compute_network.main.id
    ip_cidr_range = "10.0.1.0/24"
}

resource "google_compute_subnetwork" "serving" {
  name          = "quantserve-serving-${var.environment}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = "10.0.2.0/24"
}

resource "google_compute_subnetwork" "observability" {
  name          = "quantserve-observability-${var.environment}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = "10.0.3.0/24"
}

# ---------- Cloud NAT (outbound internet without public IPs) ----------

resource "google_compute_router" "main" {
  name    = "quantserve-router-${var.environment}"
  project = var.project_id
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "quantserve-nat-${var.environment}"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.main.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------- Firewall ----------

# Allow IAP SSH access (no open SSH ports)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "quantserve-allow-iap-ssh-${var.environment}"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range
  source_ranges = ["35.235.240.0/20"]
}

# Allow health checks from GCP load balancer
resource "google_compute_firewall" "allow_health_checks" {
  name    = "quantserve-allow-health-checks-${var.environment}"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  # GCP health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["vllm-serving"]
}

# Allow Prometheus to scrape vLLM metrics within the VPC
resource "google_compute_firewall" "allow_prometheus_scrape" {
  name    = "quantserve-allow-prometheus-scrape-${var.environment}"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  source_tags = ["prometheus"]
  target_tags = ["vllm-serving"]
}

# Allow internal communication for LMCache between replicas
resource "google_compute_firewall" "allow_lmcache" {
  name    = "quantserve-allow-lmcache-${var.environment}"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["7000"]
  }

  source_tags = ["vllm-serving"]
  target_tags = ["vllm-serving"]
}

# Allow Grafana access from IAP
resource "google_compute_firewall" "allow_iap_grafana" {
  name    = "quantserve-allow-iap-grafana-${var.environment}"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["prometheus"]
}

# Allow GCP load balancer health check probes to reach Grafana
resource "google_compute_firewall" "allow_lb_grafana" {
  name    = "quantserve-allow-lb-grafana-${var.environment}"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  # Same IP ranges used for vLLM health checks — these are GCP's global LB ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["prometheus"]
}
