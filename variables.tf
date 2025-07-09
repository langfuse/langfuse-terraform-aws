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

variable "kubernetes_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "use_encryption_key" {
  description = "Wheter or not to use an Encryption key for LLM API credential and integration credential store"
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
  default     = "1.2.15"
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

variable "existing_certificate_arn" {
  description = "ARN of existing ACM certificate to use instead of creating a new one"
  type        = string
  default     = null
}
