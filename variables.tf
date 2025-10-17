variable "tfc_worker_azure_private_key_base64" {
  description = "Certificate for AZ CLI authentication inside TFC worker"
  type        = string
  sensitive   = true
}

variable "ad_dns_operations_app_runbook_url" {
  description = "Base REST URL of the Azure Automation Runbook resource in the AD & DNS Operations infrastructure"
  type        = string
}

## Chef vars from workspace
variable "chef_validation_pem_base64" {
  description = "Chef validation PEM file in base64 format"
  type        = string
  sensitive   = true
}

variable "user_key_base64" {
  description = "Chef user key in base64 format"
  type        = string
  sensitive   = true
}

variable "databag_secret_key" {
  description = "Chef databag secret key (encrypted)"
  type        = string
  sensitive   = true
}

variable "virtual_machine_admin_password" {
  description = "Hetwinadmin Password (encrypted)"
  type        = string
  sensitive   = true
}
