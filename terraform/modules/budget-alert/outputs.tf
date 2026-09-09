output "sns_topic_arn" {
  value = aws_sns_topic.budget_alert.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.budget_to_discord.function_name
}
