module "inference" {
  source = "../modules/inference"

  aws_region       = var.aws_region
  environment      = var.environment
  function_name    = var.function_name
  lambda_zip       = var.lambda_zip
  model_id         = var.model_id
  model_map        = var.model_map
  api_key          = var.api_key
  lambda_s3_bucket = var.lambda_s3_bucket
  lambda_s3_key    = var.lambda_s3_key
}
