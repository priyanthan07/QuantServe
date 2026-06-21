variable "project_id" {
  type = string
}

# Dummy variable to enforce dependency on the apis module.
# Pass any output from the apis module here.
variable "apis_enabled" {
  type    = any
  default = null
}
