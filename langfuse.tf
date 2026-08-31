locals {
  inbound_cidrs_csv = join(",", var.ingress_inbound_cidrs)
  langfuse_values   = <<EOT
langfuse:
  image:
    tag: ${jsonencode(var.app_version)}
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
  # Resource configuration for production workloads
  resources:
    limits:
      cpu: "${var.langfuse_cpu}"
      memory: "${var.langfuse_memory}"
    requests:
      cpu: "${var.langfuse_cpu}"
      memory: "${var.langfuse_memory}"
  # The Web container needs slightly increased initial grace period on Fargate
  web:
    replicas: ${var.langfuse_web_replicas}
    livenessProbe:
      initialDelaySeconds: 60
    readinessProbe:
      initialDelaySeconds: 60
  worker:
    replicas: ${var.langfuse_worker_replicas}
postgresql:
  deploy: false
  host: ${aws_rds_cluster.postgres.endpoint}:5432
  auth:
    username: langfuse
    database: langfuse
    existingSecret: langfuse
    secretKeys:
      userPasswordKey: postgres-password
redis:
  deploy: false
  host: ${aws_elasticache_replication_group.redis.primary_endpoint_address}
  auth:
    existingSecret: langfuse
    existingSecretPasswordKey: redis-password
  tls:
    enabled: true
s3:
  deploy: false
  bucket: ${aws_s3_bucket.langfuse.id}
  region: ${data.aws_region.current.region}
  forcePathStyle: false
  eventUpload:
    prefix: "events/"
  batchExport:
    prefix: "exports/"
  mediaUpload:
    prefix: "media/"
EOT

  # In-cluster ClickHouse: the Langfuse Helm chart v2 renders ClickHouseCluster
  # and KeeperCluster resources reconciled by the ClickHouse operator (see
  # clickhouse.tf). Storage is backed by the statically provisioned EFS
  # persistent volumes, so the sizes must match the PV capacities.
  clickhouse_internal_values = !local.deploy_clickhouse ? "" : <<EOT
clickhouse:
  deploy: true
  auth:
    existingSecret: langfuse
    existingSecretKey: clickhouse-password
  cluster:
    replicas: ${var.clickhouse_replicas}
    storage:
      size: ${var.clickhouse_storage_size}
      className: efs
    resources:
      requests:
        cpu: "${var.clickhouse_cpu}"
        memory: "${var.clickhouse_memory}"
      limits:
        cpu: "${var.clickhouse_cpu}"
        memory: "${var.clickhouse_memory}"
  keeper:
    replicas: ${var.clickhouse_keeper_replicas}
    storage:
      size: ${var.clickhouse_keeper_storage_size}
      className: efs
    resources:
      requests:
        cpu: "${var.clickhouse_keeper_cpu}"
        memory: "${var.clickhouse_keeper_memory}"
      limits:
        cpu: "${var.clickhouse_keeper_cpu}"
        memory: "${var.clickhouse_keeper_memory}"
EOT

  # External ClickHouse: skip the in-cluster deployment (and all EFS
  # resources) and point Langfuse at the provided instance.
  clickhouse_external_values = local.deploy_clickhouse ? "" : <<EOT
clickhouse:
  deploy: false
  host: ${jsonencode(var.external_clickhouse.host)}
  httpPort: ${var.external_clickhouse.http_port}
  nativePort: ${var.external_clickhouse.native_port}
  database: ${jsonencode(var.external_clickhouse.database)}
  cluster:
    enabled: ${var.external_clickhouse.cluster_enabled}
  auth:
    username: ${jsonencode(var.external_clickhouse.username)}
    existingSecret: langfuse
    existingSecretKey: clickhouse-password
  migration:
    ssl: ${var.external_clickhouse.migration_ssl}
EOT

  clickhouse_values = local.deploy_clickhouse ? local.clickhouse_internal_values : local.clickhouse_external_values

  ai_features_configured = var.ai_features_provider != null

  # Whether a key was supplied is not itself secret, and the value never enters
  # this template — it goes to the langfuse Kubernetes secret and is referenced
  # by secretKeyRef. Without nonsensitive() the whole rendered values document
  # inherits the variable's sensitivity, which hides every unrelated
  # environment variable from the plan diff.
  ai_features_api_key_set = nonsensitive(var.ai_features_api_key != null)

  additional_env_values = !var.enable_code_based_eval_executors && !local.ai_features_configured && !var.enable_in_app_agent && length(var.additional_env) == 0 ? "" : <<EOT
langfuse:
  additionalEnv:
%{if var.enable_code_based_eval_executors~}
    - name: LANGFUSE_CODE_EVAL_DISPATCHER
      value: "aws-lambda"
    - name: LANGFUSE_CODE_EVAL_AWS_LAMBDA_PYTHON_FUNCTION_NAME
      value: ${jsonencode(local.code_based_eval_executor_lambda_names.python)}
    - name: LANGFUSE_CODE_EVAL_AWS_LAMBDA_NODE_FUNCTION_NAME
      value: ${jsonencode(local.code_based_eval_executor_lambda_names.node)}
%{endif~}
%{if local.ai_features_configured~}
    - name: LANGFUSE_AI_PROVIDER
      value: ${jsonencode(var.ai_features_provider)}
    - name: LANGFUSE_AI_MODEL
      value: ${jsonencode(var.ai_features_model)}
%{if var.ai_features_small_model != null~}
    - name: LANGFUSE_AI_SMALL_MODEL
      value: ${jsonencode(var.ai_features_small_model)}
%{endif~}
%{if var.ai_features_provider == "bedrock"~}
    - name: LANGFUSE_AI_AWS_BEDROCK_REGION
      value: ${jsonencode(coalesce(var.ai_features_bedrock_region, data.aws_region.current.region))}
%{endif~}
%{if local.ai_features_api_key_set~}
    - name: LANGFUSE_AI_API_KEY
      valueFrom:
        secretKeyRef:
          name: langfuse
          key: ai-features-api-key
%{endif~}
%{if var.ai_features_base_url != null~}
    - name: LANGFUSE_AI_BASE_URL
      value: ${jsonencode(var.ai_features_base_url)}
%{endif~}
%{endif~}
%{if var.enable_in_app_agent~}
    - name: LANGFUSE_IN_APP_AGENT_ENABLED
      value: "true"
%{endif~}
%{for env in var.additional_env~}
    - name: ${env.name}
%{if env.value != null~}
      value: ${jsonencode(env.value)}
%{endif~}
%{if env.valueFrom != null~}
      valueFrom:
%{if env.valueFrom.secretKeyRef != null~}
        secretKeyRef:
          name: ${env.valueFrom.secretKeyRef.name}
          key: ${env.valueFrom.secretKeyRef.key}
%{endif~}
%{if env.valueFrom.configMapKeyRef != null~}
        configMapKeyRef:
          name: ${env.valueFrom.configMapKeyRef.name}
          key: ${env.valueFrom.configMapKeyRef.key}
%{endif~}
%{endif~}
%{endfor~}
EOT

  # Worker-only env. Both features render into the same
  # langfuse.worker.pod.additionalEnv list, so they must share one values
  # document: Helm coalesces maps across -f documents but *replaces* lists, so
  # two documents each setting additionalEnv would silently drop one feature's
  # variables. Only the worker reads either set — it consumes the code eval and
  # agent run queues.
  worker_additional_env_values = !var.enable_code_based_eval_executors && !var.enable_agent_sandbox_microvm ? "" : <<EOT
langfuse:
  worker:
    pod:
      additionalEnv:
%{if var.enable_code_based_eval_executors~}
        - name: LANGFUSE_CODE_EVAL_EXECUTION_WORKER_CONCURRENCY
          value: ${jsonencode(tostring(var.code_eval_execution_worker_concurrency))}
        - name: QUEUE_CONSUMER_CODE_EVAL_EXECUTION_QUEUE_IS_ENABLED
          value: "true"
%{endif~}
%{if var.enable_agent_sandbox_microvm~}
        - name: LANGFUSE_IN_APP_AGENT_SANDBOX_PROVIDER
          value: "lambda-microvm"
        - name: LANGFUSE_IN_APP_AGENT_SANDBOX_AWS_LAMBDA_MICROVM_IMAGE_IDENTIFIER
          value: ${jsonencode(local.agent_sandbox_microvm_image_arn)}
        - name: LANGFUSE_IN_APP_AGENT_SANDBOX_AWS_LAMBDA_MICROVM_EXECUTION_ROLE_ARN
          value: ${jsonencode(one(aws_iam_role.agent_sandbox_execution[*].arn))}
        - name: LANGFUSE_IN_APP_AGENT_SANDBOX_AWS_LAMBDA_MICROVM_EGRESS_NETWORK_CONNECTOR_ARN
          value: ${jsonencode(one(aws_lambdacore_network_connector.agent_sandbox_egress[*].arn))}
        - name: LANGFUSE_IN_APP_AGENT_SANDBOX_AWS_LAMBDA_MICROVM_REGION
          value: ${jsonencode(data.aws_region.current.region)}
%{endif~}
EOT

  ingress_values    = <<EOT
langfuse:
  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}, {"HTTPS":443}]'
      alb.ingress.kubernetes.io/scheme: ${var.alb_scheme}
      alb.ingress.kubernetes.io/target-type: 'ip'
      alb.ingress.kubernetes.io/ssl-redirect: '443'
      alb.ingress.kubernetes.io/inbound-cidrs: ${local.inbound_cidrs_csv}
      alb.ingress.kubernetes.io/certificate-arn: ${local.certificate_arn}
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

  # The settings map is rendered into a config.d file by the ClickHouse
  # operator; the "@remove" keys translate to the XML remove="1" attribute.
  # We could also consider excluding the following tables on opt-out:
  # query_log, processors_profile_log, part_log, query_views_log,
  # asynchronous_insert_log, query_metric_log, error_log
  clickhouse_overwrite_values = var.enable_clickhouse_log_tables || !local.deploy_clickhouse ? "" : <<EOT
clickhouse:
  cluster:
    settings:
      trace_log:
        "@remove": "1"
      text_log:
        "@remove": "1"
      opentelemetry_span_log:
        "@remove": "1"
      asynchronous_metric_log:
        "@remove": "1"
      metric_log:
        "@remove": "1"
      latency_log:
        "@remove": "1"
EOT
}

resource "kubernetes_namespace" "langfuse" {
  metadata {
    name = "langfuse"
  }

  # Destroy the namespace before the PVs: this removes the PVCs the ClickHouse
  # operator created, releasing the PVs so their deletion is not held back by
  # the pv-protection finalizer.
  depends_on = [
    kubernetes_persistent_volume.clickhouse_data,
    kubernetes_persistent_volume.clickhouse_keeper,
  ]
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
    namespace = kubernetes_namespace.langfuse.metadata[0].name
  }

  data = {
    "redis-password"      = random_password.redis_password.result
    "postgres-password"   = random_password.postgres_password.result
    "salt"                = random_bytes.salt.base64
    "nextauth-secret"     = random_bytes.nextauth_secret.base64
    "clickhouse-password" = local.deploy_clickhouse ? random_password.clickhouse_password.result : var.external_clickhouse_password
    "encryption_key"      = var.use_encryption_key ? random_bytes.encryption_key[0].hex : ""
    "ai-features-api-key" = coalesce(var.ai_features_api_key, "")
  }
}

resource "helm_release" "langfuse" {
  name       = "langfuse"
  repository = "https://langfuse.github.io/langfuse-k8s"
  version    = var.langfuse_helm_chart_version
  chart      = "langfuse"
  namespace  = kubernetes_namespace.langfuse.metadata[0].name

  # Fargate cold starts on EFS-backed volumes mean the default 300s is not
  # enough: the release brings up ClickHouse and Keeper before the web pod can
  # pass its probes, and the web pod may crash-restart once on the way.
  timeout = var.helm_release_timeout

  values = compact([
    local.langfuse_values,
    local.clickhouse_values,
    local.ingress_values,
    local.encryption_values,
    local.additional_env_values,
    local.worker_additional_env_values,
    local.clickhouse_overwrite_values,
  ])

  depends_on = [
    kubernetes_namespace.langfuse,
    aws_iam_role.langfuse_irsa,
    aws_iam_role_policy.langfuse_s3_access,
    aws_iam_role_policy.langfuse_code_based_eval_executor_invoke,
    aws_iam_role_policy.langfuse_agent_sandbox,
    aws_iam_role_policy.langfuse_ai_features_bedrock,
    aws_eks_fargate_profile.namespaces,
    kubernetes_persistent_volume.clickhouse_data,
    kubernetes_persistent_volume.clickhouse_keeper,
    kubernetes_service_account.aws_load_balancer_controller,
    helm_release.aws_load_balancer_controller,
    helm_release.clickhouse_operator,
    module.vpc,
    aws_efs_mount_target.eks,
  ]

  lifecycle {
    precondition {
      condition     = var.external_clickhouse == null || var.external_clickhouse_password != ""
      error_message = "external_clickhouse_password must be set when external_clickhouse is configured."
    }
  }
}

