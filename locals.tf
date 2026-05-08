locals {
  tag_name        = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"
  certificate_arn = var.certificate_arn != null ? var.certificate_arn : aws_acm_certificate_validation.cert[0].certificate_arn
}