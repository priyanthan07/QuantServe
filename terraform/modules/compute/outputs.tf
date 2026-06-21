output "instance_group_self_link" {
  value = google_compute_instance_group_manager.serving.instance_group
}

output "health_check_self_link" {
  value = google_compute_health_check.vllm.self_link
}
