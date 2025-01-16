# Configure Terraform providers for PSCompassOne infrastructure deployment
# Implements secure defaults and enhanced security features for cloud providers

terraform {
  required_providers {
    # Azure Resource Manager provider with enhanced security features
    # hashicorp/azurerm ~> 3.0
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    # AWS provider with enhanced security and retry configurations
    # hashicorp/aws ~> 4.0
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }

    # Google Cloud provider with enhanced security and timeout settings
    # hashicorp/google ~> 4.0
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Azure Resource Manager provider configuration
provider "azurerm" {
  features {
    key_vault {
      # Ensure proper key vault security with soft delete protection
      purge_soft_delete_on_destroy = false
      recover_soft_deleted_key_vaults = true
    }
    virtual_machine {
      # Enhanced VM security settings
      delete_os_disk_on_deletion = true
      graceful_shutdown = true
    }
  }

  # Core provider settings
  location = var.azure_location
  environment = var.environment
  
  # Security enhancements
  skip_provider_registration = false
  storage_use_azuread = true
  use_msi = true
  min_tls_version = "1.2"
}

# AWS provider configuration
provider "aws" {
  region = var.aws_region

  # Enhanced security tags for resource tracking
  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "pscompassone"
    }
  }

  # Security and reliability settings
  s3_force_path_style = false
  max_retries = 5
  retry_mode = "adaptive"
}

# Google Cloud provider configuration
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  # Enhanced security settings
  user_project_override = true
  request_timeout = "60s"
  request_reason = true

  # Retry configuration for reliability
  retry_config {
    retry_count = 3
    min_backoff_duration = "1s"
    max_backoff_duration = "30s"
  }
}