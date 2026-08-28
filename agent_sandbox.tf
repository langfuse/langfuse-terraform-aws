# Optional Lambda MicroVM sandbox for the in-app agent's file and code execution
# tools. Sets LANGFUSE_IN_APP_AGENT_SANDBOX_* on the worker (see langfuse.tf).
#
# The MicroVM image is not created here. Terraform grants permissions on a
# constructed image ARN so the image can be built after apply, out of band, with
# packages/in-app-agent-sandbox-runtime/build-microvm-image.sh from a Langfuse
# checkout. The agent_sandbox_build_env output supplies every variable that
# script needs.
#
# Resource names use the short "agent-sandbox" infix rather than
# "in-app-agent-sandbox-microvm": IAM role names cap at 64 characters, and the
# longer infix would restrict var.name to 17 characters instead of 32.

locals {
  agent_sandbox_microvm_image_arn = "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:microvm-image:${var.agent_sandbox_image_name}"

  # The AWS-managed ingress connector that carries the worker's tool calls into
  # the guest. ALL_INGRESS is a different named connector, not a wildcard, and
  # Langfuse never passes it.
  agent_sandbox_http_ingress_connector_arn = "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:aws:network-connector:aws-network-connector:HTTP_INGRESS"
}

# Holds only the runtime zip that build-microvm-image.sh uploads, expired after
# a week. Deliberately not the Langfuse bucket that code_based_eval_executor.tf
# reuses: there Terraform is the uploader, whereas this artifact is written by an
# operator running a script that targets a fixed root key, and it would land
# under the Langfuse bucket's 90-day IA and 180-day Glacier transitions. It is
# also read by a different principal, the Lambda build role.
resource "aws_s3_bucket" "agent_sandbox_artifacts" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  bucket = "${local.bucket_prefix}-${var.name}-agent-sandbox"

  tags = {
    Name    = "${local.bucket_prefix}-${var.name}-agent-sandbox"
    Domain  = var.domain
    Service = "langfuse"
  }
}

resource "aws_s3_bucket_public_access_block" "agent_sandbox_artifacts" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  bucket = aws_s3_bucket.agent_sandbox_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "agent_sandbox_artifacts" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  bucket = aws_s3_bucket.agent_sandbox_artifacts[0].id

  rule {
    id     = "expire-artifacts"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Assumed by Lambda during CreateMicrovmImage to read the artifact and write
# build logs. Separate from the execution role on purpose: user-provided sandbox
# code runs as the execution role, which must reach nothing at all.
resource "aws_iam_role" "agent_sandbox_build" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  name = "${var.name}-agent-sandbox-build"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
      },
    ]
  })

  tags = {
    Name = "${local.tag_name} Agent Sandbox Build"
  }
}

resource "aws_iam_role_policy" "agent_sandbox_build" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  name = "${var.name}-agent-sandbox-build"
  role = aws_iam_role.agent_sandbox_build[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSandboxImageArtifact"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.agent_sandbox_artifacts[0].arn}/*"
      },
      {
        Sid    = "WriteBuildLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
    ]
  })
}

# The identity the MicroVM guest runs as. Intentionally has no policies.
resource "aws_iam_role" "agent_sandbox_execution" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  name = "${var.name}-agent-sandbox-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
      },
    ]
  })

  tags = {
    Name = "${local.tag_name} Agent Sandbox Execution"
  }
}

resource "aws_security_group" "agent_sandbox_egress" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  name        = "${var.name}-agent-sandbox-egress"
  description = "Deny all Lambda MicroVM agent sandbox egress"
  vpc_id      = module.isolated_execution_vpc[0].vpc_id

  # Load-bearing: a security group declared with neither argument gets AWS's
  # default allow-all egress rule. The empty lists remove it.
  ingress = []
  egress  = []

  tags = {
    Name = "${local.tag_name} Agent Sandbox Egress"
  }
}

resource "aws_iam_role" "agent_sandbox_network_connector" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  name = "${var.name}-agent-sandbox-network-connector"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "network-connectors.lambda.amazonaws.com",
          ]
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
      },
    ]
  })

  tags = {
    Name = "${local.tag_name} Agent Sandbox Network Connector"
  }
}

resource "aws_iam_role_policy" "agent_sandbox_network_connector" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  name = "${var.name}-agent-sandbox-network-connector"
  role = aws_iam_role.agent_sandbox_network_connector[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateNetworkInterfaceInSandboxSubnets"
        Effect   = "Allow"
        Action   = "ec2:CreateNetworkInterface"
        Resource = [for subnet_id in module.isolated_execution_vpc[0].private_subnets : "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:subnet/${subnet_id}"]
      },
      {
        Sid      = "CreateNetworkInterfaceWithSandboxSecurityGroup"
        Effect   = "Allow"
        Action   = "ec2:CreateNetworkInterface"
        Resource = aws_security_group.agent_sandbox_egress[0].arn
      },
      {
        Sid      = "CreateNetworkInterfaceWithLambdaTags"
        Effect   = "Allow"
        Action   = "ec2:CreateNetworkInterface"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
        Condition = {
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = [
              "aws:lambda:networkConnectorName",
              "aws:lambda:networkConnectorId",
            ]
          }
        }
      },
      {
        Sid      = "TagNetworkInterface"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction"            = "CreateNetworkInterface"
            "ec2:ManagedResourceOperator" = "network-connectors.lambda.amazonaws.com"
          }
        }
      },
    ]
  })
}

# Without this connector AWS attaches its default INTERNET_EGRESS connector and
# sandboxed code reaches the public internet.
resource "aws_lambdacore_network_connector" "agent_sandbox_egress" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  name          = "${var.name}-agent-sandbox-egress"
  operator_role = aws_iam_role.agent_sandbox_network_connector[0].arn

  configuration {
    vpc_egress_configuration {
      associated_compute_resource_types = ["MicroVm"]
      network_protocol                  = "IPv4"
      subnet_ids                        = module.isolated_execution_vpc[0].private_subnets
      security_group_ids                = [aws_security_group.agent_sandbox_egress[0].id]
    }
  }

  # aws_lambdacore_network_connector supports no tags, not even provider
  # default_tags.
  lifecycle {
    precondition {
      condition     = data.aws_partition.current.partition == "aws"
      error_message = "AWS Lambda MicroVMs are available only in commercial AWS regions, not in AWS GovCloud or China regions."
    }
  }

  # Lambda waits for the operator role and its inline policy to propagate before
  # the connector becomes usable.
  depends_on = [aws_iam_role_policy.agent_sandbox_network_connector]
}

# Web and worker share one Kubernetes ServiceAccount, so this single IRSA role
# covers both. Only the worker uses these permissions today.
resource "aws_iam_role_policy" "langfuse_agent_sandbox" {
  count = var.enable_agent_sandbox_microvm ? 1 : 0

  name = "agent-sandbox"
  role = aws_iam_role.langfuse_irsa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RunSandboxMicrovms"
        Effect = "Allow"
        Action = [
          "lambda:RunMicrovm",
          "lambda:GetMicrovm",
          "lambda:CreateMicrovmAuthToken",
          "lambda:ResumeMicrovm",
          "lambda:SuspendMicrovm",
          "lambda:TerminateMicrovm",
        ]
        Resource = local.agent_sandbox_microvm_image_arn
      },
      {
        Sid      = "PassSandboxExecutionRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.agent_sandbox_execution[0].arn
      },
      {
        Sid    = "PassSandboxNetworkConnectors"
        Effect = "Allow"
        Action = "lambda:PassNetworkConnector"
        Resource = [
          aws_lambdacore_network_connector.agent_sandbox_egress[0].arn,
          local.agent_sandbox_http_ingress_connector_arn,
        ]
      },
    ]
  })
}
