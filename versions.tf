terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.79.0"
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
      version = "~> 2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  profile = "di"
  region  = "us-east-1"
}

provider "kubernetes" {
  host                   = aws_eks_cluster.langfuse.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.langfuse.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.langfuse.token
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.langfuse.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.langfuse.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.langfuse.token
  }
}

