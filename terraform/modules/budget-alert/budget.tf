# 프로젝트 실제 운영 기간(9/7~10/6)을 하나의 예산 기간으로 잡는다.
# AWS Budgets의 time_unit에는 CUSTOM이 없어(DAILY/MONTHLY/QUARTERLY/
# ANNUALLY만 지원) MONTHLY로 두되, time_period_end를 프로젝트 종료일로 명시해 다음 갱신
# 주기(10/7~)가 시작되기 전에 끝나도록 한다 — 사실상 이 한 기간만 도는 단발성 예산이 된다.
#
# limit_amount는 "AWS 측 가용 크레딧 합계"($552 = 지원금 $352 + Free-tier $200) 기준
# 실사용 추정치($253.16)를 기준으로 잡으면 계획대로 진행해도 50%
# 임계값에서 이미 알림이 뜨는 오탐이 잦아지므로, 실제로 못 넘어야 하는 한도인 크레딧
# 총액을 기준으로 삼는다.
resource "aws_budgets_budget" "this" {
  name         = "${var.project}-budget"
  budget_type  = "COST"
  limit_amount = "552"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  time_period_start = "2026-09-07_00:00"
  time_period_end   = "2026-10-06_23:59"

  # 모니터링 & 알림 기준: 예산의 50/80/100% 도달 시 알림
  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.budget_alert.arn]
    }
  }
}
