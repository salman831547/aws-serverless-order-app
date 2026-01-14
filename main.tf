provider "aws" {
  region = "us-east-1"
}

# --- 1. DynamoDB Table ---
resource "aws_dynamodb_table" "orders_table" {
  name         = "OrdersTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "OrderId"
  attribute {
    name = "OrderId"
    type = "S"
  }
}

# --- 2. SQS Queues (Main + DLQ) ---
resource "aws_sqs_queue" "order_dlq" {
  name = "order-processing-dlq"
}

resource "aws_sqs_queue" "order_queue" {
  name = "order-processing-queue"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })
}

# --- 3. EventBridge & SNS ( The New Hub ) ---
resource "aws_cloudwatch_event_bus" "order_bus" {
  name = "order-system-bus"
}

resource "aws_sns_topic" "vip_orders" {
  name = "vip-orders-topic"
}

# --- Email Subscription ---
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.vip_orders.arn
  protocol  = "email"

  # 👇 ENTER YOUR REAL EMAIL ADDRESS BELOW 👇
  endpoint = "python831547@gmail.com"
}

# Rule 1: Catch-All (To SQS)
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

# Rule 2: VIP Orders (To SNS)
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

# --- 4. IAM Roles & Policies ---

# PRODUCER ROLE
resource "aws_iam_role" "producer_role" {
  name = "producer_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "producer_policy" {
  role = aws_iam_role.producer_role.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      { Action = ["logs:*", "events:PutEvents"], Effect = "Allow", Resource = "*" }
    ]
  })
}

# CONSUMER ROLE
resource "aws_iam_role" "consumer_role" {
  name = "consumer_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "consumer_policy" {
  role = aws_iam_role.consumer_role.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      { Action = ["logs:*", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Effect = "Allow", Resource = aws_sqs_queue.order_queue.arn },
      { Action = ["dynamodb:PutItem"], Effect = "Allow", Resource = aws_dynamodb_table.orders_table.arn }
    ]
  })
}

# EVENTBRIDGE PERMISSIONS (To write to SQS/SNS)
resource "aws_sqs_queue_policy" "allow_eventbridge" {
  queue_url = aws_sqs_queue.order_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sqs:SendMessage", Resource = aws_sqs_queue.order_queue.arn,
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.all_orders.arn } }
    }]
  })
}

resource "aws_sns_topic_policy" "allow_eventbridge_sns" {
  arn = aws_sns_topic.vip_orders.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.vip_orders.arn
    }]
  })
}

# --- 5. Lambda Functions ---
data "archive_file" "producer_zip" {
  type        = "zip"
  source_file = "producer.py"
  output_path = "producer.zip"
}
data "archive_file" "consumer_zip" {
  type        = "zip"
  source_file = "consumer.py"
  output_path = "consumer.zip"
}

resource "aws_lambda_function" "producer" {
  filename         = "producer.zip"
  function_name    = "OrderProducer"
  role             = aws_iam_role.producer_role.arn
  handler          = "producer.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.producer_zip.output_base64sha256
  environment {
    variables = { EVENT_BUS_NAME = aws_cloudwatch_event_bus.order_bus.name }
  }
}

resource "aws_lambda_function" "consumer" {
  filename         = "consumer.zip"
  function_name    = "OrderConsumer"
  role             = aws_iam_role.consumer_role.arn
  handler          = "consumer.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256
  environment {
    variables = { DYNAMODB_TABLE = aws_dynamodb_table.orders_table.name }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
}

# --- 6. API Gateway (With CORS) ---
resource "aws_api_gateway_rest_api" "order_api" {
  name = "OrderAPI"
}

resource "aws_api_gateway_resource" "order_resource" {
  parent_id   = aws_api_gateway_rest_api.order_api.root_resource_id
  path_part   = "order"
  rest_api_id = aws_api_gateway_rest_api.order_api.id
}

# POST Method
resource "aws_api_gateway_method" "post_method" {
  authorization = "NONE"
  http_method   = "POST"
  resource_id   = aws_api_gateway_resource.order_resource.id
  rest_api_id   = aws_api_gateway_rest_api.order_api.id
}

resource "aws_api_gateway_integration" "lambda_integration" {
  http_method             = aws_api_gateway_method.post_method.http_method
  resource_id             = aws_api_gateway_resource.order_resource.id
  rest_api_id             = aws_api_gateway_rest_api.order_api.id
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.producer.invoke_arn
}

# OPTIONS Method (CORS Support)
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.order_api.id
  resource_id   = aws_api_gateway_resource.order_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id       = aws_api_gateway_rest_api.order_api.id
  resource_id       = aws_api_gateway_resource.order_resource.id
  http_method       = aws_api_gateway_method.options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id     = aws_api_gateway_rest_api.order_api.id
  resource_id     = aws_api_gateway_resource.order_resource.id
  http_method     = aws_api_gateway_method.options.http_method
  status_code     = "200"
  response_models = { "application/json" = "Empty" }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.order_api.id
  resource_id = aws_api_gateway_resource.order_resource.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.order_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration, aws_api_gateway_integration.options]
  rest_api_id = aws_api_gateway_rest_api.order_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.order_resource.id,
      aws_api_gateway_method.post_method.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_integration.options.id # Ensure trigger monitors CORS changes
    ]))
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.order_api.id
  stage_name    = "prod"
}

# --- 7. S3 Frontend (Standard - not CloudFront yet for simplicity) ---
resource "aws_s3_bucket" "frontend_bucket" {
  bucket_prefix = "serverless-frontend-"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "frontend_config" {
  bucket = aws_s3_bucket.frontend_bucket.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket     = aws_s3_bucket.frontend_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.public_access]
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = "*", Action = "s3:GetObject", Resource = "${aws_s3_bucket.frontend_bucket.arn}/*" }]
  })
}

# --- Outputs ---
output "api_url" { value = "${aws_api_gateway_stage.prod_stage.invoke_url}/order" }
output "website_url" { value = aws_s3_bucket_website_configuration.frontend_config.website_endpoint }
