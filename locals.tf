locals {
  tag_name                = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"
  certificate_arn         = var.skip_dns_setup ? var.certificate_arn : aws_acm_certificate_validation.cert[0].certificate_arn
  gateway_domain          = coalesce(var.gateway_domain, "gateway.${var.domain}")
  gateway_certificate_arn = !var.enable_ai_gateway ? null : (var.skip_dns_setup ? coalesce(var.gateway_certificate_arn, var.certificate_arn) : aws_acm_certificate_validation.gateway[0].certificate_arn)
}