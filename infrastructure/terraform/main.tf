# PSCompassOne Infrastructure Configuration
# terraform ~> 1.0

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Provider configurations
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.resource_tags
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Local variables for resource configuration
locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Enhanced tags with environment and security metadata
  common_tags = merge(var.resource_tags, {
    Environment         = var.environment
    CreatedBy          = "Terraform"
    LastModified       = timestamp()
    SecurityCompliance = "HIPAA,SOC2"
  })

  # Cross-cloud configuration
  cloud_config = {
    azure = {
      enable_advanced_threat_protection = true
      enable_diagnostic_settings       = true
      network_rules_default_action     = "Deny"
    }
    aws = {
      enable_cloudwatch_logs          = true
      enable_config_recording         = true
      enable_guardduty               = true
    }
    gcp = {
      enable_cloud_audit_logs        = true
      enable_security_command_center = true
      enable_vpc_service_controls    = true
    }
  }
}

# Azure Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.azure_location
  tags     = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

# AWS KMS Key for encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for ${local.name_prefix} encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  tags = local.common_tags
}

# Cross-cloud networking security group
resource "azurerm_network_security_group" "main" {
  name                = "${local.name_prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# Cross-cloud logging configuration
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = "PerGB2018"
  retention_in_days   = 90

  tags = local.common_tags
}

# Outputs for cross-cloud resource references
output "resource_group_id" {
  description = "Azure Resource Group ID"
  value       = azurerm_resource_group.main.id
}

output "environment_name" {
  description = "Deployment Environment Name"
  value       = var.environment
}

output "cross_cloud_config" {
  description = "Cross-cloud Configuration Settings"
  value = {
    azure_resource_group_id = azurerm_resource_group.main.id
    aws_kms_key_arn        = aws_kms_key.main.arn
    log_analytics_id       = azurerm_log_analytics_workspace.main.id
    environment           = var.environment
    cloud_specific        = local.cloud_config
  }
  sensitive = true
}

# Data source for existing cloud resources
data "azurerm_client_config" "current" {}

data "aws_caller_identity" "current" {}

data "google_project" "current" {}

# Cross-cloud security monitoring
resource "azurerm_security_center_subscription_pricing" "main" {
  tier          = "Standard"
  resource_type = "VirtualMachines"
}

resource "aws_securityhub_account" "main" {
  enable_security_hub = true
  
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls     = true
}

# Compliance policy assignments
resource "azurerm_policy_assignment" "security_baseline" {
  name                 = "${local.name_prefix}-security-baseline"
  scope                = azurerm_resource_group.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/1f3afdf9-d0c9-4c3d-847f-89da613e70a8"
  
  parameters = jsonencode({
    effect = {
      value = "Audit"
    }
  })

  identity {
    type = "SystemAssigned"
  }
}