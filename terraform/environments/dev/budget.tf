# =============================================================================
# terraform/environments/dev/budget.tf
# Purpose: Monthly AWS budget with email alerts from terraform.tfvars.
#
# Linked: variables budget_*; AWS Budgets console.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Budget - monthly COST alert; TagKeyValue join avoids HCL ${} escaping
# -----------------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_limit_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [join("$", ["user:Environment", var.environment])]
  }

  dynamic "notification" {
    for_each = [50, 80, 100]

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_notification_email]
    }
  }
}
