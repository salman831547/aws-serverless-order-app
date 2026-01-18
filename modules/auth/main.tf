variable "project_name" {}
variable "environment" {}

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-user-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.project_name}-${var.environment}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

output "user_pool_id" { value = aws_cognito_user_pool.main.id }
output "client_id" { value = aws_cognito_user_pool_client.client.id }
