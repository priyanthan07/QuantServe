#!/bin/bash
set -euo pipefail

# ---------- Configuration ----------
# These values are injected by Terraform templatefile().
BUCKET="${quantized_models_bucket}"
REG_BUCKET="${model_registry_bucket}"
MODEL_ID="${model_id}"
VLLM_EXTRA_ARGS="${vllm_args}"
PROJECT_ID="${project_id}"
SERVING_IMAGE="${serving_image_url}"

LOCAL_MODEL_DIR="/models/$${MODEL_ID}"
SECRET_NAME="inference-api-key"

echo "[quantserve] Starting model onload for $${MODEL_ID}"

# Step 1: Resolve the latest artifact path from the model registry
echo "[quantserve] Resolving latest artifact path"
REGISTRY_JSON=$(gcloud storage cat "gs://$${REG_BUCKET}/$${MODEL_ID}-latest.json")
ARTIFACT_PATH=$(echo "$${REGISTRY_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin)['gcs_artifact_path'])")
echo "[quantserve] Using artifact path: $${ARTIFACT_PATH}"
 
# Step 2: Copy model from GCS to local SSD
echo "[quantserve] Downloading model from gs://$${BUCKET}/$${ARTIFACT_PATH}/"
mkdir -p "$${LOCAL_MODEL_DIR}"
gcloud storage cp -r "gs://$${BUCKET}/$${ARTIFACT_PATH}/*" "$${LOCAL_MODEL_DIR}/"
echo "[quantserve] Model downloaded to $${LOCAL_MODEL_DIR}"

# Step 3: Fetch API key from Secret Manager
echo "[quantserve] Fetching API key from Secret Manager"
VLLM_API_KEY=$(gcloud secrets versions access latest \
  --secret="$${SECRET_NAME}" \
  --project="$${PROJECT_ID}")

# Step 4: Authenticate Docker to Artifact Registry
gcloud auth configure-docker "$${SERVING_IMAGE%%/*}" --quiet

# Step 5: Pull and run the serving container
echo "[quantserve] Pulling serving image: $${SERVING_IMAGE}:latest"
docker pull "$${SERVING_IMAGE}:latest"

echo "[quantserve] Starting vLLM container for $${MODEL_ID}"
exec docker run --rm --gpus all \
  -v "$${LOCAL_MODEL_DIR}":"$${LOCAL_MODEL_DIR}" \
  -e VLLM_API_KEY="$${VLLM_API_KEY}" \
  -e LMCACHE_CONFIG_FILE="/opt/quantserve/lmcache_config.yaml" \
  -p 8000:8000 \
  "$${SERVING_IMAGE}:latest" \
  python -m vllm.entrypoints.openai.api_server \
    --model "$${LOCAL_MODEL_DIR}" \
    --served-model-name "$${MODEL_ID}" \
    --host 0.0.0.0 \
    --port 8000 \
    --dtype auto \
    --trust-remote-code \
    --api-key "$${VLLM_API_KEY}" \
    $${VLLM_EXTRA_ARGS}
  