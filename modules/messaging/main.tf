variable "project_name" {}
variable "environment" {}
variable "email_endpoint" {}

# --- EventBridge Bus ---
resource "aws_cloudwatch_event_bus" "order_bus" {
  name = "${var.project_name}-${var.environment}-bus"
}

# --- SNS Topic (VIP Orders) ---
resource "aws_sns_topic" "vip_orders" {
  name              = "${var.project_name}-${var.environment}-vip-topic"
  kms_master_key_id = "alias/aws/sns" # Encryption at rest
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.vip_orders.arn
  protocol  = "email"
  endpoint  = var.email_endpoint
}

# --- SQS Queue (Standard Orders) ---
resource "aws_sqs_queue" "order_dlq" {
  name              = "${var.project_name}-${var.environment}-dlq"
  kms_master_key_id = "alias/aws/sqs"
}

resource "aws_sqs_queue" "order_queue" {
  name              = "${var.project_name}-${var.environment}-queue"
  kms_master_key_id = "alias/aws/sqs"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })
}

# --- Event Rules ---
# Rule 1: VIP (High Quantity) -> SNS
resource "aws_cloudwatch_event_rule" "vip_rule" {
  name           = "capture-vip-orders"
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
  event_pattern = jsonencode({
    source = ["com.mycompany.orderapp"],
    detail = { quantity = [{ numeric = [">=", 5] }] }
  })
}

resource "aws_cloudwatch_event_target" "sns_target" {
  rule           = aws_cloudwatch_event_rule.vip_rule.name
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
  arn            = aws_sns_topic.vip_orders.arn
}

# Rule 2: All Orders -> SQS
resource "aws_cloudwatch_event_rule" "all_orders" {
  name           = "capture-all-orders"
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
  event_pattern  = jsonencode({ source = ["com.mycompany.orderapp"] })
}

resource "aws_cloudwatch_event_target" "sqs_target" {
  rule           = aws_cloudwatch_event_rule.all_orders.name
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
  arn            = aws_sqs_queue.order_queue.arn
}

# --- Policies (Allow EventBridge to write to SQS/SNS) ---
resource "aws_sqs_queue_policy" "allow_eb" {
  queue_url = aws_sqs_queue.order_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow", Principal = { Service = "events.amazonaws.com" },
      Action    = "sqs:SendMessage", Resource = aws_sqs_queue.order_queue.arn,
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.all_orders.arn } }
    }]
  })
}

resource "aws_sns_topic_policy" "allow_eb" {
  arn = aws_sns_topic.vip_orders.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow", Principal = { Service = "events.amazonaws.com" },
      Action = "sns:Publish", Resource = aws_sns_topic.vip_orders.arn
    }]
  })
}

output "event_bus_name" { value = aws_cloudwatch_event_bus.order_bus.name }
output "event_bus_arn" { value = aws_cloudwatch_event_bus.order_bus.arn }
output "sqs_queue_arn" { value = aws_sqs_queue.order_queue.arn }
