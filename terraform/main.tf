terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

variable "app_env" {
  description = "Value for the APP_ENV environment variable on the Lambda"
  type        = string
  default     = "production"
}

variable "s3_bucket" {
  description = "S3 bucket that holds the deployment ZIP"
  type        = string
}

variable "s3_key" {
  description = "S3 key for the deployment ZIP"
  type        = string
  default     = "deployment.zip"
}

# ---------------------------------------------------------------------------
# IAM execution role
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

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "app" {
  function_name = var.function_name
  description   = "FastAPI app via Mangum"

  role    = aws_iam_role.lambda_exec.arn
  runtime = "python3.11"
  handler = "lambda_handler.handler"

  s3_bucket = var.s3_bucket
  s3_key    = var.s3_key

  timeout      = 30
  memory_size  = 256

  environment {
    variables = {
      APP_ENV = var.app_env
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
  ]
}

# ---------------------------------------------------------------------------
# Lambda Function URL  (auth_type NONE + CORS)
# ---------------------------------------------------------------------------

resource "aws_lambda_function_url" "app_url" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["content-type", "authorization", "x-amz-date", "x-api-key", "x-amz-security-token"]
    expose_headers    = []
    max_age           = 86400
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.app.function_name
}

output "function_url" {
  description = "Publicly reachable Function URL"
  value       = aws_lambda_function_url.app_url.function_url
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.app.arn
}