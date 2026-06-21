# ---------- Project metadata ----------
# Needed to resolve the Cloud Build service account email.

data "google_project" "project" {
  project_id = var.project_id
}

locals {
  # Cloud Build's default service account
  cloudbuild_sa = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# ---------- Artifact Registry ----------
# Stores the pipeline Docker image used by Cloud Build steps.

resource "google_artifact_registry_repository" "pipeline" {
  location      = var.region
  repository_id = "quantserve"
  description   = "QuantServe pipeline Docker images"
  format        = "DOCKER"
  project       = var.project_id

  depends_on = [var.apis_enabled]
}

# ---------- Cloud Build IAM ----------
# Cloud Build SA needs these permissions to run the pipeline.

resource "google_project_iam_member" "cloudbuild_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.cloudbuild_sa
}

resource "google_project_iam_member" "cloudbuild_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = local.cloudbuild_sa
}

resource "google_project_iam_member" "cloudbuild_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.cloudbuild_sa
}

resource "google_project_iam_member" "cloudbuild_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = local.cloudbuild_sa
}

# Cloud Build needs to be able to create and delete the GPU Spot VM
resource "google_project_iam_member" "cloudbuild_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = local.cloudbuild_sa
}

# Cloud Build needs to attach the pipeline service account to the GPU VM
resource "google_project_iam_member" "cloudbuild_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = local.cloudbuild_sa
}

# ---------- Cloud Build Trigger: Build pipeline Docker image ----------
# Fires when Dockerfile.pipeline or any pipeline script changes.
# Builds and pushes the image to Artifact Registry.

resource "google_cloudbuild_trigger" "build_pipeline_image" {
  name        = "quantserve-build-pipeline-image"
  description = "Builds the QuantServe pipeline Docker image"
  project     = var.project_id
  location    = "global"

  # Using Cloud Source Repositories.
  # To use GitHub: replace trigger_template with a github {} block
  # after connecting your repo at console.cloud.google.com/cloud-build/repositories
  trigger_template {
    branch_name = "^main$"
    repo_name   = var.csr_repo_name
  }

  included_files = [
    "pipeline/Dockerfile.pipeline",
    "pipeline/scripts/**",
  ]

  build {
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

  depends_on = [var.apis_enabled]
}

# ---------- Cloud Build Trigger: Model onboarding pipeline ----------
# Fires when a model config YAML is added or changed.
# Provisions a GPU Spot VM, waits for GPU steps, then updates registry.

resource "google_cloudbuild_trigger" "model_onboarding" {
  name        = "quantserve-model-onboarding"
  description = "Runs the full model onboarding pipeline when a model config changes"
  project     = var.project_id
  location    = "global"

  trigger_template {
    branch_name = "^main$"
    repo_name   = var.csr_repo_name
  }

  included_files = ["model-configs/**"]

  filename = "pipeline/cloudbuild.yaml"

  substitutions = {
    _REGION             = var.region
    _ZONE               = var.zone
    _BASE_BUCKET        = var.base_models_bucket
    _QUANT_BUCKET       = var.quant_models_bucket
    _EVAL_BUCKET        = var.eval_results_bucket
    _REG_BUCKET         = var.model_registry_bucket
    _PIPELINE_SA        = var.pipeline_sa_email
    _ARTIFACT_REPO      = "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/pipeline"
  }

  depends_on = [var.apis_enabled]
}

