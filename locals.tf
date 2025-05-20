locals {
  tag_name        = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"

  create_vpc           = var.vpc_id == null || var.private_subnets == null || var.vpc_cidr_block == null  ? true : false
  private_subnets_list = local.create_vpc && var.private_subnets != null ? var.private_subnets : []
  vpc_id               = local.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnets      = local.create_vpc ? module.vpc[0].private_subnets : local.private_subnets_list
  vpc_cidr_block       = local.create_vpc ? module.vpc[0].vpc_cidr_block : var.vpc_cidr_block

  tag_name_prefix  = "LangfuseApp"

  # Engine-specific configurations
  engine_config = {
    redis = {
      name_suffix           = "redis"
      engine                = "redis"
      engine_version        = "7.0"
      parameter_group_family = "redis7" # For cluster mode disabled or single node
      port                  = 6379
      description           = "Redis"
    }
    valkey = {
      name_suffix           = "valkey"
      engine                = "valkey"
      engine_version        = "7.2" 
      parameter_group_family = "valkey7" # For cluster mode disabled or single node
      port                  = 6379
      description           = "Valkey"
    }
  }
  selected_engine_config = local.engine_config[var.cache_engine_type]
  resource_name_suffix   = local.selected_engine_config.name_suffix
  common_tag_name        = "${local.tag_name_prefix} ${local.selected_engine_config.description}" # Used for generic resource tagging
}