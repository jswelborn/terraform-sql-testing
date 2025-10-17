terraform {
  cloud {
    organization = "hts_automation"

    workspaces {
      name = "hts-queen-sre-azure-compute"
    }
  }

  required_version = "~> 1.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "6133c7a0-a417-43b9-acb9-1bdd65114bbe"
}

locals {
  virtual_machine_os = "server2022"
}

#module "windows_vm" {
#  source  = "app.terraform.io/hts_automation/vm-windows/azure"
#  version = "~> 3.0.0"

# Env information
#create_resource_group               = false
#  resource_group_name                 = "rg-80020000-htsjswtest001"
#  resource_group_location             = "eastus"
#  virtual_network_name                = "ht-hts-eastus-vnet1"
#  virtual_network_resource_group_name = "ht-hts-eastus-core-rg"
#  subnet_name                         = "ht-hts-eastus-utilityservices-app-prod-subnet-private"

# VM information
#  virtual_machine_os             = local.virtual_machine_os
#  virtual_machine_name           = "htsjswtest001"
#  virtual_machine_size           = "Standard_D2_v5"
#  virtual_machine_admin_password = var.virtual_machine_admin_password
#  os_disk_disk_size_gb           = 127
#  additional_disks = [
#    {
#      volume_name  = "extdisk10"
#      drive_letter = "g"
#      disk_size_gb = 10
#    },
#    {
#      volume_name  = "extdisk20"
#      drive_letter = "i"
#      disk_size_gb = 20
#    }
#  ]


#  chef_version               = "18.7.6"
#  policy_name                = "hts_chef_base_node_pf"
#  policy_group               = "staging"
#  chef_client_action         = "run"
#  domain_name                = "companynet.org"
#  chef_validation_pem_base64 = var.chef_validation_pem_base64
#  databag_secret_key         = var.databag_secret_key
#  user_key_base64            = var.user_key_base64

#  ad_dns_operations_app_runbook_url   = var.ad_dns_operations_app_runbook_url
#  tfc_worker_azure_private_key_base64 = var.tfc_worker_azure_private_key_base64

#  tag_costcenter   = "80020000"
#  tag_businessunit = "Hearst_Technology_Service"
#  tag_product      = "TFC_Module_Development"
#  tag_application  = "Test_System"
#  tag_environment  = "dev"
#  tag_supportteam  = "hts.sre@hearst.com"
#  custom_tags = {
#    Monitoring      = "Datadog"
#    AlertingProfile = "no_alerts"
#  }
#}

locals {
  vm_os_key = "server2022" # Appeases module validation, actual image overridden below
}

module "sql_vm" {
  source  = "app.terraform.io/hts_automation/vm-windows/azure"
  version = "~> 3.0.0"

  resource_group_name                 = "rg-80020000-htsjswsql001"
  resource_group_location             = "eastus"
  virtual_network_name                = "ht-hts-eastus-vnet1"
  virtual_network_resource_group_name = "ht-hts-eastus-core-rg"
  subnet_name                         = "ht-hts-eastus-utilityservices-app-prod-subnet-private"

  virtual_machine_os = local.vm_os_key

  virtual_machine_os_details = {
    server2022 = {
      publisher = "MicrosoftSQLServer"
      offer     = "SQL2025-WS2025"
      sku       = "stddev-gen2"
      version   = "latest"
    }
  }

  virtual_machine_name           = "htsjswsql001"
  virtual_machine_size           = "Standard_D8s_v5"
  virtual_machine_admin_password = var.virtual_machine_admin_password
  os_disk_disk_size_gb           = 256

  additional_disks = [
    {
      volume_name  = "sqldata"
      drive_letter = "f"
      disk_size_gb = 256
    },
    {
      volume_name  = "sqllogs"
      drive_letter = "g"
      disk_size_gb = 128
    }
  ]

  chef_version               = "18.7.6"
  policy_name                = "hts_chef_base_node_pf"
  policy_group               = "staging"
  chef_client_action         = "run"
  domain_name                = "companynet.org"
  chef_validation_pem_base64 = var.chef_validation_pem_base64
  databag_secret_key         = var.databag_secret_key
  user_key_base64            = var.user_key_base64

  ad_dns_operations_app_runbook_url   = var.ad_dns_operations_app_runbook_url
  tfc_worker_azure_private_key_base64 = var.tfc_worker_azure_private_key_base64

  tag_costcenter   = "80020000"
  tag_businessunit = "Hearst_Technology_Service"
  tag_product      = "SQL_2025_Instance"
  tag_application  = "Test_System"
  tag_environment  = "prod"
  tag_supportteam  = "hts.sre@hearst.com"

  custom_tags = {
    Monitoring      = "Datadog"
    AlertingProfile = "no_alerts"
  }
}

# Look up the Windows VM created by the module — only after it's built
data "azurerm_virtual_machine" "sql_vm" {
  name                = "htsjswsql001"
  resource_group_name = "rg-80020000-htsjswsql001"
  depends_on          = [module.sql_vm]
}

# Register the VM as a SQL IaaS instance
resource "azurerm_mssql_virtual_machine" "sql_config" {
  virtual_machine_id = data.azurerm_virtual_machine.sql_vm.id
  sql_license_type   = "PAYG"

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [data.azurerm_virtual_machine.sql_vm]
}

