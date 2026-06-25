# ---------- Startup Script ----------
# Rendered from serving/startup.sh template.
# Copies model from GCS, fetches API key from Secret Manager, starts vLLM.

locals {
  startup_script = templatefile("${path.module}/../../serving/startup.sh", {
    quantized_models_bucket = var.quantized_models_bucket
    model_registry_bucket   = var.model_registry_bucket
    model_id                = var.model_id
    vllm_args               = var.vllm_args
    project_id              = var.project_id
    serving_image_url       = var.serving_image_url
  })
}

# ---------- Instance Template ----------

resource "google_compute_instance_template" "serving" {
  name_prefix  = "quantserve-${var.model_id}-${var.environment}-"
  project      = var.project_id
  machine_type = var.machine_type
  region       = var.region

  tags = ["vllm-serving"]

  disk {
    source_image = "projects/ml-images/global/images/family/common-cu124-debian-12-py311"
    auto_delete  = true
    boot         = true
    disk_type    = "pd-ssd"
    disk_size_gb = var.disk_size_gb
  }

  network_interface {
    subnetwork = var.subnet_self_link
    # No external IP — outbound via Cloud NAT
  }

  guest_accelerator {
    type  = var.gpu_type
    count = 1
  }

  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
    preemptible         = false
  }

  service_account {
    email  = var.serving_sa_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = local.startup_script
    model_id       = var.model_id
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------- Health Check ----------

resource "google_compute_health_check" "vllm" {
  name    = "quantserve-${var.model_id}-health-${var.environment}"
  project = var.project_id

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 8000
    request_path = "/health"
  }
}

# ---------- Managed Instance Group ----------

resource "google_compute_instance_group_manager" "serving" {
  name    = "quantserve-${var.model_id}-mig-${var.environment}"
  project = var.project_id
  zone    = var.zone

  base_instance_name = "quantserve-${var.model_id}"

  version {
    instance_template = google_compute_instance_template.serving.self_link
  }

  named_port {
    name = "vllm"
    port = 8000
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.vllm.id
    initial_delay_sec = 600 # 10 min grace period for model loading
  }
}

# ---------- Autoscaler ----------

resource "google_compute_autoscaler" "serving" {
  name    = "quantserve-${var.model_id}-autoscaler-${var.environment}"
  project = var.project_id
  zone    = var.zone
  target  = google_compute_instance_group_manager.serving.id

  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = 300

    # Scale on CPU as a baseline signal.
    # For more precise LLM-aware scaling (num_requests_waiting),
    # use Prometheus adapter with custom metrics once observability is up.
    cpu_utilization {
      target = 0.7
    }
  }
}
