"""
Benchmark a quantized model using GuideLLM.
Starts a local vLLM server, runs GuideLLM against it, uploads results to GCS.
"""
import argparse
import json
import os
import subprocess
import time

import yaml


def start_vllm_server(model_path: str, model_name: str, extra_args: str) -> subprocess.Popen:
    """Start a vLLM server in the background and wait for it to be ready."""
    cmd = [
        "python", "-m", "vllm.entrypoints.openai.api_server",
        "--model", model_path,
        "--served-model-name", model_name,
        "--host", "0.0.0.0",
        "--port", "8000",
        "--dtype", "auto",
    ]

    if extra_args:
        cmd.extend(extra_args.split())

    print(f"Starting vLLM server: {' '.join(cmd)}")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    # Wait for health check to pass
    import urllib.request
    max_wait = 300  # 5 minutes
    start_time = time.time()
    while time.time() - start_time < max_wait:
        try:
            resp = urllib.request.urlopen("http://localhost:8000/health", timeout=5)
            if resp.status == 200:
                print("vLLM server is ready.")
                return proc
        except Exception:
            pass
        time.sleep(5)

    proc.terminate()
    raise TimeoutError("vLLM server did not become ready within 5 minutes")


def run_guidellm(model_name: str, output_path: str):
    """Run GuideLLM benchmark sweep against the local vLLM server."""
    cmd = [
        "guidellm",
        "--target", "http://localhost:8000",
        "--model", model_name,
        "--profile", "sweep",
        "--max-seconds", "120",
        "--data", "kind=synthetic_text,prompt_tokens=256,output_tokens=128",
        "--output-path", output_path,
    ]

    print(f"Running GuideLLM: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)
    print(f"GuideLLM results written to {output_path}")


def upload_results(local_path: str, bucket: str, prefix: str):
    """Upload GuideLLM results to GCS."""
    from google.cloud import storage

    client = storage.Client()
    gcs_bucket = client.bucket(bucket)

    blob = gcs_bucket.blob(f"{prefix}/guidellm_results.json")
    blob.upload_from_filename(local_path)
    print(f"Results uploaded to gs://{bucket}/{prefix}/guidellm_results.json")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--quant-bucket", required=True)
    parser.add_argument("--eval-bucket", required=True)
    args = parser.parse_args()

    with open(args.config) as f:
        config = yaml.safe_load(f)

    with open("/tmp/quant_local_dir.txt") as f:
        model_path = f.read().strip()

    with open("/tmp/quant_version.txt") as f:
        version = f.read().strip()

    model_name = config["model_name"]
    scheme = config["quantization_scheme"]
    vllm_args = config.get("vllm_args", "")

    eval_prefix = f"{model_name}-{scheme.lower()}/{version}"
    output_path = "/tmp/guidellm_results.json"

    # Start vLLM server
    vllm_proc = start_vllm_server(model_path, model_name, vllm_args)

    try:
        # Run GuideLLM
        run_guidellm(model_name, output_path)

        # Upload results
        upload_results(output_path, args.eval_bucket, eval_prefix)
    finally:
        # Always stop the server
        vllm_proc.terminate()
        vllm_proc.wait(timeout=30)
        print("vLLM server stopped.")


if __name__ == "__main__":
    main()
    