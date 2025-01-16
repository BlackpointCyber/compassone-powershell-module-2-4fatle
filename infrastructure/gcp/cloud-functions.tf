# Google Cloud Functions configuration for PSCompassOne PowerShell module automation
# Provider: hashicorp/google ~> 4.0

# Import required provider configuration
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Cloud Function for PSCompassOne automation with enhanced security and monitoring
resource "google_cloudfunctions_function" "pscompassone_automation" {
  name                  = "pscompassone-automation-${var.environment}"
  description           = "Secure Cloud Function for PSCompassOne automation tasks with enhanced monitoring"
  runtime               = "powershell"
  available_memory_mb   = 256
  timeout              = 540
  entry_point          = "Invoke-PSCompassOneAutomation"
  project              = var.gcp_project_id
  region               = var.gcp_region

  # Environment variables for configuration and security
  environment_variables = {
    ENVIRONMENT         = var.environment
    SECRET_MANAGER_KEY  = google_secret_manager_secret.api_key.name
    FUNCTION_REGION     = var.gcp_region
    LOG_LEVEL          = "Information"
    ENABLE_MONITORING  = "true"
    MAX_RETRY_ATTEMPTS = "3"
    EXECUTION_TIMEOUT  = "500"
  }

  # Service account for secure execution
  service_account_email = "pscompassone-sa@${var.gcp_project_id}.iam.gserviceaccount.com"

  # Source code repository configuration
  source_repository {
    url     = "https://source.developers.google.com/projects/${var.gcp_project_id}/repos/pscompassone/moveable-aliases/main"
    branch  = var.environment
  }

  # Comprehensive resource labels for tracking and compliance
  labels = {
    environment         = var.environment
    managed-by         = "terraform"
    module             = "pscompassone"
    security-level     = "high"
    data-classification = "sensitive"
    compliance         = "hipaa"
  }

  # Enhanced security settings
  vpc_connector        = "projects/${var.gcp_project_id}/locations/${var.gcp_region}/connectors/pscompassone-vpc"
  ingress_settings     = "ALLOW_INTERNAL_ONLY"
  security_level       = "secure-always"
}

# IAM binding for function invocation with security conditions
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.gcp_project_id
  region         = var.gcp_region
  cloud_function = google_cloudfunctions_function.pscompassone_automation.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:pscompassone-sa@${var.gcp_project_id}.iam.gserviceaccount.com"

  # Conditional access for enhanced security
  condition {
    title       = "secure_function_access"
    description = "Restrict function access to internal VPC"
    expression  = "request.origin.tag == 'internal-vpc'"
  }
}

# Output function details for monitoring and access
output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.pscompassone_automation.name
}

output "function_uri" {
  description = "The HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.pscompassone_automation.https_trigger_url
  sensitive   = true
}

output "function_status" {
  description = "The deployment status of the Cloud Function"
  value       = google_cloudfunctions_function.pscompassone_automation.status
}