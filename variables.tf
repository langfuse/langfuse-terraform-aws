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

variable "vpc_id" {
  description = "VPC ID to use for the cluster, overrides the VPC CIDR"
  type        = string
  default     = null
}

variable "private_subnets" {
  description = "Private subnets in which to create the cluster"
  type        = list(string)
  default     = null
}

variable "public_subnets" {
  description = "Public subnets in which to create the cluster"
  type        = list(string)
  default     = null
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block to use for the cluster, overrides the VPC CIDR"
  type        = string
  default     = null
}

# Define an input variable to choose the cache engine
variable "cache_engine_type" {
  description = "The type of cache engine to deploy. Valid values are 'redis' or 'valkey'."
  type        = string
  default     = "valkey" # Default to Redis

  validation {
    condition     = contains(["redis", "valkey"], var.cache_engine_type)
    error_message = "Allowed values for cache_engine_type are 'redis' or 'valkey'."
  }
}

variable "eks_admin_role_arn" {
  description = "The ARN of the AgentAdmin IAM role to grant EKS admin access."
  type        = string
}

variable "public_endpoint" {
  description = "Public endpoint for langfuse"
  type        = bool
  default     = true
}

variable "public_zone" {
  description = "Zone where to deploy the langfuse subdomain"
  type        = string
  default     = null
}

variable "enable_okta" {
  description = "Enable SSO for the cluster"
  type        = bool
  default     = false
}

variable "okta_settings" {
  description = "Okta settings for authentication."
  type = object({
    client_id                  = string
    client_secret_secrets_name = string
    issuer                     = string
  })
  default = null
}
