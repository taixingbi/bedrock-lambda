variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type = string
}

variable "function_name" {
  type = string
}

variable "lambda_zip" {
  type = string
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
  type    = string
  default = ""
}

variable "lambda_s3_key" {
  type    = string
  default = "lambda.zip"
}
