locals {
  tag_name        = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"

  vpc_id          = local.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnets = local.create_vpc ? module.vpc[0].private_subnets : var.private_subnets
  vpc_cidr_block  = local.create_vpc ? module.vpc[0].vpc_cidr_block : var.vpc_cidr_block

  # Engine-specific configurations
  engine_config = {
    redis = {
      name_suffix           = "redis"
      engine                = "redis"
      engine_version        = "7.0"    # Consistent with original code
      parameter_group_family = "redis7" # For cluster mode disabled or single node
      port                  = 6379
      description           = "Redis"
    }
    valkey = {
      name_suffix           = "valkey"
      engine                = "valkey"
      engine_version        = "7.2"    # AWS supports Valkey 7.2.x and 8.x. Using 7.2 as an example.
      parameter_group_family = "valkey7" # For cluster mode disabled or single node
      port                  = 6379
      description           = "Valkey"
    }
  }
  selected_engine_config = local.engine_config[var.cache_engine_type]
  resource_name_suffix   = local.selected_engine_config.name_suffix
  common_tag_name        = "${local.tag_name_prefix} ${local.selected_engine_config.description}" # Used for generic resource tagging
}