resource "aws_security_group" "cache" {
  name        = "${var.name}-${local.resource_name_suffix}"
  description = "Security group for Langfuse ${local.selected_engine_config.description}"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = local.selected_engine_config.port
    to_port     = local.selected_engine_config.port
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.common_tag_name} SG"
  }
}

# --- ElastiCache Parameter Group ---
resource "aws_elasticache_parameter_group" "cache" {
  family = local.selected_engine_config.parameter_group_family
  name   = "${var.name}-${local.resource_name_suffix}-params"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction" # This policy is generally available for both Redis and Valkey
  }

  tags = {
    Name = "${local.common_tag_name} Parameter Group"
  }
}

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "cache" {
  name              = "/aws/elasticache/${var.name}-${local.resource_name_suffix}"
  retention_in_days = 7

  tags = {
    Name = "${local.common_tag_name} Log Group"
  }
}

# --- ElastiCache Subnet Group ---
resource "aws_elasticache_subnet_group" "cache" {
  name       = "${var.name}-${local.resource_name_suffix}-subnet-group"
  subnet_ids = local.private_subnets

  tags = {
    Name = "${local.common_tag_name} Subnet Group"
  }
}

# --- Random Password ---
resource "random_password" "cache_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

# --- ElastiCache Replication Group ---
resource "aws_elasticache_replication_group" "cache" {
  replication_group_id       = "${var.name}-${local.resource_name_suffix}"
  description                = "${local.selected_engine_config.description} cluster for Langfuse"
  node_type                  = var.cache_node_type
  port                       = local.selected_engine_config.port
  parameter_group_name       = aws_elasticache_parameter_group.cache.name
  automatic_failover_enabled = var.cache_instance_count > 1
  num_cache_clusters         = var.cache_instance_count # For single-shard replication group (primary + replicas)

  subnet_group_name          = aws_elasticache_subnet_group.cache.name
  security_group_ids         = [aws_security_group.cache.id]
  engine                     = local.selected_engine_config.engine
  engine_version             = local.selected_engine_config.engine_version
  auth_token                 = random_password.cache_password.result
  transit_encryption_enabled = true
  auto_minor_version_upgrade = true

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.cache.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = {
    Name   = local.common_tag_name
    Engine = var.cache_engine_type
  }

  lifecycle {
    ignore_changes = [
       engine_version, # If you want to manage engine version upgrades outside of apply, or if minor versions change
    ]
  }
}
