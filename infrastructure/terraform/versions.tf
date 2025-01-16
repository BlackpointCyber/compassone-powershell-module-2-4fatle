# Terraform version constraints and required provider configuration for PSCompassOne module
# infrastructure deployment across Azure, AWS, and Google Cloud platforms.

terraform {
  # Require Terraform version 1.0 or higher, but less than 2.0
  required_version = "~> 1.0"

  # Configure required providers with specific version constraints
  required_providers {
    # Azure Resource Manager provider for Azure Key Vault and Azure Automation
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    # AWS provider for Systems Manager and Parameter Store integration
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }

    # Google Cloud provider for Cloud Functions and secret management
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}