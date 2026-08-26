# Langfuse with DNS and TLS managed outside this module, for example when the
# domain is hosted at a registrar other than Route53.
#
# The module then creates no Route53 zone, no ACM certificate and no alias
# record. Point your own DNS at the load_balancer_dns_name output once the
# apply completes.
module "langfuse" {
  source = "../.."

  domain = "langfuse.example.com"

  # Bring your own DNS and certificate. Both settings go together: the
  # certificate must already be issued and validated in the same region.
  skip_dns_setup  = true
  certificate_arn = "arn:aws:acm:eu-central-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"

  # Optional: pin the Langfuse application version
  app_version = "4.19.0"
}

output "load_balancer_dns_name" {
  description = "Create a CNAME or alias record for the domain pointing here."
  value       = module.langfuse.load_balancer_dns_name
}

output "load_balancer_zone_id" {
  description = "Hosted zone ID of the ALB, for a Route53 alias record in another account."
  value       = module.langfuse.load_balancer_zone_id
}
provider "kubernetes" {
  host                   = module.langfuse.cluster_host
  cluster_ca_certificate = module.langfuse.cluster_ca_certificate
  token                  = module.langfuse.cluster_token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.langfuse.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.langfuse.cluster_host
    cluster_ca_certificate = module.langfuse.cluster_ca_certificate
    token                  = module.langfuse.cluster_token

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.langfuse.cluster_name]
    }
  }
}
