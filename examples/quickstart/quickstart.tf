module "langfuse" {
  source = "../.."

  domain = "langfuse.renovacloud.io"

  # Optional use a different name for your installation
  # e.g. when using the module multiple times on the same AWS account
  name = "langfuse"

  # Optional: Configure Langfuse
  use_encryption_key = true # Enable encryption for sensitive data stored in Langfuse

  # Optional: Configure the VPC
  vpc_id                       = "vpc-0ee4c1a66725b1d42"
  public_subnets               = ["subnet-081e560d30829197d", "subnet-010894193d47a0ce9"]
  private_subnets              = ["subnet-0494e9edc9f31d4bb", "subnet-0f0e9f440615dfb63"]
  vpc_cidr_block               = "10.200.48.0/20"
  use_single_nat_gateway = false # Using a single NAT gateway decreases costs, but is less resilient

  # Optional: Configure the Kubernetes cluster
  kubernetes_version         = "1.33"
  fargate_profile_namespaces = ["kube-system", "langfuse", "default"]

  # Optional: Configure the database instances
  postgres_instance_class = "db.t3.large"
  postgres_instance_count = 2
  postgres_min_capacity   = 0.5
  postgres_max_capacity   = 2.0

  # Optional: Configure the cache
  cache_node_type      = "cache.t4g.small"
  cache_instance_count = 2

  # Optional: Configure Langfuse Helm chart version
  langfuse_helm_chart_version = "1.5.0"
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
