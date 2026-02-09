# Cross-Account ECR Image Sync with Terraform Cloud

This example demonstrates how to build **event-driven, cross-account architecture** using Terraform Cloud's dynamic credentials feature and AWS EventBridge.

## Architecture Overview

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│         SOURCE ACCOUNT              │     │       DESTINATION ACCOUNT           │
│         (aws.ecr provider)          │     │       (default provider)            │
│                                     │     │                                     │
│  ┌─────────────┐                    │     │                                     │
│  │  ECR Repo   │                    │     │  ┌─────────────┐                    │
│  │  (push)     │                    │     │  │  ECR Repo   │                    │
│  └──────┬──────┘                    │     │  │  (synced)   │                    │
│         │ ECR Push Event            │     │  └──────▲──────┘                    │
│         ▼                           │     │         │                           │
│  ┌─────────────────┐                │     │         │ Push Image                │
│  │  EventBridge    │                │     │  ┌──────┴──────┐                    │
│  │  Rule           │                │     │  │   Lambda    │                    │
│  └────────┬────────┘                │     │  │  Function   │                    │
│           │                         │     │  └──────▲──────┘                    │
│           │ Cross-account invoke    │     │         │                           │
│  ┌────────▼────────┐                │     │  ┌──────┴──────┐                    │
│  │  EventBridge    │────────────────┼─────┼─▶│   Lambda    │                    │
│  │  Target + Role  │                │     │  │  Permission │                    │
│  └─────────────────┘                │     │  └─────────────┘                    │
│                                     │     │                                     │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

## How It Works

1. **Image Push**: A new image is pushed to the ECR repository in the source account
2. **Event Capture**: EventBridge in the source account captures the ECR push event
3. **Cross-Account Invoke**: EventBridge invokes a Lambda function in the destination account
4. **Image Sync**: The Lambda pulls the image from source and pushes to destination ECR

## Key Cross-Account Components

### Source Account Resources (`provider = aws.ecr`)
- **EventBridge Rule**: Captures ECR image push events
- **EventBridge Target**: Points to the Lambda in the destination account
- **IAM Role**: Allows EventBridge to invoke the cross-account Lambda

### Destination Account Resources (default provider)
- **Lambda Function**: Handles the image copy logic
- **Lambda Permission**: Allows the source account's EventBridge to invoke it
- **IAM Role**: Permissions for ECR operations and CloudWatch Logs

## Terraform Cloud Setup

This example uses **Terraform Cloud Dynamic Credentials** to authenticate to multiple AWS accounts from a single workspace.

### Required TFC Configuration

1. **Configure OIDC trust** in both AWS accounts pointing to your TFC organization
2. **Set up workspace variables**:
   - `TFC_AWS_PROVIDER_AUTH = true`
   - `TFC_AWS_RUN_ROLE_ARN` = Role ARN for destination account (default provider)
   - `TFC_AWS_PROVIDER_AUTH_ECR = true` 
   - `TFC_AWS_RUN_ROLE_ARN_ECR` = Role ARN for source account (aws.ecr provider)

The provider aliases in Terraform (`aws.ecr`) map to environment variable suffixes (`_ECR`).

## Prerequisites

- Terraform Cloud workspace with dynamic credentials configured
- OIDC identity providers in both AWS accounts
- IAM roles in both accounts trusting TFC's OIDC provider
- ECR repositories existing in both accounts with matching names

## Usage

1. Configure your Terraform Cloud workspace with the required variables
2. Create a `terraform.tfvars` file (see `example.tfvars`)
3. Run `terraform plan` and `terraform apply`

## Variables

| Name | Description |
|------|-------------|
| `region` | AWS region for resources |
| `appenv` | Environment/image tag to trigger on (e.g., "dev", "prod") |
| `lambda_name` | Name for the Lambda function and related resources |
| `source_account_id` | AWS account ID where ECR source repository lives |
| `source_region` | Region of the source ECR repository |
| `destination_account_id` | AWS account ID for the destination ECR repository |
| `destination_region` | Region of the destination ECR repository |
| `repo_name` | Name of the ECR repository (must exist in both accounts) |

## Important Notes

### How the Image Sync Works
The Lambda uses the ECR API directly to copy images - no Docker required. It:
1. Fetches the image manifest from the source repository
2. Puts the manifest to the destination repository

This approach works in standard Lambda (no container runtime needed) and is efficient
because ECR handles layer deduplication automatically.

### Cross-Account ECR Access
For the Lambda to pull images from the source account's ECR, you need an ECR repository
policy in the source account that allows the destination account's Lambda role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCrossAccountPull",
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::DESTINATION_ACCOUNT:role/ecr-image-sync-role"
    },
    "Action": [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
  }]
}
```

### Security Considerations
- IAM policies are scoped to specific repository ARNs
- Consider using VPC endpoints for ECR if running in a private subnet
- The EventBridge IAM role is limited to invoking only this specific Lambda

## Files

| File | Purpose |
|------|---------|
| `provider.tf` | AWS provider configuration with TFC dynamic credentials |
| `variables.tf` | Input variable definitions |
| `data.tf` | Data sources including Lambda zip packaging |
| `lambda-erc-sync.tf` | Main infrastructure: Lambda, EventBridge, IAM |
| `lambda.py` | Python code for the image sync Lambda |
| `example.tfvars` | Example variable values |
