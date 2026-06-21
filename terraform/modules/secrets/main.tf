# Creates the Secret Manager secret containers.
# The actual secret VALUES are not stored in Terraform.
# After apply, add values manually:
#   echo -n "YOUR_HF_TOKEN" | gcloud secrets versions add hf-access-token --data-file=-
#   echo -n "YOUR_API_KEY"  | gcloud secrets versions add inference-api-key --data-file=-

resource "google_secret_manager_secret" "hf_token" {
  secret_id = "hf-access-token"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "inference_api_key" {
  secret_id = "inference-api-key"
  project   = var.project_id

  replication {
    auto {}
  }
}
