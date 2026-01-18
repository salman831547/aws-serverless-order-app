provider "aws" {
  region = var.aws_region
}

module "auth" {
  source       = "../../modules/auth"
  project_name = var.project_name
  environment  = var.environment
}

module "database" {
  source       = "../../modules/database"
  project_name = var.project_name
  environment  = var.environment
}

module "messaging" {
  source         = "../../modules/messaging"
  project_name   = var.project_name
  environment    = var.environment
  email_endpoint = var.alert_email
}

module "backend" {
  source              = "../../modules/backend"
  project_name        = var.project_name
  environment         = var.environment
  event_bus_name      = module.messaging.event_bus_name
  event_bus_arn       = module.messaging.event_bus_arn
  sqs_queue_arn       = module.messaging.sqs_queue_arn
  dynamodb_table_name = module.database.table_name
  dynamodb_table_arn  = module.database.table_arn
  user_pool_id        = module.auth.user_pool_id
  user_pool_client_id = module.auth.client_id
}

module "frontend" {
  source       = "../../modules/frontend"
  project_name = var.project_name
  environment  = var.environment
}
