"""
Evaluate a quantized model using lm_eval.
Runs benchmarks specified in the model config, uploads results to GCS.
Soft gate: logs warnings if thresholds are missed, does not block pipeline.
"""
import argparse
import json
import os
from datetime import datetime, timezone
 
import yaml
import lm_eval

def run_evaluation(model_path: str, benchmarks: list[str]) -> dict:
    """Run lm_eval against the quantized model on local disk."""
    print(f"Running lm_eval benchmarks: {benchmarks}")
    print(f"Model path: {model_path}")
 
    results = lm_eval.simple_evaluate(
        model="hf",
        model_args=f"pretrained={model_path}",
        tasks=benchmarks,
        batch_size="auto",
    )
 
    return results

def check_thresholds(results: dict, thresholds: dict) -> list[dict]:
    """Compare results against thresholds. Returns list of warnings."""
    warnings = []
 
    for benchmark, min_score in thresholds.items():
        if benchmark not in results.get("results", {}):
            warnings.append({
                "benchmark": benchmark,
                "status": "missing",
                "message": f"Benchmark {benchmark} not found in results",
            })
            continue
 
        # lm_eval stores accuracy in different keys depending on the task.
        # Common patterns: acc,none / acc_norm,none
        task_results = results["results"][benchmark]
        score = None
        for key in ["acc,none", "acc_norm,none"]:
            if key in task_results:
                score = task_results[key]
                break
 
        if score is None:
            warnings.append({
                "benchmark": benchmark,
                "status": "no_metric",
                "message": f"Could not find accuracy metric in {benchmark} results",
            })
            continue
 
        if score < min_score:
            warnings.append({
                "benchmark": benchmark,
                "status": "below_threshold",
                "expected": min_score,
                "actual": round(score, 4),
                "message": f"{benchmark}: {score:.4f} < {min_score} (threshold)",
            })
            print(f"  WARNING: {benchmark} score {score:.4f} below threshold {min_score}")
        else:
            print(f"  PASS: {benchmark} score {score:.4f} >= {min_score}")
 
    return warnings


def upload_results(results: dict, warnings: list, bucket: str, prefix: str):
    """Upload evaluation results and warnings to GCS."""
    from google.cloud import storage
 
    client = storage.Client()
    gcs_bucket = client.bucket(bucket)
 
    # Upload full results
    results_blob = gcs_bucket.blob(f"{prefix}/lm_eval_results.json")
    results_blob.upload_from_string(
        json.dumps(results, indent=2, default=str),
        content_type="application/json",
    )
    print(f"Results uploaded to gs://{bucket}/{prefix}/lm_eval_results.json")
 
    # Upload warnings separately for easy parsing
    if warnings:
        warnings_blob = gcs_bucket.blob(f"{prefix}/quality_warnings.json")
        warnings_blob.upload_from_string(
            json.dumps(warnings, indent=2),
            content_type="application/json",
        )
        print(f"Warnings uploaded to gs://{bucket}/{prefix}/quality_warnings.json")
 
 
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--quant-bucket", required=True)
    parser.add_argument("--eval-bucket", required=True)
    args = parser.parse_args()
 
    with open(args.config) as f:
        config = yaml.safe_load(f)
 
    # Read local path from quantization step
    with open("/tmp/quantserve/quant_local_dir.txt") as f:
        model_path = f.read().strip()
 
    with open("/tmp/quantserve/quant_version.txt") as f:
        version = f.read().strip()
 
    model_name = config["model_name"]
    scheme = config["quantization_scheme"]
    benchmarks = config["benchmarks"]
    thresholds = config.get("thresholds", {})
 
    eval_prefix = f"{model_name}-{scheme.lower()}/{version}"
 
    # Run evaluation
    results = run_evaluation(model_path, benchmarks)
 
    # Check thresholds (soft gate)
    warnings = check_thresholds(results, thresholds)
 
    # Upload results
    upload_results(results, warnings, args.eval_bucket, eval_prefix)
 
    # Write warnings flag for downstream steps
    quality_warning = len(warnings) > 0
    with open("/tmp/quality_warning.json", "w") as f:
        json.dump({"quality_warning": quality_warning, "warnings": warnings}, f)
 
    if quality_warning:
        print(f"\nQuality gate: {len(warnings)} warning(s) — pipeline continues with warnings.")
    else:
        print("\nQuality gate: all thresholds passed.")
 
 
if __name__ == "__main__":
    main()
 