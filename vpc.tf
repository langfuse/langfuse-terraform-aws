data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  should_create_vpc = var.vpc_id == null
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  count   = local.should_create_vpc ? 1 : 0

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway     = true
  single_nat_gateway     = !var.use_single_nat_gateway
  one_nat_gateway_per_az = var.use_single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  # Add required tags for the AWS Load Balancer Controller
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }

  tags = {
    Name = local.tag_name
  }
}

locals {
  vpc_id                  = local.should_create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnets         = local.should_create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  public_subnets          = local.should_create_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids
  vpc_cidr_block          = data.aws_vpc.vpc.cidr_block
  private_route_table_ids = local.should_create_vpc ? module.vpc[0].private_route_table_ids : var.private_route_table_ids
}

data "aws_vpc" "vpc" {
  id = local.vpc_id
}

# Tag existing private subnets for AWS Load Balancer Controller
resource "aws_ec2_tag" "private_subnet_alb" {
  count       = local.should_create_vpc ? 0 : length(var.private_subnet_ids)
  resource_id = var.private_subnet_ids[count.index]
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_ec2_tag" "private_subnet_cluster" {
  count       = local.should_create_vpc ? 0 : length(var.private_subnet_ids)
  resource_id = var.private_subnet_ids[count.index]
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"
}

# Tag existing public subnets for AWS Load Balancer Controller
resource "aws_ec2_tag" "public_subnet_alb" {
  count       = local.should_create_vpc ? 0 : length(var.public_subnet_ids)
  resource_id = var.public_subnet_ids[count.index]
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_subnet_cluster" {
  count       = local.should_create_vpc ? 0 : length(var.public_subnet_ids)
  resource_id = var.public_subnet_ids[count.index]
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"
}

# VPC Endpoints for AWS services
resource "aws_vpc_endpoint" "sts" {
  vpc_id             = local.vpc_id
  service_name       = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = local.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = {
    Name = "${local.tag_name} STS VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "s3" {
  count = local.private_route_table_ids != null ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = {
    Name = "${local.tag_name} S3 VPC Endpoint"
  }
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  tags = {
    Name = "${local.tag_name} VPC Endpoints"
  }
}
