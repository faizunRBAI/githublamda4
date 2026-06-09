terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "githublamda4"
}

variable "deployment_zip_path" {
  description = "Path to the deployment zip artifact produced by CI"
  type        = string
  default     = "deployment.zip"
}

# ---------------------------------------------------------------------------
# IAM role for the Lambda function
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.function_name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# CloudWatch log group (explicit so Terraform manages retention)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 14
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "app" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_exec.arn

  # Package is managed by CI via aws lambda update-function-code;
  # a placeholder filename is required on first apply.
  filename         = var.deployment_zip_path
  source_code_hash = filebase64sha256(var.deployment_zip_path)

  handler     = "lambda_handler.handler"
  runtime     = "python3.12"
  memory_size = 256
  timeout     = 30

  environment {
    variables = {
      APP_ENV = "production"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_logs,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# ---------------------------------------------------------------------------
# Lambda Function URL (public, no IAM auth, CORS enabled for browser access)
# ---------------------------------------------------------------------------

resource "aws_lambda_function_url" "app_url" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["content-type", "authorization", "x-amz-date", "x-api-key"]
    expose_headers    = ["*"]
    max_age           = 86400
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.app.arn
}

output "function_url" {
  description = "Lambda Function URL (public endpoint)"
  value       = aws_lambda_function_url.app_url.function_url
}