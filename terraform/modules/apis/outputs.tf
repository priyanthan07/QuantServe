# This output exists purely as a dependency signal.
# Other modules receive it as the apis_enabled variable,
# ensuring no resource is created before the required APIs are enabled.
output "enabled" {
  description = "Signals that all required APIs have been enabled"
  value       = true
  depends_on  = [google_project_service.apis]
}
