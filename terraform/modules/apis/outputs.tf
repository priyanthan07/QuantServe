output "enabled" {
  description = "Signals that all required APIs have been enabled"
  value       = true
  depends_on  = [google_project_service.apis]
}