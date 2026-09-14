output "function_url" {
  description = "Lambda Function URL for the inference API"
  value       = aws_lambda_function_url.inference.function_url
}

output "function_arn" {
  description = "Inference Lambda ARN"
  value       = aws_lambda_function.inference.arn
}
