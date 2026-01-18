variable "project_name" {}
variable "environment" {}

# 1. Block Public Access S3 Bucket
resource "aws_s3_bucket" "static_site" {
  bucket_prefix = "${var.project_name}-${var.environment}-frontend-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket                  = aws_s3_bucket.static_site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. CloudFront Origin Access Control (Secure way S3 talks to CF)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for static site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 3. CloudFront Distribution
resource "aws_cloudfront_distribution" "cf" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    viewer_protocol_policy = "redirect-to-https"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
}

# 4. S3 Bucket Policy (Allow CloudFront)
resource "aws_s3_bucket_policy" "cdn_policy" {
  bucket = aws_s3_bucket.static_site.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "s3:GetObject",
      Effect    = "Allow",
      Principal = { Service = "cloudfront.amazonaws.com" },
      Resource  = "${aws_s3_bucket.static_site.arn}/*",
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.cf.arn } }
    }]
  })
}

output "website_url" { value = aws_cloudfront_distribution.cf.domain_name }
output "bucket_name" { value = aws_s3_bucket.static_site.id }
