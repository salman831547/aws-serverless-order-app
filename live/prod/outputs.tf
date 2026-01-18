output "api_gateway_url" {
  description = "HTTP API Endpoint for POST /orders"
  value       = "${module.backend.api_endpoint}/orders"
}

output "website_url" {
  description = "CloudFront URL for the frontend"
  value       = "https://${module.frontend.website_url}"
}

output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "s3_bucket_name_to_upload_html" {
  value = module.frontend.bucket_name
}

output "cognito_client_id" {
  description = "The ID of the App Client to put in index.html"
  value       = module.auth.client_id
}
