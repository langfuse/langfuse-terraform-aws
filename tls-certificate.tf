resource "aws_s3_bucket" "crl_bucket" {
  bucket_prefix = "acmpca-crl-${var.name}-"
  force_destroy = true

  tags = {
    Name        = "${local.tag_name}-crl-bucket"
    Environment = "internal"
  }
}

resource "aws_s3_bucket_policy" "crl_bucket_policy" {
  bucket = aws_s3_bucket.crl_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowACMPCACRLAccess",
        Effect = "Allow",
        Principal = {
          Service = "acm-pca.amazonaws.com"
        },
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ],
        Resource = [
          aws_s3_bucket.crl_bucket.arn,
          "${aws_s3_bucket.crl_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_acmpca_certificate_authority" "private_root_ca" {
  type = "ROOT"
  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA" # Ensure this matches what you use below
    subject {
      common_name  = "internal-ca.${var.domain}"
      organization = "My Organization Internal CA"
    }
  }
  revocation_configuration {
    crl_configuration {
      enabled            = true
      expiration_in_days = 7
      s3_bucket_name     = aws_s3_bucket.crl_bucket.id
      s3_object_acl      = "BUCKET_OWNER_FULL_CONTROL"
    }
  }
  # Do not set 'enabled' here. Status will be PENDING_CERTIFICATE after creation.
  # The 'aws_acmpca_certificate_authority_certificate' resource handles activation.
  permanent_deletion_time_in_days = 7 # For non-prod. Adjust for production.
  tags = {
    Name        = "${local.tag_name}-Private-Root-CA"
    Environment = "internal"
  }
  depends_on = [aws_s3_bucket_policy.crl_bucket_policy]
}

# Step 1: Issue the self-signed certificate for the Root CA itself
resource "aws_acmpca_certificate" "private_root_ca_self_signed_cert" {
  # This certificate is for the CA itself.
  certificate_authority_arn   = aws_acmpca_certificate_authority.private_root_ca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.private_root_ca.certificate_signing_request # Fetches the CA's own CSR
  signing_algorithm           = aws_acmpca_certificate_authority.private_root_ca.certificate_authority_configuration[0].signing_algorithm # Match the CA's signing algorithm
  template_arn                = "arn:aws:acm-pca:::template/RootCACertificate/V1"                                                          # Special template for Root CA's own cert

  validity {
    type  = "YEARS"
    value = 10 # Root CA certificates typically have a long validity
  }

  # This depends_on ensures the CA object exists and its CSR is available.
  depends_on = [aws_acmpca_certificate_authority.private_root_ca]
}

# Step 2: Import the self-signed certificate into the Root CA. This should activate it.
resource "aws_acmpca_certificate_authority_certificate" "private_root_ca_cert_import" {
  certificate_authority_arn = aws_acmpca_certificate_authority.private_root_ca.arn
  certificate               = aws_acmpca_certificate.private_root_ca_self_signed_cert.certificate
  certificate_chain         = aws_acmpca_certificate.private_root_ca_self_signed_cert.certificate_chain # For a root CA, chain is usually just its own cert or null.
                                                                                                       # This output from aws_acmpca_certificate should be correct.
  depends_on = [aws_acmpca_certificate.private_root_ca_self_signed_cert]
}

# Optional: Add a small delay if direct dependency isn't enough due to eventual consistency
resource "time_sleep" "wait_for_ca_activation" {
  depends_on = [aws_acmpca_certificate_authority_certificate.private_root_ca_cert_import]
  create_duration = "30s" # Start with 30s, adjust if needed. Remove if not necessary.
}

# --- Certificate for your specific domain (langfuse.vertice.local) ---
resource "tls_private_key" "domain_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "domain_csr" {
  private_key_pem = tls_private_key.domain_key.private_key_pem
  subject {
    common_name  = var.domain # e.g., langfuse.vertice.local
    organization = "My Organization"
  }
  dns_names = [var.domain]
}

resource "aws_acmpca_certificate" "domain_issued_cert" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.private_root_ca.arn
  certificate_signing_request = tls_cert_request.domain_csr.cert_request_pem
  signing_algorithm           = "SHA256WITHRSA" # Common algorithm for end-entity certs
  template_arn                = "arn:aws:acm-pca:::template/EndEntityCertificate/V1"

  validity {
    type  = "DAYS"
    value = 90 # Shorter validity for end-entity certificates
  }

  # CRITICAL: This must depend on the CA's certificate being imported and the CA becoming active.
  # Using time_sleep here adds a buffer.
  depends_on = [time_sleep.wait_for_ca_activation]
  # If you remove time_sleep, the direct dependency is:
  # depends_on = [aws_acmpca_certificate_authority_certificate.private_root_ca_cert_import]
}

# --- Import into ACM for ALB ---
resource "aws_acm_certificate" "imported_private_cert" {
  private_key       = tls_private_key.domain_key.private_key_pem
  certificate_body  = aws_acmpca_certificate.domain_issued_cert.certificate
  # The certificate chain for an end-entity certificate signed by your Root CA is the Root CA's certificate itself.
  certificate_chain = aws_acmpca_certificate.private_root_ca_self_signed_cert.certificate # This is the Root CA's certificate.

  tags = {
    Name        = "${local.tag_name} (Private)"
    Environment = "internal"
    Domain      = var.domain
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create Route53 zone for the domain
resource "aws_route53_zone" "zone" {
  name = var.domain

  vpc {
    vpc_id = local.vpc_id
  }

  tags = {
    Name = local.tag_name
  }
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

# Create Route53 record for the ALB
resource "aws_route53_record" "langfuse" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}
