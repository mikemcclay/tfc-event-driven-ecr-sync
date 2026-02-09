# =============================================================================
# CROSS-ACCOUNT ECR IMAGE SYNC - EVENT-DRIVEN ARCHITECTURE
# =============================================================================
# This file demonstrates cross-account event-driven architecture where:
#   - EventBridge rule/target live in the SOURCE account (aws.ecr provider)
#   - Lambda function lives in the DESTINATION account (default provider)
#
# Flow: ECR Push → EventBridge Rule → Cross-Account Lambda Invoke → ECR Push
# =============================================================================

# #############################################################################
# DESTINATION ACCOUNT RESOURCES (default provider)
# #############################################################################

# -----------------------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------------------
# The Lambda function that handles copying images from source to destination.
# Triggered by EventBridge events from the source account.
#
# Uses the ECR API directly to copy image manifests - no Docker required.
# This approach works in standard Lambda and is efficient for image replication.
# This is provided as an example - in production, consider vpc placement, security groups,
# error handling, retries, and monitoring.
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "pull_push" {
  function_name = var.lambda_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300 # 5 minutes - image operations can be slow
  memory_size   = 512 # Adequate for image processing, tune down if needed

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SOURCE_ACCOUNT_ID      = var.source_account_id
      SOURCE_REGION          = var.source_region
      DESTINATION_ACCOUNT_ID = var.destination_account_id
      DESTINATION_REGION     = var.destination_region
      REPO_NAME              = var.repo_name
    }
  }

  tags = {
    Purpose = "ECR cross-account image sync"
  }
}

# -----------------------------------------------------------------------------
# Lambda Execution Role (Destination Account)
# -----------------------------------------------------------------------------
# IAM role that the Lambda function assumes during execution.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "${var.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Purpose = "Lambda execution role for ECR sync"
  }
}

# -----------------------------------------------------------------------------
# Lambda IAM Policy (Destination Account)
# -----------------------------------------------------------------------------
# Permissions for the Lambda to:
#   - Read from source ECR (cross-account, requires ECR repo policy)
#   - Write to destination ECR
#   - Write CloudWatch Logs
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.lambda_name}-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPullFromSource"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer"
        ]
        # Cross-account pull requires ECR repository policy in source account
        Resource = "arn:aws:ecr:${var.source_region}:${var.source_account_id}:repository/${var.repo_name}"
      },
      {
        Sid    = "ECRPushToDestination"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:${var.destination_region}:${var.destination_account_id}:repository/${var.repo_name}"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${var.destination_account_id}:*"
      }
    ]
  })
}


# #############################################################################
# SOURCE ACCOUNT RESOURCES (aws.ecr provider)
# #############################################################################

# -----------------------------------------------------------------------------
# EventBridge Rule (Source Account)
# -----------------------------------------------------------------------------
# Captures ECR image push events. This rule MUST live in the source account 
# because that's where ECR emits the events.
#
# The event pattern filters for:
#   - Successful image pushes
#   - Specific repository name  
#   - Specific image tag (environment)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "ecr_push" {
  provider    = aws.ecr
  name        = "${var.lambda_name}-ecr-push"
  description = "Triggers cross-account Lambda when images are pushed to ECR"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      repository-name = [var.repo_name]
      image-tag       = [var.appenv]
      result          = ["SUCCESS"]
    }
  })

  tags = {
    Purpose = "Cross-account ECR sync trigger"
  }
}

# -----------------------------------------------------------------------------
# EventBridge Target (Source Account)
# -----------------------------------------------------------------------------
# Points to the Lambda function in the destination account.
# Requires an IAM role to make cross-account invocations.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_target" "lambda_target" {
  provider  = aws.ecr
  rule      = aws_cloudwatch_event_rule.ecr_push.name
  target_id = "cross-account-lambda"
  arn       = aws_lambda_function.pull_push.arn
  role_arn  = aws_iam_role.eventbridge_invoke_role.arn
}

# -----------------------------------------------------------------------------
# EventBridge IAM Role (Source Account)
# -----------------------------------------------------------------------------
# This role allows EventBridge in the source account to invoke 
# the Lambda function in the destination account.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "eventbridge_invoke_role" {
  provider = aws.ecr
  name     = "${var.lambda_name}-eventbridge-invoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Purpose = "Allow EventBridge to invoke cross-account Lambda"
  }
}

resource "aws_iam_role_policy" "eventbridge_invoke_policy" {
  provider = aws.ecr
  name     = "${var.lambda_name}-invoke-policy"
  role     = aws_iam_role.eventbridge_invoke_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeCrossAccountLambda"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.pull_push.arn
    }]
  })
}

# -----------------------------------------------------------------------------
# Lambda Resource-Based Policy (Destination Account)
# -----------------------------------------------------------------------------
# Allows the EventBridge rule in the source account to invoke this Lambda.
# This is the "receiving end" permission that complements the IAM role above.
# -----------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id   = "AllowCrossAccountEventBridge"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.pull_push.function_name
  principal      = "events.amazonaws.com"
  source_arn     = aws_cloudwatch_event_rule.ecr_push.arn
  source_account = var.source_account_id
}
