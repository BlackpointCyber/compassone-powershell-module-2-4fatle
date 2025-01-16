# Azure Automation configuration for PSCompassOne PowerShell module
# Provider: azurerm ~> 3.0

# Local variables for Azure Automation configuration
locals {
  automation_account_name = "${var.project_name}-${var.environment}-automation"
  sku_name               = "Basic"
  runbook_type          = "PowerShell"
  module_source_uri     = "https://www.powershellgallery.com/api/v2/package/PSCompassOne"
  identity_type         = "SystemAssigned"
  default_timezone      = "UTC"
  security_tags         = {
    SecurityLevel       = "High"
    DataClassification = "Confidential"
    Compliance         = "HIPAA"
  }
}

# Azure Automation Account with managed identity
resource "azurerm_automation_account" "pscompassone" {
  name                = local.automation_account_name
  location            = var.azure_location
  resource_group_name = var.resource_group_name
  sku_name           = local.sku_name

  identity {
    type = local.identity_type
  }

  tags = merge(var.resource_tags, local.security_tags)
}

# PSCompassOne PowerShell module installation
resource "azurerm_automation_module" "pscompassone" {
  name                    = "PSCompassOne"
  automation_account_name = azurerm_automation_account.pscompassone.name
  resource_group_name     = var.resource_group_name

  module_link {
    uri = local.module_source_uri
  }

  tags = merge(var.resource_tags, {
    ModuleType = "PowerShell"
    Version    = "Latest"
  })
}

# Asset inventory runbook
resource "azurerm_automation_runbook" "asset_inventory" {
  name                    = "Get-AssetInventory"
  automation_account_name = azurerm_automation_account.pscompassone.name
  resource_group_name     = var.resource_group_name
  runbook_type           = local.runbook_type
  description            = "Collects and reports asset inventory using PSCompassOne module"

  content = <<CONTENT
try {
    # Import required modules
    Import-Module PSCompassOne

    # Get Key Vault secrets using managed identity
    $token = Get-AzKeyVaultSecret -VaultName "${data.azurerm_key_vault.pscompassone.name}" -Name "CompassOneToken"
    
    # Connect to CompassOne
    Connect-CompassOne -Token $token.SecretValueText
    
    # Get asset inventory
    $assets = Get-PSCompassOneAsset -Detailed
    
    # Export results
    $assets | Export-Csv -Path "$env:TEMP\AssetInventory.csv" -NoTypeInformation
    
} catch {
    Write-Error "Error in asset inventory collection: $_"
    throw $_
}
CONTENT

  tags = merge(var.resource_tags, {
    RunbookType = "Inventory"
    Schedule    = "Daily"
  })
}

# Security findings runbook
resource "azurerm_automation_runbook" "security_findings" {
  name                    = "Get-SecurityFindings"
  automation_account_name = azurerm_automation_account.pscompassone.name
  resource_group_name     = var.resource_group_name
  runbook_type           = local.runbook_type
  description            = "Collects security findings using PSCompassOne module"

  content = <<CONTENT
try {
    # Import required modules
    Import-Module PSCompassOne
    
    # Get Key Vault secrets using managed identity
    $token = Get-AzKeyVaultSecret -VaultName "${data.azurerm_key_vault.pscompassone.name}" -Name "CompassOneToken"
    
    # Connect to CompassOne
    Connect-CompassOne -Token $token.SecretValueText
    
    # Get security findings
    $findings = Get-PSCompassOneFinding -Severity High
    
    # Process and alert on critical findings
    $criticalFindings = $findings | Where-Object { $_.Severity -eq 'Critical' }
    if ($criticalFindings) {
        Send-AlertNotification -Findings $criticalFindings
    }
    
} catch {
    Write-Error "Error in security findings collection: $_"
    throw $_
}
CONTENT

  tags = merge(var.resource_tags, {
    RunbookType = "Security"
    Schedule    = "Hourly"
  })
}

# Daily inventory schedule
resource "azurerm_automation_schedule" "daily_inventory" {
  name                    = "daily-inventory"
  automation_account_name = azurerm_automation_account.pscompassone.name
  resource_group_name     = var.resource_group_name
  frequency              = "Day"
  interval               = 1
  timezone               = local.default_timezone
  description            = "Daily schedule for asset inventory collection"

  tags = merge(var.resource_tags, {
    ScheduleType = "Daily"
    RunbookName  = azurerm_automation_runbook.asset_inventory.name
  })
}

# Hourly security findings schedule
resource "azurerm_automation_schedule" "hourly_findings" {
  name                    = "hourly-findings"
  automation_account_name = azurerm_automation_account.pscompassone.name
  resource_group_name     = var.resource_group_name
  frequency              = "Hour"
  interval               = 1
  timezone               = local.default_timezone
  description            = "Hourly schedule for security findings collection"

  tags = merge(var.resource_tags, {
    ScheduleType = "Hourly"
    RunbookName  = azurerm_automation_runbook.security_findings.name
  })
}

# Data source for Key Vault reference
data "azurerm_key_vault" "pscompassone" {
  name                = "${var.project_name}-${var.environment}-kv"
  resource_group_name = var.resource_group_name
}

# Outputs for reference in other resources
output "automation_account_id" {
  description = "Azure Automation account ID"
  value       = azurerm_automation_account.pscompassone.id
}

output "automation_account_name" {
  description = "Azure Automation account name"
  value       = azurerm_automation_account.pscompassone.name
}

output "automation_principal_id" {
  description = "Managed identity principal ID"
  value       = azurerm_automation_account.pscompassone.identity[0].principal_id
}