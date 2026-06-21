resource "google_storage_bucket" "base_models" {
    name          = "${var.project_id}-base-models-${var.environment}"
    project       = var.project_id
    location      = var.region
    force_destroy = false

    versioning {
        enabled = true
    }

    uniform_bucket_level_access = true
}

resource "google_storage_bucket" "quantized_models" {
  name          = "${var.project_id}-quantized-models-${var.environment}"
  project       = var.project_id
  location      = var.region
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "evaluation_results" {
  name          = "${var.project_id}-evaluation-results-${var.environment}"
  project       = var.project_id
  location      = var.region
  force_destroy = false

  versioning {
    enabled = false
  }

  uniform_bucket_level_access = true

  # Evaluation results accumulate over time.
  # Move results older than 365 days to cheaper storage.
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 365
    }
  }
}

resource "google_storage_bucket" "model_registry" {
  name          = "${var.project_id}-model-registry-${var.environment}"
  project       = var.project_id
  location      = var.region
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
}
