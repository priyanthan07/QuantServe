# ---------- Service Accounts ----------

# Pipeline SA: used by Cloud Build and the quantization VM.
# Reads base models, writes quantized models and eval results, reads secrets.

resource "google_service_account" "pipeline" {
  account_id   = "quantserve-pipeline"
  display_name = "QuantServe Pipeline"
  project      = var.project_id
}

# Serving SA: used by vLLM serving VMs.
# Reads quantized models only.
resource "google_service_account" "serving" {
  account_id   = "quantserve-serving"
  display_name = "QuantServe Serving"
  project      = var.project_id
}

# Observability SA: used by Prometheus/Grafana VM.
# Reads compute metadata for service discovery.
resource "google_service_account" "observability" {
  account_id   = "quantserve-observability"
  display_name = "QuantServe Observability"
  project      = var.project_id
}

# ---------- Pipeline SA Bindings ----------

resource "google_storage_bucket_iam_member" "pipeline_read_base" {
  bucket = var.base_models_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_write_base" {
  bucket = var.base_models_bucket
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_write_quantized" {
  bucket = var.quant_models_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_write_eval" {
  bucket = var.eval_results_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_write_registry" {
  bucket = var.model_registry_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_project_iam_member" "pipeline_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_project_iam_member" "pipeline_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}

# ---------- Serving SA Bindings ----------

resource "google_storage_bucket_iam_member" "serving_read_quantized" {
  bucket = var.quant_models_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.serving.email}"
}

resource "google_project_iam_member" "serving_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.serving.email}"
}

resource "google_project_iam_member" "serving_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.serving.email}"
}

resource "google_project_iam_member" "serving_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.serving.email}"
}

# ---------- Observability SA Bindings ----------

resource "google_project_iam_member" "observability_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.observability.email}"
}

resource "google_project_iam_member" "observability_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.observability.email}"
}
