#!/bin/bash
set -euo pipefail

# ---------- Configuration ----------
# These values are injected by Terraform templatefile().
BUCKET="${quantized_models_bucket}"
ARTIFACT_PATH="${gcs_artifact_path}"
MODEL_ID="${model_id}"
VLLM_EXTRA_ARGS="${vllm_args}"
PROJECT_ID="${project_id}"
 
LOCAL_MODEL_DIR="/models/$${MODEL_ID}"
SECRET_NAME="inference-api-key"

echo "[quantserve] Starting model onload for $${MODEL_ID}"
 
# ---------- Step 1: Copy model from GCS to local SSD ----------
echo "[quantserve] Downloading model from gs://$${BUCKET}/$${ARTIFACT_PATH}/"
mkdir -p "$${LOCAL_MODEL_DIR}"
gcloud storage cp -r "gs://$${BUCKET}/$${ARTIFACT_PATH}/*" "$${LOCAL_MODEL_DIR}/"
echo "[quantserve] Model downloaded to $${LOCAL_MODEL_DIR}"

# ---------- Step 2: Fetch API key from Secret Manager ----------
echo "[quantserve] Fetching API key from Secret Manager"
VLLM_API_KEY=$(gcloud secrets versions access latest \
  --secret="$${SECRET_NAME}" \
  --project="$${PROJECT_ID}")
export VLLM_API_KEY

# ---------- Step 3: Start vLLM ----------
echo "[quantserve] Starting vLLM for model $${MODEL_ID}"
exec python -m vllm.entrypoints.openai.api_server \
  --model "$${LOCAL_MODEL_DIR}" \
  --served-model-name "$${MODEL_ID}" \
  --host 0.0.0.0 \
  --port 8000 \
  --dtype auto \
  --trust-remote-code \
  $${VLLM_EXTRA_ARGS}
  