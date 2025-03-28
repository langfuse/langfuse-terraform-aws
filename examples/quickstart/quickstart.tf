module "langfuse" {
  source = "../.."

  domain = "aws-test.langfuse.com"

  # Optional use a different name for your installation
  # e.g. when using the module multiple times on the same AWS account
  name   = "langfuse"

  # Optional: Configure the VPC
  vpc_cidr = "10.0.0.0/16"
  use_single_nat_gateway = false  # Using a single NAT gateway decreases costs, but is less resilient

  # Optional: Configure the Kubernetes cluster
  kubernetes_version = "1.32"
  fargate_profile_namespaces = ["kube-system", "langfuse", "default"]

  # Optional: Configure the database instances
  postgres_instance_count = 2
  postgres_min_capacity = 0.5
  postgres_max_capacity = 2.0

  # Optional: Configure the cache
  cache_node_type = "cache.t4g.small"
  cache_instance_count = 2
}