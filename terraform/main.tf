provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------- APIs (must be first — everything depends on this) ----------

module "apis" {
  source     = "./modules/apis"
  project_id = var.project_id
}

# ---------- Secrets ----------

module "secrets" {
  source       = "./modules/secrets"
  project_id   = var.project_id
  apis_enabled = module.apis.enabled
}

# ---------- Networking ----------

module "networking" {
  source = "./modules/networking"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  depends_on = [module.apis]
}

# ---------- Storage ----------

module "storage" {
  source = "./modules/storage"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  depends_on = [module.apis]
}

# ---------- IAM ----------

module "iam" {
  source = "./modules/iam"

  project_id         = var.project_id
  base_models_bucket = module.storage.base_models_bucket_name
  quant_models_bucket = module.storage.quantized_models_bucket_name
  eval_results_bucket = module.storage.evaluation_results_bucket_name
  model_registry_bucket = module.storage.model_registry_bucket_name
}

# ---------- CI/CD ----------

module "cicd" {
  source = "./modules/cicd"

  project_id            = var.project_id
  region                = var.region
  zone                  = var.zone
  environment           = var.environment
  base_models_bucket    = module.storage.base_models_bucket_name
  quant_models_bucket   = module.storage.quantized_models_bucket_name
  eval_results_bucket   = module.storage.evaluation_results_bucket_name
  model_registry_bucket = module.storage.model_registry_bucket_name
  pipeline_sa_email     = module.iam.pipeline_sa_email
  apis_enabled          = module.apis.enabled
}

# ---------- Compute (serving instances per model) ----------

module "compute" {
  source   = "./modules/compute"
  for_each = var.models

  project_id  = var.project_id
  region      = var.region
  zone        = var.zone
  environment = var.environment

  model_id          = each.key
  gpu_type          = each.value.gpu_type
  machine_type      = each.value.machine_type
  min_replicas      = each.value.min_replicas
  max_replicas      = each.value.max_replicas
  disk_size_gb      = each.value.disk_size_gb
  vllm_args         = each.value.vllm_args

  subnet_self_link       = module.networking.serving_subnet_self_link
  serving_sa_email       = module.iam.serving_sa_email
  quantized_models_bucket = module.storage.quantized_models_bucket_name
  model_registry_bucket   = module.storage.model_registry_bucket_name
  serving_image_url = module.cicd.serving_image_url

  depends_on = [module.apis]
}

# ---------- Load Balancer (one per model) ----------

module "load_balancer" {
  source   = "./modules/load_balancer"

  project_id  = var.project_id
  environment = var.environment
  domain_suffix = var.domain_suffix
  default_model_id = var.default_model_id

  model_backends = {
    for model_id, _ in var.models : model_id => {
      instance_group = module.compute[model_id].instance_group_self_link
      health_check   = module.compute[model_id].health_check_self_link
    }
  }

  grafana_backend = {
    instance_group = module.observability.grafana_instance_group
    health_check   = module.observability.grafana_health_check
  }

  depends_on = [module.apis]
}

# ---------- Observability ----------

module "observability" {
  source = "./modules/observability"

  project_id  = var.project_id
  region      = var.region
  zone        = var.zone
  environment = var.environment

  subnet_self_link    = module.networking.observability_subnet_self_link
  observability_sa_email = module.iam.observability_sa_email
  models                           = var.models
  alert_notification_channel_email = var.alert_notification_channel_email
  ttft_p99_slo_seconds             = var.ttft_p99_slo_seconds
  domain_suffix                    = var.domain_suffix
  grafana_admin_password_secret_id = module.secrets.grafana_admin_password_secret_id

  depends_on = [module.apis]
}

# ---------- DNS ----------

module "dns" {
  source = "./modules/dns"

  project_id    = var.project_id
  dns_zone_name = var.dns_zone_name
  domain_suffix = var.domain_suffix
  api_lb_ip     = module.load_balancer.external_ip
}
