# ACM Certificate for the domain (only if no existing cert provided)
resource "aws_acm_certificate" "cert" {
  count             = var.existing_certificate_arn == null ? 1 : 0
  domain_name       = var.domain
  validation_method = "DNS"

  tags = {
    Name = local.tag_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create Route53 zone for the domain (only if no existing cert provided)
resource "aws_route53_zone" "zone" {
  count = var.existing_certificate_arn == null ? 1 : 0
  name  = var.domain

  tags = {
    Name = local.tag_name
  }
}

# Create DNS records for certificate validation (only if creating new cert)
resource "aws_route53_record" "cert_validation" {
  for_each = var.existing_certificate_arn == null ? {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.zone[0].zone_id
}

# Certificate validation (only if creating new cert)
resource "aws_acm_certificate_validation" "cert" {
  count                   = var.existing_certificate_arn == null ? 1 : 0
  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Data source to get existing certificate (when provided)
data "aws_acm_certificate" "existing" {
  count = var.existing_certificate_arn != null ? 1 : 0
  arn   = var.existing_certificate_arn
}

# Local value to reference the correct certificate ARN
locals {
  certificate_arn = var.existing_certificate_arn != null ? var.existing_certificate_arn : aws_acm_certificate_validation.cert[0].certificate_arn
}

# Get the ALB details
data "aws_lb" "ingress" {
  tags = {
    "elbv2.k8s.aws/cluster"    = var.name
    "ingress.k8s.aws/stack"    = "langfuse/langfuse"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.langfuse
  ]
}

# Create Route53 record for the ALB (only if creating new zone)
resource "aws_route53_record" "langfuse" {
  count   = var.existing_certificate_arn == null ? 1 : 0
  zone_id = aws_route53_zone.zone[0].zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}
