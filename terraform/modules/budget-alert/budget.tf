# 프로젝트 실제 운영 기간(9/7~10/6)을 하나의 예산 기간으로 잡는다.
# AWS Budgets의 time_unit에는 CUSTOM이 없어(DAILY/MONTHLY/QUARTERLY/
# ANNUALLY만 지원) MONTHLY로 두되, time_period_end를 프로젝트 종료일로 명시해 다음 갱신
# 주기(10/7~)가 시작되기 전에 끝나도록 한다 — 사실상 이 한 기간만 도는 단발성 예산이 된다.
# (이 부분을 안 넣으면 생성 시점부터 매달 반복되는 무기한 예산이 되어, 실제 프로젝트
# 종료 후에도 계속 새 주기로 알림을 감시하게 된다.)
resource "aws_budgets_budget" "monthly_cost" {
  name         = "${var.project}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  time_period_start = "2026-09-07_00:00"
  time_period_end   = "2026-10-06_23:59"

  dynamic "notification" {
    for_each = var.budget_notification_thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.budget_alert.arn]
    }
  }
}
