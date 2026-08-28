terraform {
  # 1.9 is the first release that lets a variable validation block reference
  # another variable, which the name length and AI feature validations in
  # variables.tf rely on.
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Bounded deliberately: an open-ended constraint silently adopts the next
      # provider major, which removes attributes this module uses.
      # 6.61 is the first release with aws_lambdacore_network_connector.
      version = ">= 6.61, < 7.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.7" # OCI registry support is required for the ClickHouse operator chart
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}
