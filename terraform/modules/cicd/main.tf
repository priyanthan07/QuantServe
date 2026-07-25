# ---------- Artifact Registry ----------
# Stores the pipeline Docker image used by Cloud Build steps.

resource "google_artifact_registry_repository" "pipeline" {
  location      = var.region
  repository_id = "quantserve"
  description   = "QuantServe pipeline Docker images"
  format        = "DOCKER"
  project       = var.project_id
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_cloudbuildv2_repository" "quantserve" {
  project           = var.project_id
  location          = var.region
  name              = "quantserve"
  parent_connection = "projects/${var.project_id}/locations/${var.region}/connections/quantserve-repo"
  remote_uri        = "https://github.com/priyanthan07/QuantServe.git"
}

# ---------- Cloud Build Trigger: Build pipeline Docker image ----------
# Fires when Dockerfile.pipeline or any pipeline script changes.
# Builds and pushes the image to Artifact Registry.

resource "google_cloudbuild_trigger" "build_pipeline_image" {
  name        = "quantserve-build-pipeline-image"
  description = "Builds the QuantServe pipeline Docker image"
  project     = var.project_id
  location    = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  repository_event_config {
    repository = google_cloudbuildv2_repository.quantserve.id
    push {
      branch = "^main$"
    }
  }

  included_files = [
    "pipeline/Dockerfile.pipeline",
    "pipeline/scripts/**",
  ]

  build {
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/pipeline:$COMMIT_SHA",
        "-t", "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/pipeline:latest",
        "-f", "pipeline/Dockerfile.pipeline",
        ".",
      ]
    }

    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "--all-tags",
        "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/pipeline",
      ]
    }
  }
}

# ---------- Cloud Build Trigger: Model onboarding pipeline ----------
# Fires when a model config YAML is added or changed.
# Provisions a GPU Spot VM, waits for GPU steps, then updates registry.

resource "google_cloudbuild_trigger" "model_onboarding" {
  name        = "quantserve-model-onboarding"
  description = "Runs the full model onboarding pipeline when a model config changes"
  project     = var.project_id
  location    = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  repository_event_config {
    repository = google_cloudbuildv2_repository.quantserve.id
    push {
      branch = "^main$"
    }
  }

  included_files = ["model-configs/**"]

  filename = "pipeline/cloudbuild.yaml"

  substitutions = {
    _REGION             = var.region
    _ZONE               = var.zone
    _ENVIRONMENT   = var.environment
    _BASE_BUCKET        = var.base_models_bucket
    _QUANT_BUCKET       = var.quant_models_bucket
    _EVAL_BUCKET        = var.eval_results_bucket
    _REG_BUCKET         = var.model_registry_bucket
    _PIPELINE_SA        = var.pipeline_sa_email
    _ARTIFACT_REPO      = "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/pipeline"
  }
}

resource "google_cloudbuild_trigger" "build_serving_image" {
  name        = "quantserve-build-serving-image"
  description = "Builds the QuantServe vLLM serving Docker image"
  project     = var.project_id
  location    = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  repository_event_config {
    repository = google_cloudbuildv2_repository.quantserve.id
    push {
      branch = "^main$"
    }
  }

  included_files = [
    "serving/Dockerfile.serving",
    "serving/startup.sh",
  ]

  build {
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/serving:$COMMIT_SHA",
        "-t", "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/serving:latest",
        "-f", "serving/Dockerfile.serving",
        "serving/",
      ]
    }
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push", "--all-tags",
        "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/serving",
      ]
    }
  }
}
