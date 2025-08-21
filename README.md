![GitHub Banner](https://github.com/langfuse/langfuse-k8s/assets/2834609/2982b65d-d0bc-4954-82ff-af8da3a4fac8)

# AWS Langfuse Terraform module

> This module is a pre-release version and its interface may change.
> Please review the changelog between each release and create a GitHub issue for any problems or feature requests.

This repository contains a Terraform module for deploying [Langfuse](https://langfuse.com/) - the open-source LLM observability platform - on AWS.
This module aims to provide a production-ready, secure, and scalable deployment using managed services whenever possible.

## Usage

1. Set up the module with the settings that suit your need. A minimal installation requires a `domain` which is under your control. Configure the kubernetes and helm providers to connect to the EKS cluster.

```hcl
module "langfuse" {
  source = "github.com/langfuse/langfuse-terraform-aws?ref=0.4.2"

  domain = "langfuse.example.com"

  # Optional use a different name for your installation
  # e.g. when using the module multiple times on the same AWS account
  name   = "langfuse"

  # Optional: Configure Langfuse
  # use_encryption_key = false # Disable encryption (default is true for security)

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

  # Optional: Configure Langfuse Helm chart version
  langfuse_helm_chart_version = "1.4.1"

  # Optional: Add additional environment variables
  additional_env = [
    # Direct value
    {
      name  = "CUSTOM_ENV_VAR"
      value = "custom-value"
    },
    # Reference to Kubernetes secret
    {
      name = "DATABASE_PASSWORD"
      valueFrom = {
        secretKeyRef = {
          name = "my-database-secret"
          key  = "password"
        }
      }
    }
  ]
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
```

You can also navigate into the `examples/quickstart` directory and run the example there.

2. Apply the DNS zone

```bash
terraform init
terraform apply --target module.langfuse.aws_route53_zone.zone
```

3. Set up the Nameserver delegation on your DNS provider, e.g.

```bash
$ dig NS langfuse.example.com
ns-1.awsdns-00.org.
ns-2.awsdns-01.net.
ns-3.awsdns-02.com.
ns-4.awsdns-03.co.uk.
```

4. Apply the full stack. If this fails, run through the commands under Known Issues, and then re-run the apply command.

```bash
terraform apply
```

### Known issues

Due to a race-condition between the Fargate Profile creation and the Kubernetes pod scheduling, on the initial system creation the CoreDNS containers, and the ClickHouse containers must be restarted:

```bash
# Connect your kubectl to the EKS cluster
aws eks update-kubeconfig --name langfuse

# Restart the CoreDNS and ClickHouse containers
kubectl --namespace kube-system rollout restart deploy coredns
kubectl --namespace langfuse delete pod langfuse-clickhouse-shard0-{0,1,2} langfuse-zookeeper-{0,1,2}
```

Afterward, your installation should become fully available.
Navigate to your domain, e.g. langfuse.example.com, to access the Langfuse UI.

## Architecture

![lanfuse-v3-on-aws](./images/langfuse-v3-on-aws.svg)

> :information_source: For more information on Langfuse's architecture, please check [the official documentation](https://langfuse.com/self-hosting#architecture)

## Resource Configuration

This module provides configurable resource allocation for all container workloads to ensure optimal performance in production environments. On AWS EKS Fargate, resource requests and limits are set to the same value for each container.
The default values are based on the recommendations from the [Langfuse K8s documentation](https://github.com/langfuse/langfuse-k8s) and [Bitnami ClickHouse chart documentation](https://github.com/bitnami/charts/tree/main/bitnami/clickhouse).

### Default Resource Allocations

- **Langfuse containers** (web and worker): 2 CPU, 4 GiB memory
- **ClickHouse containers**: 2 CPU, 8 GiB memory
- **ClickHouse Keeper containers**: 1 CPU, 2 GiB memory

These defaults provide a good starting point for production workloads, but you can adjust them based on your specific requirements by setting the corresponding variables in your Terraform configuration.

### Customizing Resources

You can override any of the resource configurations by setting the appropriate variables.
For example, to increase ClickHouse Keeper resources:

```hcl
module "langfuse" {
  source = "github.com/langfuse/langfuse-terraform-aws?ref=0.2.6"

  domain = "langfuse.example.com"

  # Increase ClickHouse Keeper resources
  clickhouse_keeper_cpu    = "2"
  clickhouse_keeper_memory = "4Gi"
}
```

## Features

This module creates a complete Langfuse stack with the following components:

- VPC with public and private subnets
- EKS cluster with Fargate compute
- Aurora PostgreSQL Serverless v2 cluster
- ElastiCache Redis cluster
- S3 bucket for storage
- TLS certificates and Route53 DNS configuration
- Required IAM roles and security groups
- AWS Load Balancer Controller for ingress
- EFS CSI Driver for persistent storage

## Requirements

| Name       | Version |
| ---------- | ------- |
| terraform  | >= 1.0  |
| aws        | >= 5.0  |
| kubernetes | >= 2.10 |
| helm       | >= 2.5  |

## Providers

| Name       | Version |
| ---------- | ------- |
| aws        | >= 5.0  |
| kubernetes | >= 2.10 |
| helm       | >= 2.5  |
| random     | >= 3.0  |
| tls        | >= 3.0  |

## Resources

| Name                                    | Type     |
| --------------------------------------- | -------- |
| aws_eks_cluster.langfuse                | resource |
| aws_eks_fargate_profile.namespaces      | resource |
| aws_rds_cluster.postgres                | resource |
| aws_elasticache_replication_group.redis | resource |
| aws_s3_bucket.langfuse                  | resource |
| aws_acm_certificate.cert                | resource |
| aws_route53_zone.zone                   | resource |
| aws_iam_role.eks                        | resource |
| aws_iam_role.fargate                    | resource |
| aws_security_group.eks                  | resource |
| aws_security_group.postgres             | resource |
| aws_security_group.redis                | resource |
| aws_security_group.vpc_endpoints        | resource |

## Inputs

| Name                       | Description                                                                                    | Type         | Default                                | Required |
| -------------------------- | ---------------------------------------------------------------------------------------------- | ------------ |----------------------------------------| :------: |
| name                       | Name prefix for resources                                                                      | string       | "langfuse"                             |    no    |
| domain                     | Domain name used for resource naming                                                           | string       | n/a                                    |   yes    |
| vpc_cidr                   | CIDR block for VPC                                                                             | string       | "10.0.0.0/16"                          |    no    |
| use_single_nat_gateway     | To use a single NAT Gateway (cheaper) or one per AZ (more resilient)                           | bool         | true                                   |    no    |
| kubernetes_version         | Kubernetes version for EKS cluster                                                             | string       | "1.32"                                 |    no    |
| use_encryption_key         | Wheter or not to use an Encryption key for LLM API credential and integration credential store | bool         | true                                   |    no    |
| fargate_profile_namespaces | List of namespaces to create Fargate profiles for                                              | list(string) | ["default", "langfuse", "kube-system"] |    no    |
| postgres_instance_count    | Number of PostgreSQL instances                                                                 | number       | 2                                      |    no    |
| postgres_min_capacity      | Minimum ACU capacity for PostgreSQL Serverless v2                                              | number       | 0.5                                    |    no    |
| postgres_max_capacity      | Maximum ACU capacity for PostgreSQL Serverless v2                                              | number       | 2.0                                    |    no    |
| cache_node_type            | ElastiCache node type                                                                          | string       | "cache.t4g.small"                      |    no    |
| cache_instance_count       | Number of ElastiCache instances                                                                | number       | 1                                      |    no    |
| langfuse_helm_chart_version | Version of the Langfuse Helm chart to deploy                                                  | string       | "1.4.1"                                |    no    |
| langfuse_cpu               | CPU allocation for Langfuse containers                                                        | string       | "2"                                    |    no    |
| langfuse_memory            | Memory allocation for Langfuse containers                                                     | string       | "4Gi"                                  |    no    |
| clickhouse_cpu             | CPU allocation for ClickHouse containers                                                      | string       | "2"                                    |    no    |
| clickhouse_memory          | Memory allocation for ClickHouse containers                                                   | string       | "8Gi"                                  |    no    |
| clickhouse_keeper_cpu      | CPU allocation for ClickHouse Keeper containers                                               | string       | "1"                                    |    no    |
| clickhouse_keeper_memory   | Memory allocation for ClickHouse Keeper containers                                            | string       | "2Gi"                                  |    no    |
| alb_scheme                 | ALB scheme                                                                                    | string       | "internet-facing"                      |    no    |
| ingress_inbound_cidrs      | Allowed CIDR blocks for ingress alb                                                           | list(string) | ["0.0.0.0/0"]                          |    no    |
| redis_at_rest_encryption   | At rest encryption enabled for the redis cluster                                              | bool         | false                                  |    no    |
| redis_multi_az             | Multi availability zone enabled for the redis cluster                                         | bool         | false                                  |    no    |

## Outputs

| Name                   | Description                      |
| ---------------------- | -------------------------------- |
| cluster_name           | EKS Cluster Name                 |
| cluster_host           | EKS Cluster endpoint             |
| cluster_ca_certificate | EKS Cluster CA certificate       |
| cluster_token          | EKS Cluster authentication token |
| private_subnet_ids     | Private subnet IDs from VPC      |
| public_subnet_ids      | Public subnet IDs from VPC       |
| bucket_name            | S3 bucket name for Langfuse      |
| bucket_id              | S3 bucket ID for Langfuse        |
| route53_nameservers    | Route53 zone nameservers         |

## Support

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
- [Join Langfuse Discord](https://langfuse.com/discord)

## License

MIT Licensed. See LICENSE for full details.
