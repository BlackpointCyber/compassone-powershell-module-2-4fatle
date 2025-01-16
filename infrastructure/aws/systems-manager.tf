# AWS Systems Manager configuration for PSCompassOne PowerShell module
# AWS Provider ~> 4.0

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local variables for resource naming
locals {
  automation_prefix = "${var.project_name}-${var.environment}"
}

# SSM Automation document for PowerShell script execution
resource "aws_ssm_document" "pscompassone_automation" {
  name            = "${var.project_name}-${var.environment}-automation"
  document_type   = "Automation"
  document_format = "YAML"
  
  content = <<DOC
schemaVersion: '0.3'
description: 'Automation document for PSCompassOne PowerShell module'
parameters:
  ScriptPath:
    type: String
    description: Path to PowerShell script
  KmsKeyId:
    type: String
    description: KMS key for encryption
    default: ''
mainSteps:
  - name: runPowerShellScript
    action: 'aws:runPowerShellScript'
    inputs:
      runCommand:
        - pwsh -File '{{ScriptPath}}'
      cloudWatchOutputConfig:
        CloudWatchOutputEnabled: true
      cloudWatchEncryptionEnabled: true
      kmsKeyId: '{{KmsKeyId}}'
DOC

  tags = merge(var.resource_tags, {
    Name = "${var.project_name}-${var.environment}-automation"
    Type = "SSMDocument"
  })
}

# Maintenance window for scheduled automation
resource "aws_ssm_maintenance_window" "pscompassone_window" {
  name                       = "${var.project_name}-${var.environment}-maintenance-window"
  schedule                   = "cron(0 0 ? * SUN *)"  # Weekly on Sunday at midnight
  duration                   = "PT4H"                 # 4 hour duration
  allow_unassociated_targets = true
  cutoff                     = "PT1H"                # Stop scheduling new tasks 1 hour before end

  tags = merge(var.resource_tags, {
    Name   = "${var.project_name}-${var.environment}-maintenance-window"
    Module = "PSCompassOne"
  })
}

# SSM association for automation execution
resource "aws_ssm_association" "pscompassone_association" {
  name = aws_ssm_document.pscompassone_automation.name

  parameters = {
    ScriptPath = "/opt/pscompassone/scripts/maintenance.ps1"
    KmsKeyId   = aws_kms_key.pscompassone_key.id
  }

  targets {
    key    = "tag:Module"
    values = ["PSCompassOne"]
  }

  automation_target_parameter_name = "InstanceIds"
  max_concurrency                 = "50%"
  max_errors                      = "10%"

  depends_on = [aws_ssm_document.pscompassone_automation]
}

# KMS key for script output encryption
resource "aws_kms_key" "pscompassone_key" {
  description             = "KMS key for PSCompassOne Systems Manager automation"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Systems Manager to use the key"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.resource_tags, {
    Name = "${var.project_name}-${var.environment}-ssm-key"
  })
}

# KMS alias for easier key reference
resource "aws_kms_alias" "pscompassone_key_alias" {
  name          = "alias/${var.project_name}-${var.environment}-ssm"
  target_key_id = aws_kms_key.pscompassone_key.key_id
}

# Outputs for reference in other modules
output "ssm_document_arn" {
  description = "ARN of the Systems Manager automation document"
  value       = aws_ssm_document.pscompassone_automation.arn
}

output "maintenance_window_id" {
  description = "ID of the Systems Manager maintenance window"
  value       = aws_ssm_maintenance_window.pscompassone_window.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for Systems Manager encryption"
  value       = aws_kms_key.pscompassone_key.arn
}