module "langfuse" {
  source = "../.."

  domain = "langfuse.example.com"

  # Optional use a different name for your installation
  # e.g. when using the module multiple times on the same AWS account
  name = "langfuse"

  # Optional: Configure Langfuse
  use_encryption_key = true # Enable encryption for sensitive data stored in Langfuse

  # Optional: Configure the VPC
  vpc_cidr               = "10.0.0.0/16"
  use_single_nat_gateway = false # Using a single NAT gateway decreases costs, but is less resilient

  # Optional: Configure the Kubernetes cluster
  kubernetes_version         = "1.36"
  fargate_profile_namespaces = ["kube-system", "langfuse", "default", "cert-manager", "clickhouse-operator-system"]

  # Optional: Configure the database instances
  postgres_instance_count = 2
  postgres_min_capacity   = 0.5
  postgres_max_capacity   = 2.0

  # Optional: Configure the cache
  cache_node_type      = "cache.t4g.small"
  cache_instance_count = 2

  # Optional: Configure Langfuse Helm chart version
  langfuse_helm_chart_version = "2.0.2"

  # Optional: Pin the Langfuse application version (defaults to the latest
  # release at the time this module version was published)
  app_version = "4.25.0"

  # Optional: Langfuse AI features (in-app agent, Ask AI). Requires app_version
  # >= 4.24. The agent sandbox image is built out of band after apply.
  # ai_features_provider         = "bedrock"
  # ai_features_model            = "eu.anthropic.claude-opus-5"
  # ai_features_small_model      = "eu.anthropic.claude-haiku-4-5-20251001-v1:0"
  # enable_in_app_agent          = true
  # enable_agent_sandbox_microvm = true
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
