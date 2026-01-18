variable "aws_region" {
  description = "The AWS region to deploy to"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier"
  default     = "serverless-shop"
}

variable "environment" {
  description = "Deployment environment (dev/prod)"
  default     = "prod"
}

variable "alert_email" {
  description = "Email for critical SNS alerts"
  type        = string
  # No default - force user to provide it for safety
}
