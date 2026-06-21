terraform {
    backend "gcs" {
        bucket = "" # Set via: terraform init -backend-config="bucket=YOUR_PROJECT-terraform-state"
        prefix = "quantserve"
    }

    required_version = ">= 1.5.0"

    required_providers {
        google = {
        source  = "hashicorp/google"
        version = "~> 5.0"
        }
    }
}
