data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# Data source to reference your existing VPC
data "aws_vpc" "existing" {
  # Option 1: Reference by VPC ID
  id = var.vpc_id  # Replace with your actual VPC ID

  # Option 2: Reference by tags (alternative)
  # tags = {
  #   Name = "${var.name}-vpc"
  # }
}

# Data source for existing Internet Gateway
data "aws_internet_gateway" "existing" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.existing.id]
  }
}

# Note: This configuration creates NEW subnets in your existing VPC
# The data sources below are removed since we're creating new subnets

# Create NEW private subnets in existing VPC
resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = data.aws_vpc.existing.id
  cidr_block        = cidrsubnet(data.aws_vpc.existing.cidr_block, 4, 12 + count.index)
  availability_zone = local.azs[count.index]

  tags = merge(
    {
      Name = "${var.name}-vpc-private-${local.azs[count.index]}"
      "kubernetes.io/role/internal-elb"   = "1"
      "kubernetes.io/cluster/${var.name}" = "shared"
    },
    {
      Name = local.tag_name
    }
  )
}

# Create NEW public subnets in existing VPC
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = data.aws_vpc.existing.id
  cidr_block              = cidrsubnet(data.aws_vpc.existing.cidr_block, 4, 8 + count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "${var.name}-vpc-public-${local.azs[count.index]}"
      "kubernetes.io/role/elb"            = "1"
      "kubernetes.io/cluster/${var.name}" = "shared"
    },
    {
      Name = local.tag_name
    }
  )
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.use_single_nat_gateway ? 1 : length(local.azs)

  domain = "vpc"

  tags = merge(
    {
      Name = "${var.name}-vpc-eip-${var.use_single_nat_gateway ? "single" : local.azs[count.index]}"
    },
    {
      Name = local.tag_name
    }
  )

  depends_on = [data.aws_internet_gateway.existing]
}

# NAT Gateways
resource "aws_nat_gateway" "this" {
  count = var.use_single_nat_gateway ? 1 : length(local.azs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    {
      Name = "${var.name}-vpc-nat-${var.use_single_nat_gateway ? "single" : local.azs[count.index]}"
    },
    {
      Name = local.tag_name
    }
  )

  depends_on = [data.aws_internet_gateway.existing]
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.existing.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.existing.id
  }

  tags = merge(
    {
      Name = "${var.name}-vpc-public"
    },
    {
      Name = local.tag_name
    }
  )
}

# Route table associations for public subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route tables for private subnets
resource "aws_route_table" "private" {
  count = var.use_single_nat_gateway ? 1 : length(local.azs)

  vpc_id = data.aws_vpc.existing.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.use_single_nat_gateway ? 0 : count.index].id
  }

  tags = merge(
    {
      Name = "${var.name}-vpc-private-${var.use_single_nat_gateway ? "single" : local.azs[count.index]}"
    },
    {
      Name = local.tag_name
    }
  )
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.use_single_nat_gateway ? 0 : count.index].id
}



# Enable DNS settings on existing VPC (if needed)
resource "aws_vpc_dhcp_options" "this" {
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = {
    Name = "${var.name}-vpc-dhcp-options"
  }
}

resource "aws_vpc_dhcp_options_association" "this" {
  vpc_id          = data.aws_vpc.existing.id
  dhcp_options_id = aws_vpc_dhcp_options.this.id
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.tag_name} VPC Endpoints"
  }
}

# VPC Endpoints for AWS services
resource "aws_vpc_endpoint" "sts" {
  vpc_id             = data.aws_vpc.existing.id
  service_name       = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.tag_name} STS VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.existing.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${local.tag_name} S3 VPC Endpoint"
  }
}

#
# # Outputs to match the original module outputs
# output "vpc_id" {
#   description = "ID of the VPC"
#   value       = data.aws_vpc.existing.id
# }
#
# output "vpc_cidr_block" {
#   description = "The CIDR block of the VPC"
#   value       = data.aws_vpc.existing.cidr_block
# }
#
# output "private_subnets" {
#   description = "List of IDs of private subnets"
#   value       = aws_subnet.private[*].id
# }
#
# output "public_subnets" {
#   description = "List of IDs of public subnets"
#   value       = aws_subnet.public[*].id
# }
#
# output "internet_gateway_id" {
#   description = "The ID of the Internet Gateway"
#   value       = data.aws_internet_gateway.existing.id
# }
#
# output "nat_gateway_ids" {
#   description = "List of IDs of the NAT Gateways"
#   value       = aws_nat_gateway.this[*].id
# }
#
# output "private_route_table_ids" {
#   description = "List of IDs of the private route tables"
#   value       = aws_route_table.private[*].id
# }
#
# output "public_route_table_ids" {
#   description = "List of IDs of the public route tables"
#   value       = [aws_route_table.public.id]
# }
