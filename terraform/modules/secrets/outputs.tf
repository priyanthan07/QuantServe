output "hf_token_secret_id" {
  value = google_secret_manager_secret.hf_token.secret_id
}

output "inference_api_key_secret_id" {
  value = google_secret_manager_secret.inference_api_key.secret_id
}
