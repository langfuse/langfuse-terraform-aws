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

output "code_based_eval_executor_lambda_function_names" {
  description = "Code-based eval executor Lambda function names by runtime (empty when disabled)"
  value       = var.enable_code_based_eval_executors ? local.code_based_eval_executor_lambda_names : {}
}
