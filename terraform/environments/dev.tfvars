project_id  = "your-gcp-project-id"
region      = "us-central1"
zone        = "us-central1-a"
environment = "dev"

alert_notification_channel_email = "your-email@example.com"
ttft_p99_slo_seconds             = 3.0

models = {
  "qwen3-7b-w4a16" = {
    gcs_artifact_path = "qwen3-7b-w4a16/v1"
    gpu_type          = "nvidia-l4"
    machine_type      = "g2-standard-4"
    min_replicas      = 1
    max_replicas      = 2
    disk_size_gb      = 100
    vllm_args         = "--max-model-len 4096 --enable-prefix-caching"
  }
}

csr_repo_name = "quantserve"