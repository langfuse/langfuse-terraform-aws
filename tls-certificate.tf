# 1. S3 Bucket for Certificate Revocation List (CRL)
resource "aws_s3_bucket" "crl_bucket" {
  bucket_prefix = "acmpca-crl-${var.name}-"
  force_destroy = true # Consider for non-production. For production, manage lifecycle carefully.

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

# 2. Create a Root Certificate Authority
resource "aws_acmpca_certificate_authority" "private_root_ca" {
  type = "ROOT" # For purely internal use, a ROOT CA is often simplest.
  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"
    subject {
      common_name  = "internal-ca.${var.domain}" # e.g., internal-ca.langfuse.vertice.local
      organization = "My Organization Internal CA"
    }
  }

  revocation_configuration {
    crl_configuration {
      enabled            = true
      expiration_in_days = 7
      s3_bucket_name     = aws_s3_bucket.crl_bucket.id
      s3_object_acl      = "BUCKET_OWNER_FULL_CONTROL" # Or "PUBLIC_READ" if CRL needs to be public within network
    }
  }

  enabled                         = true # Creates the CA and makes it active with its self-signed certificate.
  permanent_deletion_time_in_days = 7    # For non-prod, allows quicker deletion. Remove or increase for prod.

  tags = {
    Name        = "${local.tag_name}-Private-Root-CA"
    Environment = "internal"
  }

  depends_on = [aws_s3_bucket_policy.crl_bucket_policy]
}

# ------------------------------------------------------------------------------
# Issue Certificate for your .local domain
# ------------------------------------------------------------------------------

# 3. Generate a private key for your domain certificate
resource "tls_private_key" "domain_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 4. Generate a Certificate Signing Request (CSR)
resource "tls_cert_request" "domain_csr" {
  private_key_pem = tls_private_key.domain_key.private_key_pem
  subject {
    common_name  = var.domain # This will be langfuse.vertice.local
    organization = "My Organization"
  }
  dns_names = [var.domain]
  # ip_addresses = ["10.0.1.10"] # Optional: if you need to include IP addresses
}

# 5. Issue the certificate using your Private CA
resource "aws_acmpca_certificate" "domain_issued_cert" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.private_root_ca.arn
  certificate_signing_request = tls_cert_request.domain_csr.cert_request_pem
  signing_algorithm           = "SHA256WITHRSA" # Must be supported by the CA

  # Use a standard template for end-entity server certificates
  template_arn = "arn:aws:acm-pca:::template/EndEntityCertificate/V1"

  validity {
    type  = "DAYS"
    value = 90 # Recommended to keep validity periods for end-entity certs short
  }

  depends_on = [aws_acmpca_certificate_authority.private_root_ca]
}

# 6. Import the issued private certificate into ACM
# This makes it available for services like ALB, CloudFront (though CF needs public certs)
resource "aws_acm_certificate" "cert" { # Re-using your original resource name "cert"
  private_key       = tls_private_key.domain_key.private_key_pem
  certificate_body  = aws_acmpca_certificate.domain_issued_cert.certificate
  # The certificate chain for a certificate issued by a Root CA is the Root CA's certificate itself.
  certificate_chain = aws_acmpca_certificate_authority.private_root_ca.certificate

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
