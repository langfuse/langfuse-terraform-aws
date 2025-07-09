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
  description = "Nameserver for the Route53 zone (only when zone is created)"
  value       = var.existing_certificate_arn == null ? aws_route53_zone.zone[0].name_servers : null
}

output "private_subnet_ids" {
  description = "Private subnet IDs from the VPC module"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs from the VPC module"
  value       = module.vpc.public_subnets
}

output "bucket_name" {
  description = "Name of the S3 bucket for Langfuse"
  value       = aws_s3_bucket.langfuse.bucket
}

output "bucket_id" {
  description = "ID of the S3 bucket for Langfuse"
  value       = aws_s3_bucket.langfuse.id
}

output "certificate_arn" {
  description = "ARN of the ACM certificate being used"
  value       = local.certificate_arn
}
