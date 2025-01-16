# Terraform variables for PSCompassOne infrastructure deployment
# terraform ~> 1.0

# Environment configuration with strict validation
variable "environment" {
  description = "Deployment environment (dev, staging, prod) with strict validation"
  type        = string
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod"
  }
}

# Project naming configuration with format validation
variable "project_name" {
  description = "Project name for resource naming with validation"
  type        = string
  default     = "pscompassone"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_name))
    error_message = "Project name must be 3-25 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens"
  }
}

# Azure configuration
variable "azure_location" {
  description = "Azure region for resource deployment with format validation"
  type        = string
  validation {
    condition     = can(regex("^[a-z]+[a-z0-9]+$", var.azure_location))
    error_message = "Azure location must be a valid region name in lowercase"
  }
}

# AWS configuration
variable "aws_region" {
  description = "AWS region for resource deployment with strict format validation"
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-east-1)"
  }
}

# GCP configuration
variable "gcp_region" {
  description = "GCP region for resource deployment with format validation"
  type        = string
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+\\d$", var.gcp_region))
    error_message = "GCP region must be a valid region identifier (e.g., us-central1)"
  }
}

variable "gcp_project_id" {
  description = "GCP project ID for resource deployment with format validation"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{5,29}$", var.gcp_project_id))
    error_message = "GCP project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens"
  }
}

# Common resource tagging with security metadata
variable "resource_tags" {
  description = "Common resource tags for all deployed resources including security metadata"
  type        = map(string)
  default = {
    Module              = "PSCompassOne"
    ManagedBy          = "Terraform"
    SecurityLevel      = "High"
    ComplianceRequired = "True"
    DataClassification = "Sensitive"
  }
}

# Service enablement flags with security features
variable "enable_key_vault" {
  description = "Flag to enable Azure Key Vault deployment with security features"
  type        = bool
  default     = true
}

variable "enable_systems_manager" {
  description = "Flag to enable AWS Systems Manager deployment with security features"
  type        = bool
  default     = true
}

variable "enable_cloud_functions" {
  description = "Flag to enable GCP Cloud Functions deployment with security features"
  type        = bool
  default     = true
}