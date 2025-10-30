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
  subscription_id = "03406327-efac-48f9-86da-67618104eec3"
}

# Shared Locals
locals {
  vm_os_key = "server2025sql"
  rg_name   = "rg-20080000-multilex-non-prod"
  region    = "uksouth"

  # File paths and URLs used for post-config persistence
  hts_root     = "C:\\ProgramData\\HTS"
  hts_scripts  = "C:\\ProgramData\\HTS\\scripts"
  hts_markers  = "C:\\ProgramData\\HTS\\markers"
  temp_dir     = "C:\\Temp"
  task_name    = "HTS_SQL_PostConfig_OnStartup"
  wrapper_name = "sql_post_config.wrapper.ps1"
  main_name    = "sql_post_config.ps1"
  done_flag    = "sql_post_config_done.flag"
  main_uri     = "https://raw.githubusercontent.com/jswelborn/terraform-sql-testing/master/sql_post_config.ps1"
}

#  SQL VM: hbm044cldtcd508
module "sql_vm_hbm044cldtcd508" {
  source  = "app.terraform.io/hts_automation/vm-windows/azure"
  version = "~> 4.1.0"

  create_resource_group               = false
  resource_group_name                 = local.rg_name
  resource_group_location             = local.region
  virtual_network_name                = "vnet-10.123.52.0_23-southuk"
  virtual_network_resource_group_name = "rg-20080000-Multilex-Non-Prod"
  subnet_name                         = "default"

  virtual_machine_os             = local.vm_os_key
  virtual_machine_name           = "hbm044cldtcd508"
  virtual_machine_size           = "Standard_D4s_v5"
  virtual_machine_admin_password = var.virtual_machine_admin_password
  os_disk_disk_size_gb           = 128
  os_disk_storage_account_type   = "Premium_LRS"
  virtual_machine_zone           = "1"

  additional_disks = [
    { volume_name = "sqldata", drive_letter = "e", disk_size_gb = 1024, storage_account_type = "PremiumV2_LRS" },
    { volume_name = "snapshots", drive_letter = "g", disk_size_gb = 256, storage_account_type = "PremiumV2_LRS" },
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

  tag_costcenter   = "20080000"
  tag_businessunit = "First Data Bank"
  tag_product      = "Multilex"
  tag_application  = "rg-20080000-Multilex-Non-Prod"
  tag_environment  = "dev"
  tag_supportteam  = "hts.sre@hearst.com"

  custom_tags = {
    Monitoring      = "Datadog"
    AlertingProfile = "no_alerts"
  }

  post_chef_commands = <<EOT
${file("${path.module}/sql_postconfig_task.ps1")}
EOT
}

data "azurerm_virtual_machine" "sql_vm_hbm044cldtcd508" {
  name                = "hbm044cldtcd508"
  resource_group_name = local.rg_name
  depends_on          = [module.sql_vm_hbm044cldtcd508]
}

resource "azurerm_network_security_group" "vm_nsg_hbm044cldtcd508" {
  name                = "hbm044cldtcd508-nsg"
  location            = local.region
  resource_group_name = local.rg_name
}

locals {
  vm_nic_name_hbm044cldtcd508 = "hbm044cldtcd508_nic"
}

data "azurerm_network_interface" "vm_nic_hbm044cldtcd508" {
  name                = local.vm_nic_name_hbm044cldtcd508
  resource_group_name = local.rg_name
  depends_on          = [module.sql_vm_hbm044cldtcd508]
}

resource "azurerm_network_interface_security_group_association" "vm_nic_nsg_hbm044cldtcd508" {
  network_interface_id      = data.azurerm_network_interface.vm_nic_hbm044cldtcd508.id
  network_security_group_id = azurerm_network_security_group.vm_nsg_hbm044cldtcd508.id
}

resource "azurerm_mssql_virtual_machine" "sql_config_hbm044cldtcd508" {
  virtual_machine_id = data.azurerm_virtual_machine.sql_vm_hbm044cldtcd508.id
  sql_license_type   = "PAYG"

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [data.azurerm_virtual_machine.sql_vm_hbm044cldtcd508]
}

output "vm_id_hbm044cldtcd508" {
  value = data.azurerm_virtual_machine.sql_vm_hbm044cldtcd508.id
}

output "sql_vm_resource_id_hbm044cldtcd508" {
  value = azurerm_mssql_virtual_machine.sql_config_hbm044cldtcd508.id
}


# SQL VM: hbm044cldtcd509 
module "sql_vm_hbm044cldtcd509" {
  source  = "app.terraform.io/hts_automation/vm-windows/azure"
  version = "~> 4.1.0"

  create_resource_group               = false
  resource_group_name                 = local.rg_name
  resource_group_location             = local.region
  virtual_network_name                = "vnet-10.123.52.0_23-southuk"
  virtual_network_resource_group_name = "rg-20080000-Multilex-Non-Prod"
  subnet_name                         = "default"

  virtual_machine_os             = local.vm_os_key
  virtual_machine_name           = "hbm044cldtcd509"
  virtual_machine_size           = "Standard_D4s_v5"
  virtual_machine_admin_password = var.virtual_machine_admin_password
  os_disk_disk_size_gb           = 128
  os_disk_storage_account_type   = "Premium_LRS"
  virtual_machine_zone           = "1"

  additional_disks = [
    { volume_name = "sqldata", drive_letter = "e", disk_size_gb = 1024, storage_account_type = "PremiumV2_LRS" },
    { volume_name = "snapshots", drive_letter = "g", disk_size_gb = 256, storage_account_type = "PremiumV2_LRS" },
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

  tag_costcenter   = "20080000"
  tag_businessunit = "First Data Bank"
  tag_product      = "Multilex"
  tag_application  = "rg-20080000-Multilex-Non-Prod"
  tag_environment  = "dev"
  tag_supportteam  = "hts.sre@hearst.com"

  custom_tags = {
    Monitoring      = "Datadog"
    AlertingProfile = "no_alerts"
  }

  post_chef_commands = <<EOT
${file("${path.module}/sql_postconfig_task.ps1")}
EOT
}

data "azurerm_virtual_machine" "sql_vm_hbm044cldtcd509" {
  name                = "hbm044cldtcd509"
  resource_group_name = local.rg_name
  depends_on          = [module.sql_vm_hbm044cldtcd509]
}

resource "azurerm_network_security_group" "vm_nsg_hbm044cldtcd509" {
  name                = "hbm044cldtcd509-nsg"
  location            = local.region
  resource_group_name = local.rg_name
}

locals {
  vm_nic_name_hbm044cldtcd509 = "hbm044cldtcd509_nic"
}

data "azurerm_network_interface" "vm_nic_hbm044cldtcd509" {
  name                = local.vm_nic_name_hbm044cldtcd509
  resource_group_name = local.rg_name
  depends_on          = [module.sql_vm_hbm044cldtcd509]
}

resource "azurerm_network_interface_security_group_association" "vm_nic_nsg_hbm044cldtcd509" {
  network_interface_id      = data.azurerm_network_interface.vm_nic_hbm044cldtcd509.id
  network_security_group_id = azurerm_network_security_group.vm_nsg_hbm044cldtcd509.id
}

resource "azurerm_mssql_virtual_machine" "sql_config_hbm044cldtcd509" {
  virtual_machine_id = data.azurerm_virtual_machine.sql_vm_hbm044cldtcd509.id
  sql_license_type   = "PAYG"

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [data.azurerm_virtual_machine.sql_vm_hbm044cldtcd509]
}

output "vm_id_hbm044cldtcd509" {
  value = data.azurerm_virtual_machine.sql_vm_hbm044cldtcd509.id
}

output "sql_vm_resource_id_hbm044cldtcd509" {
  value = azurerm_mssql_virtual_machine.sql_config_hbm044cldtcd509.id
}
