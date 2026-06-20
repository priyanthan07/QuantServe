"""
    Quantize a base model using llm-compressor.
    Downloads base model from GCS, runs oneshot() quantization,
    uploads the quantized artifact back to GCS.
"""
import argparse
import json
import os
import subprocess
from datetime import datetime, timezone
 
import yaml
from llmcompressor import oneshot
from llmcompressor.modifiers.quantization import GPTQModifier, QuantizationModifier

# Map scheme names to modifier constructors and configurations
SCHEME_REGISTRY = {
    "W4A16": {
        "modifier_cls": GPTQModifier,
        "params": {"scheme": "W4A16", "targets": "Linear", "ignore": ["lm_head"]},
    },
    "W8A16": {
        "modifier_cls": GPTQModifier,
        "params": {"scheme": "W8A16", "targets": "Linear", "ignore": ["lm_head"]},
    },
    "W8A8": {
        "modifier_cls": QuantizationModifier,
        "params": {"scheme": "W8A8", "targets": "Linear", "ignore": ["lm_head"]},
    },
}

def download_from_gcs(bucket: str, prefix: str, local_dir: str):
    """Download model files from GCS to local directory."""
    os.makedirs(local_dir, exist_ok=True)
    cmd = ["gcloud", "storage", "cp", "-r", f"gs://{bucket}/{prefix}/*", local_dir]
    subprocess.run(cmd, check=True)
    
def upload_to_gcs(local_dir: str, bucket: str, prefix: str):
    """Upload local directory to GCS."""
    cmd = ["gcloud", "storage", "cp", "-r", f"{local_dir}/*", f"gs://{bucket}/{prefix}/"]
    subprocess.run(cmd, check=True)
    
def run_quantization(config: dict, base_model_dir: str, output_dir: str):
    """Run llm-compressor oneshot() with the recipe from config."""
    scheme = config["quantization_scheme"]
 
    if scheme not in SCHEME_REGISTRY:
        raise ValueError(
            f"Unknown quantization scheme: {scheme}. Available: {list(SCHEME_REGISTRY.keys())}"
        )
 
    scheme_config = SCHEME_REGISTRY[scheme]
    modifier = scheme_config["modifier_cls"](**scheme_config["params"])
 
    print(f"Running quantization: {scheme}")
    print(f"  Base model: {base_model_dir}")
    print(f"  Output: {output_dir}")
    print(f"  Calibration: {config['calibration_dataset']} ({config['num_calibration_samples']} samples)")
 
    oneshot(
        model=base_model_dir,
        dataset=config["calibration_dataset"],
        dataset_config_name=config.get("calibration_dataset_config", None),
        recipe=modifier,
        output_dir=output_dir,
        num_calibration_samples=config["num_calibration_samples"],
        max_seq_length=config["max_seq_length"],
    )
 
    print("Quantization complete.")
    
def write_metadata(config: dict, output_dir: str):
    """Write metadata.json alongside the quantized model."""
    metadata = {
        "model_name": config["model_name"],
        "hf_model_id": config["hf_model_id"],
        "quantization_scheme": config["quantization_scheme"],
        "recipe": config["recipe"],
        "calibration_dataset": config["calibration_dataset"],
        "num_calibration_samples": config["num_calibration_samples"],
        "max_seq_length": config["max_seq_length"],
        "quantized_at": datetime.now(timezone.utc).isoformat(),
    }
 
    metadata_path = os.path.join(output_dir, "metadata.json")
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)
    print(f"Metadata written to {metadata_path}")
    

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--base-bucket", required=True)
    parser.add_argument("--quant-bucket", required=True)
    args = parser.parse_args()
 
    with open(args.config) as f:
        config = yaml.safe_load(f)
 
    model_name = config["model_name"]
    scheme = config["quantization_scheme"]
    hf_model_id = config["hf_model_id"]
 
    # Read commit hash from download step
    commit_hash_file = "/tmp/hf_commit_hash.txt"
    if os.path.exists(commit_hash_file):
        with open(commit_hash_file) as f:
            commit_hash = f.read().strip()
    else:
        commit_hash = "latest"
 
    # Paths
    base_model_dir = f"/tmp/base-model/{model_name}"
    output_dir = f"/tmp/quantized/{model_name}-{scheme.lower()}"
    gcs_base_prefix = f"{hf_model_id.replace('/', '_')}/{commit_hash}"
    version = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    gcs_quant_prefix = f"{model_name}-{scheme.lower()}/{version}"
 
    # Download base model from GCS
    print(f"Downloading base model from gs://{args.base_bucket}/{gcs_base_prefix}/")
    download_from_gcs(args.base_bucket, gcs_base_prefix, base_model_dir)
 
    # Run quantization
    run_quantization(config, base_model_dir, output_dir)
 
    # Write metadata
    write_metadata(config, output_dir)
 
    # Upload quantized model to GCS
    print(f"Uploading quantized model to gs://{args.quant_bucket}/{gcs_quant_prefix}/")
    upload_to_gcs(output_dir, args.quant_bucket, gcs_quant_prefix)
 
    # Write version for downstream steps
    with open("/tmp/quant_version.txt", "w") as f:
        f.write(version)
    with open("/tmp/quant_gcs_prefix.txt", "w") as f:
        f.write(gcs_quant_prefix)
    with open("/tmp/quant_local_dir.txt", "w") as f:
        f.write(output_dir)
 
    print(f"Quantization pipeline complete: {gcs_quant_prefix}")
 
 
if __name__ == "__main__":
    main()
    