# Azure Key Vault configuration for PSCompassOne module
# Provider: azurerm ~> 3.0

# Local variables for enhanced Key Vault configuration
locals {
  key_vault_name = lower("kv-${var.project_name}-${var.environment}")
  
  key_vault_config = {
    retention_days = var.soft_delete_retention_days
    network_rules = {
      default_action = "Deny"
      bypass        = ["AzureServices"]
      ip_rules      = []
      virtual_network_subnet_ids = []
    }
    monitoring = {
      retention_days = 30
      categories = ["AuditEvent", "AzurePolicyEvaluationDetails"]
    }
  }
}

# Key Vault resource with enhanced security features
resource "azurerm_key_vault" "pscompassone" {
  name                = local.key_vault_name
  location            = var.azure_location
  resource_group_name = data.azurerm_resource_group.main.name
  tenant_id          = data.azurerm_client_config.current.tenant_id
  sku_name           = var.key_vault_sku

  # Enhanced security features
  enable_rbac_authorization   = var.enable_rbac_authorization
  purge_protection_enabled    = true
  soft_delete_retention_days  = local.key_vault_config.retention_days
  enabled_for_disk_encryption = true
  
  # Network security rules
  network_acls {
    default_action             = local.key_vault_config.network_rules.default_action
    bypass                     = local.key_vault_config.network_rules.bypass
    ip_rules                   = local.key_vault_config.network_rules.ip_rules
    virtual_network_subnet_ids = local.key_vault_config.network_rules.virtual_network_subnet_ids
  }

  tags = merge(var.resource_tags, {
    Service     = "KeyVault"
    Environment = var.environment
  })
}

# Private endpoint for secure network access
resource "azurerm_private_endpoint" "key_vault" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "pe-${local.key_vault_name}"
  location            = var.azure_location
  resource_group_name = data.azurerm_resource_group.main.name
  subnet_id           = data.azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-${local.key_vault_name}"
    private_connection_resource_id = azurerm_key_vault.pscompassone.id
    is_manual_connection          = false
    subresource_names            = ["vault"]
  }

  tags = merge(var.resource_tags, {
    Service     = "KeyVault-PrivateEndpoint"
    Environment = var.environment
  })
}

# Diagnostic settings for monitoring and auditing
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${local.key_vault_name}"
  target_resource_id         = azurerm_key_vault.pscompassone.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.main.id

  dynamic "log" {
    for_each = local.key_vault_config.monitoring.categories
    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = true
        days    = local.key_vault_config.monitoring.retention_days
      }
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true
    retention_policy {
      enabled = true
      days    = local.key_vault_config.monitoring.retention_days
    }
  }
}

# RBAC role assignments for Key Vault access
resource "azurerm_role_assignment" "key_vault_admin" {
  count                = var.enable_rbac_authorization ? 1 : 0
  scope                = azurerm_key_vault.pscompassone.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Outputs for dependent resources
output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.pscompassone.id
  sensitive   = false
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.pscompassone.vault_uri
  sensitive   = false
}

output "private_endpoint_ip" {
  description = "The private IP address of the Key Vault private endpoint"
  value       = var.enable_private_endpoint ? azurerm_private_endpoint.key_vault[0].private_service_connection[0].private_ip_address : null
  sensitive   = false
}