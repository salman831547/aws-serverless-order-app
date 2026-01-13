provider "aws" {
  region = "us-east-1" # Change if needed
}

# --- 1. DynamoDB Table ---
resource "aws_dynamodb_table" "orders_table" {
  name           = "OrdersTable"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "OrderId"

  attribute {
    name = "OrderId"
    type = "S"
  }
}

# --- 2. SQS Queue ---
resource "aws_sqs_queue" "order_queue" {
  name = "order-processing-queue"
}

# --- 3. IAM Roles & Policies ---
# Role for Producer Lambda
resource "aws_iam_role" "producer_role" {
  name = "producer_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

# Policy: Allow Producer to log and send to SQS
resource "aws_iam_role_policy" "producer_policy" {
  role = aws_iam_role.producer_role.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      { Action = ["logs:*", "sqs:SendMessage"], Effect = "Allow", Resource = "*" }
    ]
  })
}

# Role for Consumer Lambda
resource "aws_iam_role" "consumer_role" {
  name = "consumer_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

# Policy: Allow Consumer to log, read SQS, write DynamoDB
resource "aws_iam_role_policy" "consumer_policy" {
  role = aws_iam_role.consumer_role.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      { Action = ["logs:*", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Effect = "Allow", Resource = aws_sqs_queue.order_queue.arn },
      { Action = ["dynamodb:PutItem"], Effect = "Allow", Resource = aws_dynamodb_table.orders_table.arn }
    ]
  })
}

# --- 4. Lambda Functions ---
# Zip files creation
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
  filename      = "producer.zip"
  function_name = "OrderProducer"
  role          = aws_iam_role.producer_role.arn
  handler       = "producer.lambda_handler"
  runtime       = "python3.9"
  source_code_hash = data.archive_file.producer_zip.output_base64sha256
  
  environment {
    variables = { SQS_QUEUE_URL = aws_sqs_queue.order_queue.id }
  }
}

resource "aws_lambda_function" "consumer" {
  filename      = "consumer.zip"
  function_name = "OrderConsumer"
  role          = aws_iam_role.consumer_role.arn
  handler       = "consumer.lambda_handler"
  runtime       = "python3.9"
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256

  environment {
    variables = { DYNAMODB_TABLE = aws_dynamodb_table.orders_table.name }
  }
}

# --- 5. Event Source Mapping (Connect SQS -> Consumer) ---
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
}

# --- 6. API Gateway (REST) ---
resource "aws_api_gateway_rest_api" "order_api" {
  name = "OrderAPI"
}

resource "aws_api_gateway_resource" "order_resource" {
  parent_id   = aws_api_gateway_rest_api.order_api.root_resource_id
  path_part   = "order"
  rest_api_id = aws_api_gateway_rest_api.order_api.id
}

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

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.order_api.execution_arn}/*/*"
}

# 1. The Deployment (Snapshot of the API)
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.order_api.id

  # Redeploy when the API definition changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.order_resource.id,
      aws_api_gateway_method.post_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 2. The Stage (The actual environment "prod")
resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.order_api.id
  stage_name    = "prod"
}

# --- 7. S3 Static Website ---
resource "aws_s3_bucket" "frontend_bucket" {
  bucket_prefix = "serverless-frontend-"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "frontend_config" {
  bucket = aws_s3_bucket.frontend_bucket.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.frontend_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.public_access]
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow", Principal = "*", Action = "s3:GetObject",
      Resource = "${aws_s3_bucket.frontend_bucket.arn}/*"
    }]
  })
}

# --- Outputs ---

output "api_url" { value = "${aws_api_gateway_stage.prod_stage.invoke_url}/order" }

output "website_url" { value = aws_s3_bucket_website_configuration.frontend_config.website_endpoint }