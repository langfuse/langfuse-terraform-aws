resource "aws_ec2_tag" "lbl_subnets_eks_cluster_tag" {
  for_each = toset(var.public_subnets)

  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"
}

resource "aws_ec2_tag" "lbl_subnets_internal_elb_tag" {
  for_each = toset(var.public_subnets)

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}
