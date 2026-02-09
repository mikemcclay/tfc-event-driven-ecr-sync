# =============================================================================
# INPUT VARIABLES
# =============================================================================

variable "region" {
  description = "AWS region where resources will be deployed"
  type        = string
}

variable "appenv" {
  description = "Environment name / image tag to trigger syncs for (e.g., 'dev', 'staging', 'prod')"
  type        = string
}

variable "lambda_name" {
  description = "Name prefix for the Lambda function and associated resources"
  type        = string
  default     = "ecr-image-sync"
}

variable "source_account_id" {
  description = "AWS account ID where the source ECR repository lives"
  type        = string
}

variable "source_region" {
  description = "AWS region of the source ECR repository"
  type        = string
}

variable "destination_account_id" {
  description = "AWS account ID for the destination ECR repository"
  type        = string
}

variable "destination_region" {
  description = "AWS region of the destination ECR repository"
  type        = string
}

variable "repo_name" {
  description = "Name of the ECR repository (must exist in both source and destination accounts)"
  type        = string
}
