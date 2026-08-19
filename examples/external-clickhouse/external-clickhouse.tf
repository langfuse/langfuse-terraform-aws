# Deploys Langfuse against an external ClickHouse (e.g. ClickHouse Cloud)
# instead of running ClickHouse inside the EKS cluster. With an external
# ClickHouse configured, the module does not install cert-manager, the
# ClickHouse operator, an in-cluster ClickHouse, or the EFS file system.

variable "clickhouse_password" {
  description = "Password of the external ClickHouse user"
  type        = string
  sensitive   = true
}

module "langfuse" {
  source = "../.."

  domain = "langfuse.example.com"

  # ClickHouse Cloud connection. The defaults match ClickHouse Cloud:
  # HTTPS on port 8443 and the TLS native protocol on port 9440.
  external_clickhouse = {
    host = "https://abc123.us-east-1.aws.clickhouse.cloud"

    # Uncomment for ClickHouse Cloud on Azure or single-node deployments:
    # cluster_enabled = false

    # For a self-managed ClickHouse without TLS instead:
    # host          = "clickhouse.internal.example.com"
    # http_port     = 8123
    # native_port   = 9000
    # migration_ssl = false
  }
  external_clickhouse_password = var.clickhouse_password
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
