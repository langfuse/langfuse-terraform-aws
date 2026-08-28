output "cluster_name" {
  description = "EKS Cluster Name to use for a Kubernetes terraform provider"
  value       = aws_eks_cluster.langfuse.name
}

output "cluster_host" {
  description = "EKS Cluster host to use for a Kubernetes terraform provider"
  value       = aws_eks_cluster.langfuse.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS Cluster CA certificate to use for a Kubernetes terraform provider"
  value       = base64decode(aws_eks_cluster.langfuse.certificate_authority[0].data)
  sensitive   = true
}

output "cluster_token" {
  description = "EKS Cluster Token to use for a Kubernetes terraform provider"
  value       = data.aws_eks_cluster_auth.langfuse.token
  sensitive   = true
}

output "route53_nameservers" {
  description = "Nameservers for the Route53 zone (null when skip_dns_setup is true)"
  value       = var.skip_dns_setup ? null : aws_route53_zone.zone[0].name_servers
}

output "load_balancer_dns_name" {
  description = "DNS name of the ALB created for Langfuse"
  value       = data.aws_lb.ingress.dns_name
}

output "load_balancer_zone_id" {
  description = "Hosted zone ID of the ALB (for use in Route53 alias records)"
  value       = data.aws_lb.ingress.zone_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs from the VPC module"
  value       = local.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs from the VPC module"
  value       = local.public_subnets
}

output "bucket_name" {
  description = "Name of the S3 bucket for Langfuse"
  value       = aws_s3_bucket.langfuse.bucket
}

output "bucket_id" {
  description = "ID of the S3 bucket for Langfuse"
  value       = aws_s3_bucket.langfuse.id
}

output "isolated_execution_vpc_id" {
  description = "ID of the shared isolated VPC that runs untrusted code. Null unless code evaluators or the agent sandbox are enabled."
  value       = one(module.isolated_execution_vpc[*].vpc_id)
}

output "isolated_execution_subnet_ids" {
  description = "Private subnet IDs of the shared isolated VPC. Empty unless code evaluators or the agent sandbox are enabled."
  value       = try(module.isolated_execution_vpc[0].private_subnets, [])
}

output "isolated_execution_route_table_ids" {
  description = "Private route table IDs of the shared isolated VPC. These carry no default route. Empty unless code evaluators or the agent sandbox are enabled."
  value       = try(module.isolated_execution_vpc[0].private_route_table_ids, [])
}

output "agent_sandbox_execution_role_arn" {
  description = "IAM role the MicroVM guest runs as. Null when the agent sandbox is disabled."
  value       = one(aws_iam_role.agent_sandbox_execution[*].arn)
}

output "agent_sandbox_egress_network_connector_arn" {
  description = "Deny-all VPC egress connector ARN. Null when the agent sandbox is disabled."
  value       = one(aws_lambdacore_network_connector.agent_sandbox_egress[*].arn)
}

output "agent_sandbox_microvm_image_arn" {
  description = "Constructed MicroVM image ARN. The image itself is created by build-microvm-image.sh after apply. Null when the agent sandbox is disabled."
  value       = var.enable_agent_sandbox_microvm ? local.agent_sandbox_microvm_image_arn : null
}

# Everything build-microvm-image.sh needs, so the image build is one command with
# no copy-paste:
#
#   terraform output -json agent_sandbox_build_env \
#     | jq -r 'to_entries[] | "export \(.key)=\(.value)"' > .env && source .env
#   bash packages/in-app-agent-sandbox-runtime/build-microvm-image.sh
#
# AWS_PROFILE is deliberately absent: the script requires it, but only the caller
# knows which local profile to use.
output "agent_sandbox_build_env" {
  description = "Environment for packages/in-app-agent-sandbox-runtime/build-microvm-image.sh. Set AWS_PROFILE yourself. Null when the agent sandbox is disabled."
  value = var.enable_agent_sandbox_microvm ? {
    AWS_REGION                    = data.aws_region.current.region
    S3_BUCKET                     = aws_s3_bucket.agent_sandbox_artifacts[0].bucket
    MICROVM_IMAGE_NAME            = var.agent_sandbox_image_name
    LAMBDA_MICROVM_BUILD_ROLE_ARN = aws_iam_role.agent_sandbox_build[0].arn
    BASE_IMAGE_ARN                = "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:aws:microvm-image:al2023-1"
    BASE_IMAGE_VERSION            = "0"
  } : null
}
