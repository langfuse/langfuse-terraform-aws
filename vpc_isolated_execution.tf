# Shared isolated VPC for everything that runs untrusted, user-provided code:
# the code evaluator Lambdas (code_based_eval_executor.tf) and the agent sandbox
# MicroVMs (agent_sandbox.tf). It has no internet gateway, no NAT gateway, no
# peering, no endpoints and no DNS, so nothing in it can reach the Langfuse VPC
# or the public internet even if a security group is later loosened.
#
# Each workload brings its own deny-all security group rather than sharing one,
# so their network postures can diverge. If the sandbox ever needs a route to
# langfuse-web, note that the route table here is shared: a route added to it is
# visible to code evaluator ENIs too, and only their own security group would
# stop them. At that point either accept the security group as the boundary or
# give the sandbox dedicated subnets and route table out of the spare CIDR
# space. enable_dns_support and enable_dns_hostnames are in-place updates on
# aws_vpc, so turning them on later does not replace anything.

locals {
  isolated_execution_enabled = var.enable_code_based_eval_executors || var.enable_agent_sandbox_microvm

  # Both variables default to null so an explicit value is distinguishable from an
  # untouched default; code_based_eval_vpc_cidr is the deprecated 1.1.1 name.
  isolated_execution_vpc_cidr = coalesce(var.isolated_execution_vpc_cidr, var.code_based_eval_vpc_cidr, "10.1.0.0/24")
}

# 1.1.1 shipped this VPC as module.code_based_eval_executor_vpc, before the agent
# sandbox began sharing it. Without this block, upgrading from 1.1.1 destroys and
# recreates the VPC and everything attached to it.
moved {
  from = module.code_based_eval_executor_vpc
  to   = module.isolated_execution_vpc
}

module "isolated_execution_vpc" {
  count = local.isolated_execution_enabled ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.name}-isolated-execution"
  cidr = local.isolated_execution_vpc_cidr

  azs             = local.azs
  private_subnets = [for index, _ in local.azs : cidrsubnet(local.isolated_execution_vpc_cidr, 2, index)]

  create_igw         = false
  enable_nat_gateway = false
  # AmazonProvidedDNS bypasses security groups and can otherwise be used to
  # exfiltrate data through attacker-controlled DNS names.
  enable_dns_support   = false
  enable_dns_hostnames = false

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  # A log group's name is its identity and AWS has no rename, so changing this
  # replaces the group and the flow log pointing at it. Upgrading from 1.1.1
  # with code evaluators enabled therefore loses up to 14 days of records for
  # this VPC. Done deliberately and now rather than later: the cost is the same
  # whenever it happens and only grows with adoption. Operators who have to keep
  # the records can drop the old group from state before upgrading, which leaves
  # it in AWS untouched; see the upgrade note in the README.
  flow_log_cloudwatch_log_group_name_prefix       = "${var.name}-isolated-execution-"
  flow_log_cloudwatch_log_group_retention_in_days = 14
  flow_log_cloudwatch_log_group_class             = "INFREQUENT_ACCESS"

  tags = {
    Name = "${local.tag_name} Isolated Execution"
  }
}
