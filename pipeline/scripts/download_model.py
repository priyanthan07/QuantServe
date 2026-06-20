"""
    Download base model from HuggingFace Hub to GCS.
    Skips download if the model already exists at the expected GCS path
"""
import argparse
import os
import sys
import yaml
from google.cloud import storage
from huggingface_hub import snapshot_download, HfApi

def model_exists_in_gcs(bucket_name: str, prefix: str) -> bool:
    """
        Check if model files already exist in GCS.
    """
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blobs = list(bucket.list_blobs(prefix=prefix, max_results=1))
    return len(blobs) > 0

def get_hf_commit_hash(model_id: str) -> str:
    """
        Get the latest commit hash for a HuggingFace model
    """
    api = HfApi()
    model_info = api.model_info(model_id)
    return model_info.sha

def download_and_upload(model_id: str, commit_hash: str, bucket_name: str):
    """
        Download model from HF local disk, then upload to GCS
    """
    local_dir = f"/tmp/models/{model_id.replace('/', '_')}"
    
    print(f"Downloading {model_id} (commit: {commit_hash} to {local_dir})")
    snapshot_download(
        repo_id=model_id,
        revision=commit_hash,
        local_dir=local_dir,
        token=os.environ.get("HF_TOKEN")
    )
    
    gcs_prefix = f"{model_id.replace('/', '_')}/{commit_hash}"
    print(f"Uploading to gs://{bucket_name}/{gcs_prefix}/")
    
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    
    for root, _, files in os.walk(local_dir):
        for filename in files:
            local_path = os.path.join(root, filename)
            relative_path = os.path.relpath(local_path, local_dir)
            blob_path = f"{gcs_prefix}/{relative_path}"
            blob = bucket.blob(blob_path)
            blob.upload_from_filename(local_path)
            print(f" Uploaded: {blob_path}")
            

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, help="Path to model config YAML")
    parser.add_argument("--bucket", required=True, help="GCS bucket for base models")
    args = parser.parse_args()
    
    with open(args.config) as f:
        config = yaml.safe_load(f)
        
    model_id = config["hf_model_id"]
    commit_hash = get_hf_commit_hash(model_id)
    gcs_prefix = f"{model_id.replace('/', '_')}/{commit_hash}"
    
    if model_exists_in_gcs(args.bucket, gcs_prefix):
        print(f"Model already exists at gs://{args.bucket}/{gcs_prefix}/ — skipping download")
        # Write commit hash for downstream steps
        with open("/tmp/hf_commit_hash.txt", "w") as f:
            f.write(commit_hash)
        return
    
    download_and_upload(model_id, commit_hash, args.bucket)
    
    with open("/tmp/hf_commit_hash.txt", "w") as f:
        f.write(commit_hash)
        
    print("Download complete.")
    
if __name__ == "__main__":
    main()
    