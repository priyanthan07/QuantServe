""" 
    Update the model registry with complete lineage, evaluation scores, and deployment 
    readiness status.
"""
import argparse
import json
import os
from datetime import datetime, timezone
 
import yaml
from google.cloud import storage

def load_eval_results(bucket_name: str, prefix: str) -> dict:
    """ 
        Load lm_eval results from GCS.
    """
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    
    results = {}
    
    # Load lm_eval results
    lm_eval_blob = bucket.blob(f"{prefix}/lm_eval_results.json")
    if lm_eval_blob.exists():
        content = lm_eval_blob.download_as_text()
        results["lm_eval"] = json.loads(content)
        
    
    # Load quality warnings
    warnings_blob = bucket.blob(f"{prefix}/quality_warnings.json")
    if warnings_blob.exists():
        content = warnings_blob.download_as_text()
        results["quality_warnings"] = json.loads(content)
        
    # Load GuideLLM results
    guidellm_blob = bucket.blob(f"{prefix}/guidellm_results.json")
    if guidellm_blob.exists():
        content = guidellm_blob.download_as_text()
        results["guidellm"] = json.loads(content)
        
    return results

def extract_scores(eval_results: dict) -> dict:
    """
        Extract key scores from lm_eval results for the registry summary.
    """
    scores = {}
    lm_eval_data = eval_results.get("lm_eval", {}).get("results", {})
    
    for task_name, task_data in lm_eval_data.items():
        for key in ["acc,none", "acc_norm,none"]:
            if key in task_data:
                scores[task_name] = round(task_data[key], 4)
                break
            
    return scores

def build_registry_entry(config: dict, version: str, eval_results: dict) -> dict:
    """
        Build the complete registry entry for a model version.
    """
    
    quality_data = eval_results.get("quality_warnings", {})
    quality_warning = quality_data.get("quality_warning", False) if isinstance(quality_data, dict) else False
    warnings = quality_data.get("warnings", []) if isinstance(quality_data, dict) else []
 
    entry = {
        "model_name": config["model_name"],
        "hf_model_id": config["hf_model_id"],
        "quantization_scheme": config["quantization_scheme"],
        "recipe": config["recipe"],
        "calibration_dataset": config["calibration_dataset"],
        "num_calibration_samples": config["num_calibration_samples"],
        "max_seq_length": config["max_seq_length"],
        "version": version,
        "evaluation_scores": extract_scores(eval_results),
        "quality_warning": quality_warning,
        "quality_warnings_detail": warnings,
        "has_guidellm_results": "guidellm" in eval_results,
        "promoted_at": datetime.now(timezone.utc).isoformat(),
        "status": "promoted",
    }
 
    return entry

def upload_registry_entry(entry: dict, bucket_name: str, model_key: str):
    """
        Upload registry entry to GCS.
    """
    
    client = storage.Client()
    bucket = client.bucket(bucket_name)
 
    blob_path = f"{model_key}.json"
    blob = bucket.blob(blob_path)
    blob.upload_from_string(
        json.dumps(entry, indent=2),
        content_type="application/json",
    )
    print(f"Registry entry uploaded to gs://{bucket_name}/{blob_path}")
    
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--eval-bucket", required=True)
    parser.add_argument("--registry-bucket", required=True)
    args = parser.parse_args()
 
    with open(args.config) as f:
        config = yaml.safe_load(f)
 
    with open("/tmp/quant_version.txt") as f:
        version = f.read().strip()
 
    model_name = config["model_name"]
    scheme = config["quantization_scheme"]
    eval_prefix = f"{model_name}-{scheme.lower()}/{version}"
    model_key = f"{model_name}-{scheme.lower()}"
 
    # Load evaluation results from GCS
    eval_results = load_eval_results(args.eval_bucket, eval_prefix)
 
    # Build and upload registry entry
    entry = build_registry_entry(config, version, eval_results)
    upload_registry_entry(entry, args.registry_bucket, model_key)
 
    # Print summary
    print("\n--- Registry Summary ---")
    print(f"Model: {model_name} ({scheme})")
    print(f"Version: {version}")
    print(f"Quality warning: {entry['quality_warning']}")
    print(f"Scores: {json.dumps(entry['evaluation_scores'], indent=2)}")
    print(f"Status: {entry['status']}")
 
 
if __name__ == "__main__":
    main()
    