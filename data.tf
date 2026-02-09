# =============================================================================
# DATA SOURCES
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Deployment Package
# -----------------------------------------------------------------------------
# Creates a zip file from lambda.py for deployment. The source file is renamed
# to lambda_function.py to match the handler path (lambda_function.lambda_handler).
#
# This approach works well with Terraform Cloud as the zip is generated during
# plan/apply - no need to pre-build or commit the zip file.
# -----------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = file("${path.module}/lambda.py")
    filename = "lambda_function.py"
  }
}
