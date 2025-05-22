locals {
  cert_validation_map = var.public_endpoint ? {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}
}

# ACM Certificate for the domain
resource "aws_acm_certificate" "cert" {
  count = var.public_endpoint ? 1 : 0
  domain_name       = var.domain
  validation_method = "DNS"

  tags = {
    Name = local.tag_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create Route53 zone for the domain
resource "aws_route53_zone" "public_zone" {
  count = var.public_endpoint ? 1 : 0
  name = var.domain

  tags = {
    Name = local.tag_name
  }
}

# Create DNS records for certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = local.cert_validation_map

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.public_zone[0].zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Create Route53 record for the ALB
resource "aws_route53_record" "langfuse_public" {
  count = var.public_endpoint ? 1 : 0
  zone_id = aws_route53_zone.public_zone[0].zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "public_ns" {
  count = var.public_endpoint && var.public_zone != null ? 1 : 0

  zone_id = var.public_zone
  name    = var.domain
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.public_zone[0].name_servers
}

# data.aws_lb was moved to ingress.tf, as it is shared between public and private endpoints
