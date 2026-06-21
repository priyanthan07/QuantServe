# ---------- Prometheus + Grafana VM ----------

resource "google_compute_instance" "prometheus" {
  name         = "quantserve-prometheus-${var.environment}"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-standard-2"

  tags = ["prometheus"]

  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/images/family/cos-stable"
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
    # No external IP
  }

  service_account {
    email  = var.observability_sa_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = <<-SCRIPT
      #!/bin/bash
      set -e

      # Container-Optimized OS has Docker pre-installed
      # Create data directories
      mkdir -p /home/prometheus/config /home/prometheus/data /home/grafana/data

      # Write Prometheus config
      cat > /home/prometheus/config/prometheus.yml << 'PROMEOF'
      global:
        scrape_interval: 15s
        evaluation_interval: 15s

      scrape_configs:
        - job_name: 'vllm'
          gce_sd_configs:
            - project: ${var.project_id}
              zone: ${var.zone}
              port: 8000
              filter: '(tags.items = "vllm-serving")'
          relabel_configs:
            - source_labels: [__meta_gce_instance_name]
              target_label: instance_name
            - source_labels: [__meta_gce_metadata_model_id]
              target_label: model_id
      PROMEOF

      # Start Prometheus
      docker run -d \
        --name prometheus \
        --restart always \
        -p 9090:9090 \
        -v /home/prometheus/config:/etc/prometheus \
        -v /home/prometheus/data:/prometheus \
        prom/prometheus:latest \
        --config.file=/etc/prometheus/prometheus.yml \
        --storage.tsdb.retention.time=30d

      # Start Grafana
      docker run -d \
        --name grafana \
        --restart always \
        -p 3000:3000 \
        -v /home/grafana/data:/var/lib/grafana \
        -e "GF_SECURITY_ADMIN_PASSWORD=changeme" \
        grafana/grafana:latest
    SCRIPT
  }
}

# ---------- Alert Policies ----------

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_notification_channel_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "QuantServe Alerts"
  type         = "email"

  labels = {
    email_address = var.alert_notification_channel_email
  }
}

# Alert: high GPU cache usage (OOM risk)
resource "google_monitoring_alert_policy" "gpu_cache_high" {
  project      = var.project_id
  display_name = "QuantServe: GPU Cache Usage > 90%"
  combiner     = "OR"

  conditions {
    display_name = "GPU cache usage exceeds 90%"
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/vllm/gpu_cache_usage_perc\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.9
      duration        = "120s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.alert_notification_channel_email != "" ? [
    google_monitoring_notification_channel.email[0].name
  ] : []
}
