#!/bin/bash
set -euo pipefail

# ---------- Read parameters from GCE metadata ----------
METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
HEADERS="-H 'Metadata-Flavor: Google'"

get_metadata() {
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"
}

MODEL_CONFIG_GCS=$(get_metadata "model_config_gcs")
BASE_BUCKET=$(get_metadata "base_bucket")
QUANT_BUCKET=$(get_metadata "quant_bucket")
EVAL_BUCKET=$(get_metadata "eval_bucket")
REG_BUCKET=$(get_metadata "reg_bucket")
BUILD_ID=$(get_metadata "build_id")
ZONE=$(get_metadata "zone")
PROJECT_ID=$(get_metadata "project_id")
ARTIFACT_REPO=$(get_metadata "artifact_repo")

INSTANCE_NAME=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/name")

COMPLETION_FLAG="gs://${EVAL_BUCKET}/_pipeline_flags/${BUILD_ID}/COMPLETE"
FAILURE_FLAG="gs://${EVAL_BUCKET}/_pipeline_flags/${BUILD_ID}/FAILED"

echo "[gpu_startup] Starting GPU pipeline for build ${BUILD_ID}"

# ---------- Self-cleanup on exit ----------
cleanup() {
  EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    echo "[gpu_startup] Pipeline failed with exit code ${EXIT_CODE}"
    echo "FAILED" | gcloud storage cp - "${FAILURE_FLAG}"
  fi
  # Self-delete this VM after a short delay to allow logs to flush
  sleep 10
  gcloud compute instances delete "${INSTANCE_NAME}" \
    --zone="${ZONE}" \
    --project="${PROJECT_ID}" \
    --quiet || true
}
trap cleanup EXIT

# ---------- Install pipeline dependencies ----------
echo "[gpu_startup] Pulling pipeline image"
docker pull "${ARTIFACT_REPO}:latest"

# ---------- Download model config from GCS ----------
echo "[gpu_startup] Downloading model config"
mkdir -p /tmp/quantserve
gcloud storage cp "${MODEL_CONFIG_GCS}" /tmp/quantserve/model_config.yaml

# ---------- Run pipeline steps inside container ----------
DOCKER_RUN="docker run --rm --gpus all \
  -v /tmp/quantserve:/tmp/quantserve \
  -e BASE_BUCKET=${BASE_BUCKET} \
  -e QUANT_BUCKET=${QUANT_BUCKET} \
  -e EVAL_BUCKET=${EVAL_BUCKET} \
  -e GOOGLE_CLOUD_PROJECT=${PROJECT_ID} \
  ${ARTIFACT_REPO}:latest"

# Step 1: Download base model (if not already in GCS)
HF_TOKEN=$(gcloud secrets versions access latest \
  --secret="hf-access-token" \
  --project="${PROJECT_ID}")

echo "[gpu_startup] Running: download_model"
$DOCKER_RUN python3 scripts/download_model.py \
  --config /tmp/quantserve/model_config.yaml \
  --bucket "${BASE_BUCKET}" \
  -e HF_TOKEN="${HF_TOKEN}"

# Step 2: Quantize
echo "[gpu_startup] Running: quantize_model"
$DOCKER_RUN python3 scripts/quantize_model.py \
  --config /tmp/quantserve/model_config.yaml \
  --base-bucket "${BASE_BUCKET}" \
  --quant-bucket "${QUANT_BUCKET}"

# Step 3: Evaluate with lm_eval
echo "[gpu_startup] Running: evaluate_model"
$DOCKER_RUN python3 scripts/evaluate_model.py \
  --config /tmp/quantserve/model_config.yaml \
  --quant-bucket "${QUANT_BUCKET}" \
  --eval-bucket "${EVAL_BUCKET}"

# Step 4: Benchmark with GuideLLM
echo "[gpu_startup] Running: benchmark_model"
$DOCKER_RUN python3 scripts/benchmark_model.py \
  --config /tmp/quantserve/model_config.yaml \
  --quant-bucket "${QUANT_BUCKET}" \
  --eval-bucket "${EVAL_BUCKET}"

# ---------- Signal success ----------
echo "SUCCESS" | gcloud storage cp - "${COMPLETION_FLAG}"
echo "[gpu_startup] GPU pipeline complete. Signalled ${COMPLETION_FLAG}"
