variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "langfuse"
}

variable "domain" {
  description = "Domain name used for resource naming (e.g., company.com)"
  type        = string
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
    condition     = var.vpc_id == null || (var.private_subnet_ids != null && length(var.private_subnet_ids) > 0)
    error_message = "private_subnet_ids must be provided when using an existing VPC (vpc_id is set)."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (required when using existing VPC)"
  type        = list(string)
  default     = null

  validation {
    condition     = var.vpc_id == null || (var.public_subnet_ids != null && length(var.public_subnet_ids) > 0)
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
  default     = "15.5"
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

variable "clickhouse_instance_count" {
  description = "Number of ClickHouse instances used in the cluster"
  type        = number
  default     = 3
}

variable "fargate_profile_namespaces" {
  description = "List of Namespaces which are created with a fargate profile"
  type        = list(string)
  default = [
    "default",
    "langfuse",
    "kube-system",
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
  default     = "1.5.9"
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
  description = "Number of replicas of ClickHouse containers"
  type        = number
  default     = 3
  validation {
    condition     = var.clickhouse_replicas > 1
    error_message = "There must be at least two clickhouse replicas for high availability."
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
