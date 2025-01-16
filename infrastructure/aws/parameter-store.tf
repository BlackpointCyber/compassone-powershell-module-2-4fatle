# AWS Systems Manager Parameter Store Configuration for PSCompassOne
# aws provider ~> 4.0

locals {
  # Parameter Store path hierarchy with environment segmentation
  parameter_path_prefix = "/pscompassone/${var.environment}"

  # Parameter tier mapping with validation
  parameter_tier_mapping = {
    credentials   = "Advanced"    # For sensitive credentials and secrets
    configuration = "Standard"    # For general configuration
    audit        = "Standard"    # For audit trail data
  }

  # Enhanced parameter tags with security metadata
  parameter_tags = merge(var.resource_tags, {
    ParameterType     = "SecureConfig"
    SecurityZone      = "HighSecurity"
    DataProtection   = "Encryption"
    ComplianceScope  = "SecurityControls"
    LastModifiedBy   = "Terraform"
  })

  # KMS encryption configuration
  kms_encryption_required = true
}

# Parameter Store configuration for API credentials
resource "aws_ssm_parameter" "api_key" {
  name        = "${local.parameter_path_prefix}/credentials/api_key"
  description = "CompassOne API Key - Encrypted with KMS"
  type        = "SecureString"
  value       = "dummy-value" # Actual value should be injected via automation
  tier        = local.parameter_tier_mapping["credentials"]
  key_id      = data.aws_kms_key.parameter_encryption.id
  overwrite   = true

  tags = merge(local.parameter_tags, {
    CredentialType = "APIKey"
    RotationRequired = "True"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

# Module configuration parameters
resource "aws_ssm_parameter" "module_config" {
  name        = "${local.parameter_path_prefix}/configuration/module_settings"
  description = "PSCompassOne Module Configuration Settings"
  type        = "SecureString"
  value       = jsonencode({
    api_endpoint     = "https://api.compassone.com"
    timeout_seconds  = 30
    retry_attempts   = 3
    log_level       = "Info"
  })
  tier        = local.parameter_tier_mapping["configuration"]
  key_id      = data.aws_kms_key.parameter_encryption.id
  overwrite   = true

  tags = merge(local.parameter_tags, {
    ConfigType = "ModuleSettings"
    UpdateFrequency = "AsNeeded"
  })
}

# Audit trail configuration
resource "aws_ssm_parameter" "audit_config" {
  name        = "${local.parameter_path_prefix}/audit/settings"
  description = "Audit Trail Configuration for PSCompassOne"
  type        = "SecureString"
  value       = jsonencode({
    audit_enabled   = true
    log_retention   = 90
    detail_level    = "Full"
    include_debug   = false
  })
  tier        = local.parameter_tier_mapping["audit"]
  key_id      = data.aws_kms_key.parameter_encryption.id
  overwrite   = true

  tags = merge(local.parameter_tags, {
    AuditType = "SecurityLogging"
    RetentionPolicy = "90Days"
  })
}

# Reference existing KMS key for parameter encryption
data "aws_kms_key" "parameter_encryption" {
  key_id = "alias/pscompassone-parameter-encryption"
}

# Output parameter store configuration for cross-module reference
output "parameter_store_config" {
  description = "Parameter Store configuration details"
  value = {
    path_prefix = local.parameter_path_prefix
    environment = var.environment
    parameters = {
      api_key_arn     = aws_ssm_parameter.api_key.arn
      config_arn      = aws_ssm_parameter.module_config.arn
      audit_arn       = aws_ssm_parameter.audit_config.arn
    }
  }
  sensitive = true
}

# Output parameter path prefix for module configuration
output "parameter_path_prefix" {
  description = "Parameter Store path prefix for module configuration"
  value = {
    prefix      = local.parameter_path_prefix
    environment = var.environment
  }
}