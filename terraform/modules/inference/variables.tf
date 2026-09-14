variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type        = string
  description = "dev or prod. Used for tags, not for a Git branch."
}

variable "function_name" {
  type = string
}

variable "lambda_zip" {
  type        = string
  description = "Absolute path to the packaged Lambda zip"
}

variable "model_id" {
  type    = string
  default = "amazon.nova-lite-v1:0"
}

variable "model_map" {
  type    = string
  default = ""
}

variable "api_key" {
  type      = string
  sensitive = true
}

variable "lambda_s3_bucket" {
  type        = string
  default     = ""
  description = "If set, upload the Lambda zip via this bucket (needed when the zip exceeds 50MB)."
}

variable "lambda_s3_key" {
  type    = string
  default = "lambda.zip"
}
