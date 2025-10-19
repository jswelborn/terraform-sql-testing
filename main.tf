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

###############################################################
#  HTS SQL 2025 Windows VM — Chef-safe, Persistent Post-Config
###############################################################

locals {
  vm_os_key = "server2022" # appease module validation
  vm_name   = "htsjswsql001"
  rg_name   = "rg-80020000-htsjswsql001"
  region    = "eastus"

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

###############################################################
#  VM Definition (via HTS Automation Windows module)
###############################################################
module "sql_vm" {
  source  = "app.terraform.io/hts_automation/vm-windows/azure"
  version = "~> 3.0.0"

  # --- Environment info ---
  resource_group_name                 = local.rg_name
  resource_group_location             = local.region
  virtual_network_name                = "ht-hts-eastus-vnet1"
  virtual_network_resource_group_name = "ht-hts-eastus-core-rg"
  subnet_name                         = "ht-hts-eastus-utilityservices-app-prod-subnet-private"

  # --- OS Info ---
  virtual_machine_os = local.vm_os_key
  virtual_machine_os_details = {
    server2022 = {
      publisher = "MicrosoftSQLServer"
      offer     = "SQL2025-WS2025"
      sku       = "stddev-gen2"
      version   = "latest"
    }
  }

  # --- VM Info ---
  virtual_machine_name           = local.vm_name
  virtual_machine_size           = "Standard_D8s_v5"
  virtual_machine_admin_password = var.virtual_machine_admin_password
  os_disk_disk_size_gb           = 256

  additional_disks = [
    { volume_name = "sqldata", drive_letter = "f", disk_size_gb = 256 },
    { volume_name = "sqllogs", drive_letter = "g", disk_size_gb = 128 },
  ]

  # --- Chef Configuration ---
  chef_version               = "18.7.6"
  policy_name                = "hts_chef_base_node_pf"
  policy_group               = "staging"
  chef_client_action         = "run"
  domain_name                = "companynet.org"
  chef_validation_pem_base64 = var.chef_validation_pem_base64
  databag_secret_key         = var.databag_secret_key
  user_key_base64            = var.user_key_base64

  # --- Azure AD/DNS automation ---
  ad_dns_operations_app_runbook_url   = var.ad_dns_operations_app_runbook_url
  tfc_worker_azure_private_key_base64 = var.tfc_worker_azure_private_key_base64

  # --- Tags ---
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

  ##################################################################
  # Persisted SYSTEM Startup Task — Executes After Chef & Domain Join
  ##################################################################
  post_chef_commands = <<EOT
Write-Host "=== Persisting SQL post-config as SYSTEM startup task ==="
$ErrorActionPreference = 'Stop'

$rootDir    = "${local.hts_root}"
$scriptsDir = "${local.hts_scripts}"
$markersDir = "${local.hts_markers}"
$tempDir    = "${local.temp_dir}"

New-Item -ItemType Directory -Path $rootDir -Force | Out-Null
New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
New-Item -ItemType Directory -Path $markersDir -Force | Out-Null
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$wrapperPath = Join-Path $scriptsDir "${local.wrapper_name}"
$mainPath    = Join-Path $scriptsDir "${local.main_name}"
$doneFlag    = Join-Path $markersDir "${local.done_flag}"
$wrapperLog  = Join-Path $tempDir   "sql_post_config.wrapper.log"
$mainLog     = Join-Path $tempDir   "sql_post_config.main.log"

# --- Wrapper Script (idempotent + retry-safe) ---
$wrapper = @"
`$ErrorActionPreference = 'Stop'
function Log([string]`$m){ `$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "`$ts :: `$m" | Tee-Object -FilePath "$wrapperLog" -Append | Out-Null }
try {
  Log "Wrapper starting (SYSTEM context expected)."
  if (Test-Path "$doneFlag") {
    Log "Done-flag present; exiting without action."
    exit 0
  }

  Log "Fetching latest main script to $mainPath"
  Invoke-WebRequest -UseBasicParsing -Uri "${local.main_uri}" -OutFile "$mainPath"

  Log "Launching main script"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$mainPath" *>> "$mainLog"
  `$exit = `$LASTEXITCODE
  Log "Main script exit code: `$exit"

  if (`$exit -eq `$null -or `$exit -eq 0) {
    Log "Main script succeeded; writing done-flag and disabling task."
    New-Item -ItemType File -Path "$doneFlag" -Force | Out-Null
    try { Disable-ScheduledTask -TaskName "${local.task_name}" -ErrorAction Stop | Out-Null } catch { Log "Disable failed: `$($_.Exception.Message)" }
    exit 0
  } else {
    Log "Main script failed (code=`$exit); will retry next boot."
    exit `$exit
  }
}
catch {
  Log "Wrapper error: `$($_.Exception.Message)"
  exit 1
}
"@
$wrapper | Set-Content -Path $wrapperPath -Encoding UTF8

# --- Register SYSTEM Task (XML delay-safe variant) ---
try {
  $action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""
  $trigger   = New-ScheduledTaskTrigger -AtStartup
  $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
  $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

  $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
  $xml = "$env:TEMP\\HTS_SQL_PostConfig_OnStartup.xml"
  $task | Export-ScheduledTask | Set-Content $xml
  (Get-Content $xml) -replace '</BootTrigger>', '<Delay>PT2M</Delay></BootTrigger>' | Set-Content $xml
  Register-ScheduledTask -TaskName "${local.task_name}" -Xml (Get-Content $xml | Out-String) -Force | Out-Null
  Remove-Item $xml -ErrorAction SilentlyContinue
  Write-Host "Startup task registered successfully (2m delay)."
  Start-ScheduledTask -TaskName "${local.task_name}"
}
catch {
  Write-Host "Warning: failed to register/start scheduled task: $($_.Exception.Message)"
}
Write-Host "=== Persisted startup task registration complete ==="
exit 0
EOT
}

###############################################################
# Lookup the VM to attach SQL IaaS configuration
###############################################################
data "azurerm_virtual_machine" "sql_vm" {
  name                = local.vm_name
  resource_group_name = local.rg_name
  depends_on          = [module.sql_vm]
}

###############################################################
# Register the SQL VM with Azure SQL IaaS
###############################################################
resource "azurerm_mssql_virtual_machine" "sql_config" {
  virtual_machine_id = data.azurerm_virtual_machine.sql_vm.id
  sql_license_type   = "PAYG"

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [data.azurerm_virtual_machine.sql_vm]
}

###############################################################
# Outputs (optional)
###############################################################
output "vm_id" {
  value = data.azurerm_virtual_machine.sql_vm.id
}

output "sql_vm_resource_id" {
  value = azurerm_mssql_virtual_machine.sql_config.id
}
