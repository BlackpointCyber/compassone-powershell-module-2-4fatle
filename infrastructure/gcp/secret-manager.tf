# Google Cloud Secret Manager configuration for PSCompassOne
# Provider: hashicorp/google ~> 4.0

# Local variables for enhanced secret management configuration
locals {
  secret_prefix = "pscompassone-${var.environment}"
  
  # Enhanced security controls for secret management
  security_controls = {
    deletion_protection = true
    version_retention  = "30d"
    max_versions      = 10
    
    # Audit configuration
    audit_config = {
      log_type     = "DATA_READ"
      exempted_members = []
    }
    
    # Default labels merged with resource tags
    labels = merge(var.resource_tags, var.secret_labels, {
      environment         = var.environment
      secret-type        = "api-credentials"
      rotation-required  = "true"
      encryption-type    = "cmek"
    })
  }
}

# Secret Manager secret with enhanced security controls
resource "google_secret_manager_secret" "pscompassone_secrets" {
  secret_id = "${local.secret_prefix}-credentials"
  project   = var.gcp_project_id

  # Multi-region replication configuration
  replication {
    dynamic "user_managed" {
      for_each = var.secret_replication_policy.user_managed[*]
      content {
        dynamic "replicas" {
          for_each = user_managed.value.replicas
          content {
            location = replicas.value.location
            customer_managed_encryption {
              kms_key_name = replicas.value.customer_managed_encryption.kms_key_name
            }
          }
        }
      }
    }
  }

  # Version control configuration
  version_aliases = {
    "latest" = "latest"
  }

  # Enhanced security controls
  labels = local.security_controls.labels

  # Deletion protection
  deletion_policy = local.security_controls.deletion_protection ? "DELETE_PROTECTION" : "DELETE"
}

# IAM binding for secret access with principle of least privilege
resource "google_secret_manager_secret_iam_binding" "secret_accessor" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.pscompassone_secrets.secret_id
  role      = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:${var.gcp_project_id}@appspot.gserviceaccount.com",
  ]

  condition {
    title       = "secret_access_condition"
    description = "Restricts access to specific environments and services"
    expression  = "resource.type == 'secretmanager.googleapis.com/Secret' && resource.name.startsWith('projects/${var.gcp_project_id}/secrets/${local.secret_prefix}')"
  }
}

# IAM binding for secret administration
resource "google_secret_manager_secret_iam_binding" "secret_admin" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.pscompassone_secrets.secret_id
  role      = "roles/secretmanager.admin"

  members = [
    "group:pscompassone-admins@${var.gcp_project_id}.iam.gserviceaccount.com",
  ]

  condition {
    title       = "secret_admin_condition"
    description = "Restricts admin access to specific security groups"
    expression  = "resource.type == 'secretmanager.googleapis.com/Secret' && resource.name.startsWith('projects/${var.gcp_project_id}/secrets/${local.secret_prefix}')"
  }
}

# Output secret information for module configuration
output "secret_manager_id" {
  description = "The ID of the Secret Manager secret"
  value = {
    id           = google_secret_manager_secret.pscompassone_secrets.id
    kms_key_name = google_secret_manager_secret.pscompassone_secrets.replication[0].user_managed[0].replicas[0].customer_managed_encryption[0].kms_key_name
  }
  sensitive = true
}

output "secret_name" {
  description = "The name and version of the secret"
  value = {
    name    = google_secret_manager_secret.pscompassone_secrets.name
    version = "latest"
  }
  sensitive = true
}

# Variables for secret configuration
variable "secret_replication_policy" {
  description = "Enhanced replication configuration with multi-region support"
  type = object({
    automatic = bool
    user_managed = object({
      replicas = list(object({
        location = string
        customer_managed_encryption = object({
          kms_key_name = string
        })
      }))
    })
  })
  default = {
    automatic = false
    user_managed = {
      replicas = [
        {
          location = "us-central1"
          customer_managed_encryption = {
            kms_key_name = ""
          }
        },
        {
          location = "us-east1"
          customer_managed_encryption = {
            kms_key_name = ""
          }
        }
      ]
    }
  }
}

variable "secret_labels" {
  description = "Comprehensive labels for security and compliance tracking"
  type        = map(string)
  default = {
    managed-by           = "terraform"
    module              = "pscompassone"
    data-classification = "sensitive"
    compliance-required = "true"
    security-level      = "high"
    audit-enabled       = "true"
  }
}