data "aws_caller_identity" "current" {}

locals {
  adapter_layer = "arn:aws:lambda:${var.aws_region}:753240598075:layer:LambdaAdapterLayerX86:28"
}

resource "aws_iam_role" "inference" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "inference" {
  name = "${var.function_name}-policy"
  role = aws_iam_role.inference.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Converse",
          "bedrock:ConverseStream",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_s3_object" "lambda_zip" {
  count       = var.lambda_s3_bucket == "" ? 0 : 1
  bucket      = var.lambda_s3_bucket
  key         = var.lambda_s3_key
  source      = var.lambda_zip
  source_hash = filemd5(var.lambda_zip)
}

resource "aws_lambda_function" "inference" {
  function_name    = var.function_name
  filename         = var.lambda_s3_bucket == "" ? var.lambda_zip : null
  s3_bucket        = var.lambda_s3_bucket == "" ? null : var.lambda_s3_bucket
  s3_key           = var.lambda_s3_bucket == "" ? null : var.lambda_s3_key
  source_code_hash = filebase64sha256(var.lambda_zip)
  role             = aws_iam_role.inference.arn
  handler          = "run.sh"
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  timeout          = 60
  memory_size      = 2048
  layers           = [local.adapter_layer]

  environment {
    variables = {
      MODEL_ID                = var.model_id
      MODEL_MAP               = var.model_map
      API_KEY                 = var.api_key
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/bootstrap"
      AWS_LWA_INVOKE_MODE     = "response_stream"
      AWS_LWA_PORT            = "8080"
    }
  }

  depends_on = [aws_iam_role_policy.inference, aws_s3_object.lambda_zip]
}

resource "aws_lambda_function_url" "inference" {
  function_name      = aws_lambda_function.inference.function_name
  authorization_type = "NONE"
  invoke_mode        = "RESPONSE_STREAM"

  cors {
    allow_origins = ["*"]
    allow_headers = ["content-type", "x-api-key", "authorization"]
    allow_methods = ["POST"]
    max_age       = 86400
  }
}

resource "aws_lambda_permission" "function_url" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.inference.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "function_invoke" {
  statement_id  = "FunctionURLAllowInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inference.function_name
  principal     = "*"
}
