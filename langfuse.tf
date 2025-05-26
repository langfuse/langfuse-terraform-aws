locals {
  ingress_scheme = var.public_endpoint ? "internet-facing" : "internal"
  ingress_subnets = var.public_endpoint ? join(",", local.public_subnets) : join(",", local.private_subnets)

  okta_client_secret = var.enable_okta ? (
    var.use_encryption_key == false ?
    data.aws_secretsmanager_secret_version.langfuse_secrets_version[0].secret_string :
    <<EOT

          secretKeyRef:
            name: langfuse
            key: okta-client-secret
EOT
  ) : ""

  langfuse_values = <<EOT
global:
  defaultStorageClass: efs
langfuse:
  salt:
    secretKeyRef:
      name: langfuse
      key: salt
  nextauth:
    url: "https://${var.domain}"
    secret:
      secretKeyRef:
        name: langfuse
        key: nextauth-secret
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: ${aws_iam_role.langfuse_irsa.arn}
  # The Web container needs slightly increased initial grace period on Fargate
  web:
    livenessProbe:
      initialDelaySeconds: 60
    readinessProbe:
      initialDelaySeconds: 60
postgresql:
  deploy: false
  host: ${aws_rds_cluster.postgres.endpoint}:5432
  auth:
    username: langfuse
    database: langfuse
    existingSecret: langfuse
    secretKeys:
      userPasswordKey: postgres-password
clickhouse:
  auth:
    existingSecret: langfuse
    existingSecretKey: clickhouse-password
  zookeeper:
    resourcePreset: medium
redis:
  deploy: false
  host: ${aws_elasticache_replication_group.cache.primary_endpoint_address}
  auth:
    existingSecret: langfuse
    existingSecretPasswordKey: redis-password
  tls:
    enabled: true
s3:
  deploy: false
  bucket: ${aws_s3_bucket.langfuse.id}
  region: ${data.aws_region.current.name}
  forcePathStyle: false
  eventUpload:
    prefix: "events/"
  batchExport:
    prefix: "exports/"
  mediaUpload:
    prefix: "media/"
EOT
  ingress_values  = <<EOT
langfuse:
  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: ${local.ingress_scheme}
      alb.ingress.kubernetes.io/target-type: 'ip'
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}, {"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: '443'
      alb.ingress.kubernetes.io/subnets: ${local.ingress_subnets}
    hosts:
    - host: ${var.domain}
      paths:
      - path: /
        pathType: Prefix
EOT
  encryption_values = var.use_encryption_key == false ? "" : <<EOT
langfuse:
  encryptionKey:
    secretKeyRef:
      name: ${kubernetes_secret.langfuse.metadata[0].name}
      key: encryption_key
EOT
  okta_values = var.enable_okta == false ? "" : <<EOT
langfuse:
  auth:
    providers:
      okta:
        clientId: ${var.okta_settings.client_id}
        clientSecret: ${local.okta_client_secret}
        issuer: ${var.okta_settings.issuer}
EOT
}

data "aws_secretsmanager_secret" "langfuse_secrets" {
  count = var.okta_settings != null ? 1 : 0
  name  = var.okta_settings.client_secret_secrets_name
}

data "aws_secretsmanager_secret_version" "langfuse_secrets_version" {
  count = var.okta_settings != null ? 1 : 0
  secret_id = data.aws_secretsmanager_secret.langfuse_secrets[0].id
}

resource "kubernetes_namespace" "langfuse" {
  metadata {
    name = "langfuse"
  }
}

resource "random_bytes" "salt" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> SALT
  length = 32
}

resource "random_bytes" "nextauth_secret" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> NEXTAUTH_SECRET
  length = 32
}

resource "random_bytes" "encryption_key" {
  count = var.use_encryption_key ? 1 : 0
  # Must be exactly 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> ENCRYPTION_KEY
  length = 32
}

resource "kubernetes_secret" "langfuse" {
  metadata {
    name      = "langfuse"
    namespace = "langfuse"
  }

  data = merge({
    "redis-password"      = random_password.cache_password.result
    "postgres-password"   = random_password.postgres_password.result
    "salt"                = random_bytes.salt.base64
    "nextauth-secret"     = random_bytes.nextauth_secret.base64
    "clickhouse-password" = random_password.clickhouse_password.result
    "encryption_key"      = var.use_encryption_key ? random_bytes.encryption_key[0].hex : ""
  },
  var.enable_okta ? {
    "okta-client-secret" = data.aws_secretsmanager_secret_version.langfuse_secrets_version[0].secret_string
  } : {})
}

resource "helm_release" "langfuse" {
  name             = "langfuse"
  repository       = "https://langfuse.github.io/langfuse-k8s"
  version          = "1.1.0"
  chart            = "langfuse"
  namespace        = "langfuse"
  create_namespace = true
  timeout          = 600

  values = [
    local.langfuse_values,
    local.ingress_values,
    local.encryption_values,
    local.okta_values
  ]

  set {
    name  = "langfuse.auth.disableUsernamePassword"
    value = var.enable_okta ? "true" : "false"
  }

  set {
    name  = "langfuse.auth.disableSignup"
    value = var.enable_okta ? "true" : "false"
  }

  depends_on = [
    aws_iam_role.langfuse_irsa,
    aws_iam_role_policy.langfuse_s3_access,
    aws_eks_fargate_profile.namespaces,
    kubernetes_persistent_volume.clickhouse_data,
    kubernetes_persistent_volume.clickhouse_zookeeper,
  ]
}
