![GitHub Banner](https://github.com/langfuse/langfuse-k8s/assets/2834609/2982b65d-d0bc-4954-82ff-af8da3a4fac8)

# AWS Langfuse Terraform module

> ⚠️ This module is under active development and its interface may change.
> Please review the changelog between each release and create a GitHub issue for any problems or feature requests.

This repository contains a Terraform module for deploying [Langfuse](https://langfuse.com/) - the open-source LLM observability platform - on AWS.
This module aims to provide a production-ready, secure, and scalable deployment using managed services whenever possible.

## Usage

1. Set up the module with the settings that suit your need. A minimal installation requires a `domain` which is under your control.

```hcl
module "langfuse" {
  source = "github.com/langfuse/langfuse-aws?ref=v0.1.0"

  domain = "langfuse.example.com"
  
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

4. Apply the full stack

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

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |
| kubernetes | >= 2.10 |
| helm | >= 2.5 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |
| kubernetes | >= 2.10 |
| helm | >= 2.5 |
| random | >= 3.0 |
| tls | >= 3.0 |

## Resources

| Name | Type |
|------|------|
| aws_eks_cluster.langfuse | resource |
| aws_eks_fargate_profile.namespaces | resource |
| aws_rds_cluster.postgres | resource |
| aws_elasticache_replication_group.redis | resource |
| aws_s3_bucket.langfuse | resource |
| aws_acm_certificate.cert | resource |
| aws_route53_zone.zone | resource |
| aws_iam_role.eks | resource |
| aws_iam_role.fargate | resource |
| aws_security_group.eks | resource |
| aws_security_group.postgres | resource |
| aws_security_group.redis | resource |
| aws_security_group.vpc_endpoints | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name prefix for resources | string | "langfuse" | no |
| domain | Domain name used for resource naming | string | n/a | yes |
| vpc_cidr | CIDR block for VPC | string | "10.0.0.0/16" | no |
| use_single_nat_gateway | To use a single NAT Gateway (cheaper) or one per AZ (more resilient) | bool | true | no |
| kubernetes_version | Kubernetes version for EKS cluster | string | "1.32" | no |
| fargate_profile_namespaces | List of namespaces to create Fargate profiles for | list(string) | ["default", "langfuse", "kube-system"] | no |
| postgres_instance_count | Number of PostgreSQL instances | number | 2 | no |
| postgres_min_capacity | Minimum ACU capacity for PostgreSQL Serverless v2 | number | 0.5 | no |
| postgres_max_capacity | Maximum ACU capacity for PostgreSQL Serverless v2 | number | 2.0 | no |
| cache_node_type | ElastiCache node type | string | "cache.t4g.small" | no |
| cache_instance_count | Number of ElastiCache instances | number | 1 | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | EKS Cluster Name |
| cluster_host | EKS Cluster endpoint |
| cluster_ca_certificate | EKS Cluster CA certificate |
| cluster_token | EKS Cluster authentication token |

## Support

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
- [Join Langfuse Discord](https://langfuse.com/discord)

## License

MIT Licensed. See LICENSE for full details.
