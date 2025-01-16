# Backend configuration for PSCompassOne Terraform state management
# terraform ~> 1.0

terraform {
  # Configure Azure Storage Account backend with enhanced security features
  backend "azurerm" {
    # Environment-specific resource group and storage account naming
    resource_group_name  = "${var.environment}-pscompassone-tfstate-rg"
    storage_account_name = "${var.environment}pscompassonetf"
    container_name      = "terraform-state"
    key                 = "pscompassone.tfstate"

    # Enhanced security features
    use_azuread_auth        = true
    use_oidc               = true
    enable_blob_encryption = true
    use_microsoft_graph    = true

    # Additional security configurations
    min_tls_version       = "TLS1_2"
    enable_https_traffic_only = true
    allow_blob_public_access = false

    # State locking configuration
    lock_enabled = true
    lock_timeout = "5m"

    # Backup and versioning
    versioning_enabled = true
    backup_enabled    = true
    backup_retention  = 30

    # Network security
    ip_rules = []
    virtual_network_subnet_ids = []
  }
}

# Local backend configuration for development environments
locals {
  backend_config = {
    environment_prefix = var.environment
    state_file_name   = "pscompassone.tfstate"
    backup_retention_days = 30
    allowed_ip_ranges = []
  }
}

# Backend configuration validation
check "backend_validation" {
  assert {
    condition     = var.environment != ""
    error_message = "Environment variable must be set for backend configuration."
  }

  assert {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

# Backend security policy
locals {
  security_policy = {
    enforce_https           = true
    min_tls_version        = "TLS1_2"
    enable_blob_encryption = true
    enable_versioning      = true
    enable_soft_delete     = true
    soft_delete_days       = 7
    network_rules = {
      default_action = "Deny"
      bypass        = ["AzureServices"]
      ip_rules      = []
      subnet_ids    = []
    }
  }
}