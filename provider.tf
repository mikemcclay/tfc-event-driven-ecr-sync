# =============================================================================
# TERRAFORM CLOUD MULTI-ACCOUNT PROVIDER CONFIGURATION
# =============================================================================
# This configuration demonstrates how to use Terraform Cloud's dynamic 
# credentials to deploy resources across multiple AWS accounts in a single
# workspace.
#
# Required TFC workspace environment variables:
#   - TFC_AWS_PROVIDER_AUTH = true
#   - TFC_AWS_RUN_ROLE_ARN = <role-arn-for-destination-account>
#   - TFC_AWS_PROVIDER_AUTH_ECR = true  
#   - TFC_AWS_RUN_ROLE_ARN_ECR = <role-arn-for-source-account>
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# TFC Dynamic Credentials Variable
# -----------------------------------------------------------------------------
# Terraform Cloud automatically populates this variable when dynamic 
# credentials are configured. It contains the paths to temporary credential
# files for each provider alias.
# -----------------------------------------------------------------------------
variable "tfc_aws_dynamic_credentials" {
  description = "Object containing AWS dynamic credentials configuration (auto-populated by TFC)"
  type = object({
    default = object({
      shared_config_file = string
    })
    aliases = map(object({
      shared_config_file = string
    }))
  })
}

# -----------------------------------------------------------------------------
# Default Provider - DESTINATION Account
# -----------------------------------------------------------------------------
# Resources without an explicit provider will be created here.
# This is where our Lambda function lives.
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.region
  shared_config_files = [
    var.tfc_aws_dynamic_credentials.default.shared_config_file,
  ]
}

# -----------------------------------------------------------------------------
# Aliased Provider - SOURCE Account (ECR)
# -----------------------------------------------------------------------------
# Resources with `provider = aws.ecr` will be created here.
# This is where the ECR repository and EventBridge rule live.
#
# Note: The alias name "ecr" in Terraform maps to the "ECR" suffix in the
# TFC environment variable (TFC_AWS_RUN_ROLE_ARN_ECR). The mapping is:
#   - Provider alias: aws.ecr
#   - TFC variable suffix: _ECR (case-insensitive match)
# -----------------------------------------------------------------------------
provider "aws" {
  alias  = "ecr"
  region = var.region
  shared_config_files = [
    var.tfc_aws_dynamic_credentials.aliases["ECR"].shared_config_file,
  ]
}
