# Enable all required GCP APIs.
# This module must be applied before any other module.
# disable_on_destroy = false prevents APIs being disabled when infrastructure is destroyed,
# which would break other projects sharing the same GCP project.

resource "google_project_service" "apis" {
    for_each = toset([
        "compute.googleapis.com",
        "storage.googleapis.com",
        "secretmanager.googleapis.com",
        "cloudbuild.googleapis.com",
        "monitoring.googleapis.com",
        "logging.googleapis.com",
        "iap.googleapis.com",
        "artifactregistry.googleapis.com",
        "iam.googleapis.com",
        "cloudresourcemanager.googleapis.com",
        "sourcerepo.googleapis.com",
    ])

    project            = var.project_id
    service            = each.value
    disable_on_destroy = false
}
