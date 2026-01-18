variable "project_name" {}
variable "environment" {}
variable "event_bus_name" {}
variable "event_bus_arn" {}
variable "dynamodb_table_name" {}
variable "dynamodb_table_arn" {}
variable "sqs_queue_arn" {}
# --- NEW VARIABLES FOR AUTH ---
variable "user_pool_id" {}
variable "user_pool_client_id" {}

# --- 1. Python Source Zipping ---
# ... (Keep data sources the same) ...
data "archive_file" "producer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/producer.py"
  output_path = "${path.module}/src/producer.zip"
}

data "archive_file" "consumer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/consumer.py"
  output_path = "${path.module}/src/consumer.zip"
}

# --- 2. IAM Roles & Polices ---
# ... (Keep IAM roles the same as previous response) ...
resource "aws_iam_role" "producer_role" {
  name = "${var.project_name}-producer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "producer_policy" {
  role = aws_iam_role.producer_role.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      { Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Effect = "Allow", Resource = "arn:aws:logs:*:*:*" },
      { Action = "events:PutEvents", Effect = "Allow", Resource = var.event_bus_arn }
    ]
  })
}

resource "aws_iam_role" "consumer_role" {
  name = "${var.project_name}-consumer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "consumer_policy" {
  role = aws_iam_role.consumer_role.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      { Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Effect = "Allow", Resource = "arn:aws:logs:*:*:*" },
      { Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Effect = "Allow", Resource = var.sqs_queue_arn },
      { Action = "dynamodb:PutItem", Effect = "Allow", Resource = var.dynamodb_table_arn }
    ]
  })
}

# --- 3. Lambda Functions ---
# ... (Keep Lambda definitions the same) ...
resource "aws_lambda_function" "producer" {
  filename         = data.archive_file.producer_zip.output_path
  function_name    = "${var.project_name}-producer"
  role             = aws_iam_role.producer_role.arn
  handler          = "producer.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.producer_zip.output_base64sha256
  environment {
    variables = { EVENT_BUS_NAME = var.event_bus_name }
  }
}

resource "aws_lambda_function" "consumer" {
  filename         = data.archive_file.consumer_zip.output_path
  function_name    = "${var.project_name}-consumer"
  role             = aws_iam_role.consumer_role.arn
  handler          = "consumer.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256
  environment {
    variables = { DYNAMODB_TABLE = var.dynamodb_table_name }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
}

# --- 4. API Gateway (HTTP API) ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"] # In real prod, restrict this to the CloudFront domain
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type", "authorization"] # Added authorization header support
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# --- NEW: Cognito Authorizer ---
resource "aws_apigatewayv2_authorizer" "cognito_auth" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-authorizer"

  jwt_configuration {
    audience = [var.user_pool_client_id]
    issuer   = "https://cognito-idp.${data.aws_region.current.id}.amazonaws.com/${var.user_pool_id}"
  }
}

# Need current region for the issuer URL
data "aws_region" "current" {}


resource "aws_apigatewayv2_integration" "producer_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  payload_format_version = "2.0"
}

# --- MODIFIED: Route with authorization ---
resource "aws_apigatewayv2_route" "post_order" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /orders"
  target    = "integrations/${aws_apigatewayv2_integration.producer_integration.id}"

  # Attach the Cognito Authorizer
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_auth.id
}


resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*/orders"
}

output "api_endpoint" { value = aws_apigatewayv2_api.http_api.api_endpoint }
