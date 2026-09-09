resource "aws_sns_topic" "budget_alert" {
  name = "${var.project}-budget-alert"
}

resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.budget_alert.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.budget_to_discord.arn
}
