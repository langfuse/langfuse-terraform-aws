variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "langfuse"

  validation {
    condition     = !(var.enable_code_based_eval_executors || var.enable_agent_sandbox_microvm) || length(var.name) <= 32
    error_message = "name must be at most 32 characters when code-based eval executors or the agent sandbox are enabled, to fit Lambda and IAM naming limits."
  }
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
  default     = "1.36"
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
  description = "Version of the Langfuse Helm chart to deploy. The AI features need 2.1.0 or newer, which is where langfuse.aiFeatures.* was added."
  type        = string
  default     = "2.1.0"

  validation {
    # try() keeps a non-semver tag working: a deliberate custom build is left
    # alone rather than rejected. It is also required rather than cosmetic,
    # because || does not short-circuit here, so the regex is evaluated even
    # when the version does not match it.
    condition = !var.enable_ai_features || (
      try(tonumber(regex("^(\\d+)\\.(\\d+)", var.langfuse_helm_chart_version)[0]), 99) > 2 ||
      (try(tonumber(regex("^(\\d+)\\.(\\d+)", var.langfuse_helm_chart_version)[0]), 99) == 2 &&
      try(tonumber(regex("^(\\d+)\\.(\\d+)", var.langfuse_helm_chart_version)[1]), 99) >= 1)
    )
    error_message = "The AI features need langfuse_helm_chart_version 2.1.0 or newer, which is where langfuse.aiFeatures.* was added. Helm ignores unknown values silently, so an older chart would deploy without them and report nothing."
  }
}

variable "app_version" {
  description = "Langfuse application version (Docker image tag) to deploy, e.g. \"4.25.0\". Defaults to the latest Langfuse release at the time this module version was published. The AI features require >= 4.25. That floor is written without a patch component on purpose, so update-langfuse-versions.yml cannot rewrite it when it moves this default. See https://github.com/langfuse/langfuse/releases."
  type        = string
  default     = "4.25.0"
}

variable "helm_release_timeout" {
  description = "Seconds to wait for the Langfuse Helm release to become ready. Fargate cold starts, and bringing up ClickHouse and Keeper on EFS-backed volumes, take longer than the Helm provider's default 300s."
  type        = number
  default     = 900
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
  default     = true
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

variable "enable_code_based_eval_executors" {
  description = "Create tenant-isolated, network-isolated Lambda executors for code-based evals and configure Langfuse to use them."
  type        = bool
  default     = false
}

variable "code_based_eval_vpc_cidr" {
  description = "Deprecated: renamed to isolated_execution_vpc_cidr in 1.2.0, because the VPC is now shared with the agent sandbox. Still honoured when set. Remove it and use isolated_execution_vpc_cidr instead."
  type        = string
  default     = null

  validation {
    condition     = var.code_based_eval_vpc_cidr == null || var.isolated_execution_vpc_cidr == null
    error_message = "Set either code_based_eval_vpc_cidr (deprecated) or isolated_execution_vpc_cidr, not both."
  }
}

variable "isolated_execution_vpc_cidr" {
  description = "CIDR block for the shared isolated VPC that runs untrusted code: the code evaluator Lambdas and the agent sandbox MicroVMs. Defaults to 10.1.0.0/24. Must not overlap vpc_cidr. Null rather than a literal default so the deprecated code_based_eval_vpc_cidr can be told apart from this one being left alone."
  type        = string
  default     = null

  validation {
    condition = var.isolated_execution_vpc_cidr == null || (
      can(cidrnetmask(var.isolated_execution_vpc_cidr)) &&
      can(cidrsubnet(var.isolated_execution_vpc_cidr, 2, 2)) &&
      can(regex("/(?:[0-9]|1[0-9]|2[0-6])$", var.isolated_execution_vpc_cidr))
    )
    error_message = "isolated_execution_vpc_cidr must be a valid IPv4 CIDR with a /26 or shorter prefix so it can contain three AWS-valid subnets."
  }
}

variable "code_based_eval_executor_lambda_settings" {
  description = "Per-runtime resource settings for code-based eval executor Lambdas. Lambda CPU is allocated proportionally to memory."
  type = object({
    python = object({
      memory_size                    = number
      timeout                        = number
      reserved_concurrent_executions = number
    })
    node = object({
      memory_size                    = number
      timeout                        = number
      reserved_concurrent_executions = number
    })
  })
  default = {
    python = {
      memory_size                    = 128
      timeout                        = 2
      reserved_concurrent_executions = 50
    }
    node = {
      memory_size                    = 128
      timeout                        = 2
      reserved_concurrent_executions = 50
    }
  }

  validation {
    condition = alltrue([
      for settings in values(var.code_based_eval_executor_lambda_settings) :
      settings.memory_size >= 128 &&
      settings.memory_size <= 10240 &&
      settings.timeout >= 1 &&
      settings.timeout <= 900 &&
      settings.reserved_concurrent_executions >= 0
    ])
    error_message = "Each executor must use 128-10240 MB memory, a 1-900 second timeout, and non-negative reserved concurrency."
  }
}

variable "code_eval_execution_worker_concurrency" {
  description = "Code eval execution queue processing concurrency for each Langfuse worker pod."
  type        = number
  default     = 5

  validation {
    condition     = var.code_eval_execution_worker_concurrency > 0 && floor(var.code_eval_execution_worker_concurrency) == var.code_eval_execution_worker_concurrency
    error_message = "code_eval_execution_worker_concurrency must be a positive integer."
  }
}

# AI features (in-app agent, Ask AI). See https://langfuse.com/security/ai-features
variable "enable_ai_features" {
  description = "Render the chart's langfuse.aiFeatures values and grant Bedrock invoke on the Langfuse role. Requires ai_features_provider and ai_features_model, Langfuse >= 4.25 and Helm chart >= 2.1.0. Terraform-only: there is no matching application environment variable, and AI features are additionally gated per organization inside Langfuse."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_ai_features || (var.ai_features_provider != null && var.ai_features_model != null)
    error_message = "ai_features_provider and ai_features_model are required when enable_ai_features is true."
  }

  validation {
    condition     = var.enable_ai_features || var.ai_features_provider == null
    error_message = "ai_features_provider is set but enable_ai_features is false, so nothing would be rendered. Set enable_ai_features to true, or remove the provider."
  }
}

variable "ai_features_provider" {
  description = "Provider for the instance-wide Langfuse AI model, set as LANGFUSE_AI_PROVIDER. Only \"bedrock\" needs AWS resources from this module; \"anthropic\" and \"openai\" additionally need LANGFUSE_AI_API_KEY via additional_env. Leave null to leave the AI features unconfigured."
  type        = string
  default     = null

  validation {
    # Terraform 1.9 evaluates both sides of the ||, so the fallback has to be a
    # non-empty string: coalesce rejects "" as well as null.
    condition     = var.ai_features_provider == null || contains(["bedrock", "anthropic", "openai"], coalesce(var.ai_features_provider, "unset"))
    error_message = "ai_features_provider must be one of \"bedrock\", \"anthropic\", or \"openai\"."
  }

}

variable "ai_features_model" {
  description = "Primary model for the AI features, set as LANGFUSE_AI_MODEL, for example \"eu.anthropic.claude-opus-5\". Claude Opus 5 is the recommended model. For Bedrock, activate the model in the Bedrock model catalog first."
  type        = string
  default     = null
}

variable "ai_features_small_model" {
  description = "Optional model for supplementary calls such as conversation titles, set as LANGFUSE_AI_SMALL_MODEL. Falls back to ai_features_model when unset."
  type        = string
  default     = null
}

variable "ai_features_api_key" {
  description = "API key for the anthropic and openai providers, stored in the langfuse Kubernetes secret and referenced by LANGFUSE_AI_API_KEY. Bedrock authenticates through the AWS credential chain instead and does not use it."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.ai_features_provider == null || var.ai_features_provider == "bedrock" || var.ai_features_api_key != null
    error_message = "ai_features_api_key is required for the anthropic and openai providers. Bedrock uses the AWS credential chain and needs no key."
  }

  validation {
    condition     = var.ai_features_provider != "bedrock" || var.ai_features_api_key == null
    error_message = "ai_features_api_key is not used by the bedrock provider, which authenticates through the AWS credential chain. Remove it, or switch provider."
  }
}

variable "ai_features_base_url" {
  description = "Base URL for the anthropic and openai providers, set as LANGFUSE_AI_BASE_URL. For openai include the /v1 suffix. Leave null to use the provider default. Unused by bedrock."
  type        = string
  default     = null
}

variable "ai_features_bedrock_region" {
  description = "Region for Bedrock model invocations, set as LANGFUSE_AI_AWS_BEDROCK_REGION. Defaults to the region this module deploys into."
  type        = string
  default     = null
}

variable "ai_features_bedrock_model_arns" {
  description = "Bedrock model ARNs the Langfuse role may invoke. The default allows every model, which is cost exposure rather than privilege; narrow it to pin specific models or inference profiles."
  type        = list(string)
  default     = ["*"]

  validation {
    condition     = length(var.ai_features_bedrock_model_arns) > 0
    error_message = "ai_features_bedrock_model_arns must not be empty."
  }
}

variable "enable_in_app_agent" {
  description = "Set LANGFUSE_IN_APP_AGENT_ENABLED on web and worker. Requires ai_features_provider and ai_features_model, and Langfuse >= 4.25."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_in_app_agent || var.enable_ai_features
    error_message = "enable_ai_features must be true when enable_in_app_agent is true; the agent runs on the instance-wide Langfuse AI model."
  }
}

variable "enable_agent_sandbox_microvm" {
  description = "Create the AWS Lambda MicroVM sandbox that backs the in-app agent's file and code execution tools, and set LANGFUSE_IN_APP_AGENT_SANDBOX_* on the worker. The MicroVM image is built out of band after apply; see the README. Available only in commercial AWS regions."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_agent_sandbox_microvm || var.enable_in_app_agent
    error_message = "enable_in_app_agent must be true when enable_agent_sandbox_microvm is true; the sandbox is only used by the in-app agent."
  }
}

variable "agent_sandbox_image_name" {
  description = "Lambda MicroVM image name. The image ARN is constructed from it, so Terraform can grant permissions before the image exists; create the image with build-microvm-image.sh after apply using the agent_sandbox_build_env output."
  type        = string
  default     = "langfuse-in-app-agent-sandbox"
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
