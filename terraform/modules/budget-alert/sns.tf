resource "aws_sns_topic" "budget_alert" {
  name = "${var.project}-budget-alert"
}

resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.budget_alert.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.budget_to_discord.arn
}

data "aws_caller_identity" "current" {}

# AWS Budgets가 이 Topic에 Publish할 수 있게 명시적으로 허용하는 정책이 없으면,
# Budget과 Topic이 둘 다 정상 생성된 것처럼 보여도 실제 임계값 초과 시 알림이 조용히
# 유실된다 (AWS 쪽에서 에러도 안 남기고 그냥 발행이 거부됨).
data "aws_iam_policy_document" "budget_alert_topic_policy" {
  statement {
    sid     = "AllowBudgetsPublish"
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    resources = [aws_sns_topic.budget_alert.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_budgets_budget.this.arn]
    }
  }
}

resource "aws_sns_topic_policy" "budget_alert" {
  arn    = aws_sns_topic.budget_alert.arn
  policy = data.aws_iam_policy_document.budget_alert_topic_policy.json
}
