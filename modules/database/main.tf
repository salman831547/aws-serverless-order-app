variable "project_name" {}
variable "environment" {}

resource "aws_dynamodb_table" "main" {
  name         = "${var.project_name}-${var.environment}-orders"
  billing_mode = "PAY_PER_REQUEST" # Serverless billing
  hash_key     = "OrderId"

  # Encryption at Rest (AWS Managed Key) - Compliance Requirement
  server_side_encryption {
    enabled = true
  }

  # Disaster Recovery - Compliance Requirement
  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "OrderId"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

output "table_name" { value = aws_dynamodb_table.main.name }
output "table_arn" { value = aws_dynamodb_table.main.arn }
