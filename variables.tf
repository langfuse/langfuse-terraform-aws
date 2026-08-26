variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "langfuse"
}

variable "domain" {
  description = "Domain name used for resource naming (e.g., company.com)"
  type        = string
}

variable "skip_dns_setup" {
  description = "When true, skips Route53 zone creation, ACM certificate creation, DNS validation records, and the Route53 alias record for the ALB. Use this when DNS and certificate management are handled externally. certificate_arn must be provided alongside this flag. The load_balancer_dns_name and load_balancer_zone_id outputs can then be used to configure DNS records outside this module."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of an existing, externally managed ACM certificate. Required when skip_dns_setup is true."
  type        = string
  default     = null

  validation {
    condition     = var.certificate_arn == null || can(regex("^arn:aws[^:]*:acm:", var.certificate_arn))
    error_message = "certificate_arn must be a valid ACM certificate ARN."
  }

  validation {
    condition     = !var.skip_dns_setup || var.certificate_arn != null
    error_message = "certificate_arn must be provided when skip_dns_setup is true."
  }

  validation {
    condition     = var.certificate_arn == null || var.skip_dns_setup
    error_message = "certificate_arn is only used when skip_dns_setup is true; the module creates and validates its own certificate otherwise."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_id" {
  description = "ID of an existing VPC to reuse"
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id == null || can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must start with 'vpc-' if provided."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (required when using existing VPC)"
  type        = list(string)
  default     = null

  validation {
    condition     = var.vpc_id == null || length(coalesce(var.private_subnet_ids, [])) > 0
    error_message = "private_subnet_ids must be provided when using an existing VPC (vpc_id is set)."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (required when using existing VPC)"
  type        = list(string)
  default     = null

  validation {
    condition     = var.vpc_id == null || length(coalesce(var.public_subnet_ids, [])) > 0
    error_message = "public_subnet_ids must be provided when using an existing VPC (vpc_id is set)."
  }
}

variable "private_route_table_ids" {
  description = "List of private route table IDs (optional when using existing VPC, for S3 VPC Gateway endpoint. If not provided, S3 endpoint will not be created)"
  type        = list(string)
  default     = null
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "use_encryption_key" {
  description = "Whether to use an Encryption key for LLM API credential and integration credential store"
  type        = bool
  default     = true
}

variable "enable_clickhouse_log_tables" {
  description = "Whether to enable Clickhouse logging tables. Having them active produces a high base-load on the EFS filesystem."
  type        = bool
  default     = false
}

variable "postgres_instance_count" {
  description = "Number of PostgreSQL instances to create"
  type        = number
  default     = 2 # Default to 2 instances for high availability
}

variable "postgres_min_capacity" {
  description = "Minimum ACU capacity for PostgreSQL Serverless v2"
  type        = number
  default     = 0.5
}

variable "postgres_max_capacity" {
  description = "Maximum ACU capacity for PostgreSQL Serverless v2"
  type        = number
  default     = 2.0 # Higher default for production readiness
}

variable "postgres_version" {
  description = "PostgreSQL engine version to use"
  type        = string
  default     = "15.12"
}

variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.small"
}

variable "cache_instance_count" {
  description = "Number of ElastiCache instances used in the cluster"
  type        = number
  default     = 2
}

variable "fargate_profile_namespaces" {
  description = "List of Namespaces which are created with a fargate profile"
  type        = list(string)
  default = [
    "default",
    "langfuse",
    "kube-system",
    "cert-manager",
    "clickhouse-operator-system",
  ]
}

variable "use_single_nat_gateway" {
  description = "To use a single NAT Gateway (cheaper), or one per AZ (more resilient)"
  type        = bool
  default     = false
}

variable "langfuse_helm_chart_version" {
  description = "Version of the Langfuse Helm chart to deploy"
  type        = string
  default     = "2.0.0"
}

variable "app_version" {
  description = "Langfuse application version (Docker image tag) to deploy, e.g. \"4.14.0\". Defaults to the latest Langfuse release at the time this module version was published. See https://github.com/langfuse/langfuse/releases."
  type        = string
  default     = "4.14.0"
}

# Resource configuration variables
variable "langfuse_cpu" {
  description = "CPU allocation for Langfuse containers"
  type        = string
  default     = "2"
}

variable "langfuse_memory" {
  description = "Memory allocation for Langfuse containers"
  type        = string
  default     = "4Gi"
}

variable "langfuse_web_replicas" {
  description = "Number of replicas for Langfuse web container"
  type        = number
  default     = 1
  validation {
    condition     = var.langfuse_web_replicas > 0
    error_message = "There must be at least one Langfuse web replica."
  }
}

variable "langfuse_worker_replicas" {
  description = "Number of replicas for Langfuse worker container"
  type        = number
  default     = 1
  validation {
    condition     = var.langfuse_worker_replicas > 0
    error_message = "There must be at least one Langfuse worker replica."
  }
}

variable "clickhouse_replicas" {
  description = "Number of ClickHouse replicas (single shard). The default of 3 provides a highly available setup. Only used when ClickHouse is deployed in-cluster."
  type        = number
  default     = 3
  validation {
    condition     = var.clickhouse_replicas >= 1
    error_message = "clickhouse_replicas must be at least 1."
  }
}

variable "clickhouse_keeper_replicas" {
  description = "Number of ClickHouse Keeper replicas. Must be 1, 3 or 5 to maintain quorum. Only used when ClickHouse is deployed in-cluster."
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 3, 5], var.clickhouse_keeper_replicas)
    error_message = "clickhouse_keeper_replicas must be 1, 3 or 5."
  }
}

variable "clickhouse_cpu" {
  description = "CPU allocation for ClickHouse containers"
  type        = string
  default     = "2"
}

variable "clickhouse_memory" {
  description = "Memory allocation for ClickHouse containers"
  type        = string
  default     = "8Gi"
}

variable "clickhouse_keeper_cpu" {
  description = "CPU allocation for ClickHouse Keeper containers"
  type        = string
  default     = "1"
}

variable "clickhouse_keeper_memory" {
  description = "Memory allocation for ClickHouse Keeper containers"
  type        = string
  default     = "2Gi"
}

variable "clickhouse_storage_size" {
  description = "Nominal size of the persistent volume of each ClickHouse replica. EFS is elastic, so this does not limit the actual storage."
  type        = string
  default     = "8Gi"
}

variable "clickhouse_keeper_storage_size" {
  description = "Nominal size of the persistent volume of each ClickHouse Keeper replica. EFS is elastic, so this does not limit the actual storage."
  type        = string
  default     = "8Gi"
}

variable "clickhouse_operator_chart_version" {
  description = "Version of the ClickHouse operator Helm chart (oci://ghcr.io/clickhouse/clickhouse-operator-helm). The default matches the version the Langfuse Helm chart is tested against."
  type        = string
  default     = "0.0.5"
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager Helm chart. cert-manager issues the certificates for the ClickHouse operator admission webhooks."
  type        = string
  default     = "v1.20.2"
}

variable "external_clickhouse" {
  description = "Use an external ClickHouse deployment (e.g. ClickHouse Cloud) instead of deploying ClickHouse into the EKS cluster. Set external_clickhouse_password as well. Prefix the host with https:// to connect via HTTPS. The defaults match ClickHouse Cloud; set cluster_enabled = false for ClickHouse Cloud on Azure or single-node deployments. When set, no EFS file system is created."
  type = object({
    host            = string
    http_port       = optional(number, 8443)
    native_port     = optional(number, 9440)
    username        = optional(string, "default")
    database        = optional(string, "default")
    cluster_enabled = optional(bool, true)
    migration_ssl   = optional(bool, true)
  })
  default = null
}

variable "external_clickhouse_password" {
  description = "Password for the external ClickHouse user. Required when external_clickhouse is set."
  type        = string
  default     = ""
  sensitive   = true
}

variable "alb_scheme" {
  description = "Scheme for the ALB (internal or internet-facing)"
  type        = string
  default     = "internet-facing"
}

variable "ingress_inbound_cidrs" {
  description = "List of CIDR blocks allowed to access the ingress"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "redis_at_rest_encryption" {
  description = "Whether at-rest encryption is enabled for the Redis cluster"
  type        = bool
  default     = false
}

variable "redis_multi_az" {
  description = "Whether Multi-AZ is enabled for the Redis cluster"
  type        = bool
  default     = false
}

variable "redis_snapshot_retention_limit" {
  description = "Days of automatic Redis snapshots to keep (0 disables backups)"
  type        = number
  default     = 1
}

variable "redis_snapshot_window" {
  description = "Daily UTC window for the automatic Redis snapshot"
  type        = string
  default     = "03:00-04:00"
}

# Additional environment variables
variable "additional_env" {
  description = "Additional environment variables to set on Langfuse pods"
  type = list(object({
    name  = string
    value = optional(string)
    valueFrom = optional(object({
      secretKeyRef = optional(object({
        name = string
        key  = string
      }))
      configMapKeyRef = optional(object({
        name = string
        key  = string
      }))
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for env in var.additional_env :
      (env.value != null && env.valueFrom == null) || (env.value == null && env.valueFrom != null)
    ])
    error_message = "Each environment variable must have either 'value' or 'valueFrom' specified, but not both."
  }
}
