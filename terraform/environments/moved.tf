# One-time: prod state copied from the old flat root (bedrock-inference-mvp.tfstate).
# Ignored when those addresses are not in this environment's state.
moved {
  from = aws_iam_role.inference
  to   = module.inference.aws_iam_role.inference
}

moved {
  from = aws_iam_role_policy.inference
  to   = module.inference.aws_iam_role_policy.inference
}

moved {
  from = aws_s3_object.lambda_zip[0]
  to   = module.inference.aws_s3_object.lambda_zip[0]
}

moved {
  from = aws_lambda_function.inference
  to   = module.inference.aws_lambda_function.inference
}

moved {
  from = aws_lambda_function_url.inference
  to   = module.inference.aws_lambda_function_url.inference
}

moved {
  from = aws_lambda_permission.function_invoke
  to   = module.inference.aws_lambda_permission.function_invoke
}
