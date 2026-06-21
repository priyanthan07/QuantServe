output "artifact_registry_repo" {
  value = google_artifact_registry_repository.pipeline.name
}

output "pipeline_image_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/quantserve/pipeline"
}

output "model_onboarding_trigger_id" {
  value = google_cloudbuild_trigger.model_onboarding.trigger_id
}
