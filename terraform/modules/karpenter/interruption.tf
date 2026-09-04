# =============================================================================
# terraform/modules/karpenter/interruption.tf
# Purpose: EventBridge -> SQS path for Spot/instance interruption signals.
#
# Flow: Queue + EventBridge rules when install_karpenter so Karpenter drains nodes.
#
# Linked: main.tf queue policy; helm.tf controller settings.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Interruption queue - 300s retention; SSE; name matches cluster
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "interruption" {
  count = var.install_karpenter ? 1 : 0

  name                      = local.queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(local.tags, {
    Name = local.queue_name
  })
}

# -----------------------------------------------------------------------------
# 2) Queue policy - EventBridge SendMessage; deny non-TLS
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "interruption_queue" {
  count = var.install_karpenter ? 1 : 0

  statement {
    sid       = "EC2InterruptionPolicy"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption[0].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${local.name_prefix}-karpenter-*",
      ]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption[0].arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# -----------------------------------------------------------------------------
# 3) Queue policy attachment - bind EventBridge allow + TLS deny
# -----------------------------------------------------------------------------

resource "aws_sqs_queue_policy" "interruption" {
  count = var.install_karpenter ? 1 : 0

  queue_url = aws_sqs_queue.interruption[0].id
  policy    = data.aws_iam_policy_document.interruption_queue[0].json
}

# -----------------------------------------------------------------------------
# 4) Locals - health/spot/rebalance/state-change events (PETPLAT-74 ready)
# -----------------------------------------------------------------------------

locals {
  interruption_events = var.install_karpenter ? {
    health-event = {
      description = "AWS Health events affecting instances"
      source      = ["aws.health"]
      detail_type = ["AWS Health Event"]
    }
    spot-interruption = {
      description = "EC2 spot interruption warnings"
      source      = ["aws.ec2"]
      detail_type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      description = "EC2 instance rebalance recommendations"
      source      = ["aws.ec2"]
      detail_type = ["EC2 Instance Rebalance Recommendation"]
    }
    instance-state-change = {
      description = "EC2 instance state changes"
      source      = ["aws.ec2"]
      detail_type = ["EC2 Instance State-change Notification"]
    }
  } : {}
}

# -----------------------------------------------------------------------------
# 5) EventBridge rules - one rule per interruption event source
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name        = "${local.name_prefix}-karpenter-${each.key}"
  description = each.value.description

  event_pattern = jsonencode({
    source        = each.value.source
    "detail-type" = each.value.detail_type
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-karpenter-${each.key}"
  })
}

# -----------------------------------------------------------------------------
# 6) EventBridge targets - forward matching events to the SQS queue
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_events

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.interruption[0].arn
}
