# PSCompassOne infrastructure outputs configuration
# Defines secure exports for cross-platform cloud resources
# terraform ~> 1.0

# Azure Key Vault outputs with enhanced security controls
output "azure_key_vault_uri" {
  description = "The URI of the Azure Key Vault for secure credential storage"
  value       = module.azure_key_vault.key_vault_uri
  sensitive   = true

  # Ensure URI format validation
  validation {
    condition     = can(regex("^https://[a-zA-Z0-9-]+\\.vault\\.azure\\.net/$", module.azure_key_vault.key_vault_uri))
    error_message = "Invalid Key Vault URI format"
  }
}

output "azure_key_vault_id" {
  description = "The resource ID of the Azure Key Vault"
  value       = module.azure_key_vault.key_vault_id
  sensitive   = false

  # Validate resource ID format
  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.KeyVault/vaults/[^/]+$", module.azure_key_vault.key_vault_id))
    error_message = "Invalid Key Vault resource ID format"
  }

  depends_on = [
    module.azure_key_vault
  ]
}

# AWS Systems Manager outputs with validation
output "aws_ssm_automation_arn" {
  description = "The ARN of the AWS Systems Manager automation document"
  value       = module.aws_systems_manager.ssm_document_arn
  sensitive   = true

  # Validate ARN format
  validation {
    condition     = can(regex("^arn:aws:ssm:[a-z0-9-]+:[0-9]{12}:document/[a-zA-Z0-9_-]+$", module.aws_systems_manager.ssm_document_arn))
    error_message = "Invalid SSM document ARN format"
  }
}

output "aws_maintenance_window_id" {
  description = "The ID of the AWS Systems Manager maintenance window"
  value       = module.aws_systems_manager.maintenance_window_id
  sensitive   = false

  # Validate maintenance window ID format
  validation {
    condition     = can(regex("^mw-[a-f0-9]{17}$", module.aws_systems_manager.maintenance_window_id))
    error_message = "Invalid maintenance window ID format"
  }

  depends_on = [
    module.aws_systems_manager
  ]
}

# Environment and resource group outputs with validation
output "environment" {
  description = "The current deployment environment"
  value       = var.environment
  sensitive   = false

  # Validate environment value
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

output "resource_group_id" {
  description = "The ID of the Azure resource group containing PSCompassOne resources"
  value       = module.main.resource_group_id
  sensitive   = false

  # Validate resource group ID format
  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", module.main.resource_group_id))
    error_message = "Invalid resource group ID format"
  }

  depends_on = [
    module.main
  ]
}

# Lifecycle management for sensitive outputs
lifecycle {
  # Prevent accidental deletion of sensitive outputs
  prevent_destroy = true

  # Ignore changes to tags and labels
  ignore_changes = [
    tags,
    labels
  ]
}