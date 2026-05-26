locals {
  code_based_eval_executor_lambda_configs = {
    python = {
      function_name = "${var.name}-code-based-eval-executor-python"
      runtime       = "python3.14"
      handler       = "index.handler"
      filename      = "index.py"
      source_path   = "${path.module}/code-eval-runners/python/code_based_eval_handler.py"
    }
    node = {
      function_name = "${var.name}-code-based-eval-executor-node"
      runtime       = "nodejs24.x"
      handler       = "index.handler"
      filename      = "index.mjs"
      source_path   = "${path.module}/code-eval-runners/node/code-based-eval-handler.mjs"
    }
  }

  code_based_eval_executor_lambda_names = {
    for runtime, config in local.code_based_eval_executor_lambda_configs : runtime => config.function_name
  }
}

module "code_based_eval_executor_vpc" {
  count = var.enable_code_based_eval_executors ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.name}-vpc-code-based-eval"
  cidr = var.vpc_cidr_block_code_based_evals

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr_block_code_based_evals, 2, k)]

  create_igw         = false
  enable_nat_gateway = false

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_iam_role             = true
  create_flow_log_cloudwatch_log_group            = true
  flow_log_cloudwatch_log_group_name_prefix       = "${var.name}-code-based-eval-"
  flow_log_cloudwatch_log_group_retention_in_days = 14
  flow_log_cloudwatch_log_group_class             = "INFREQUENT_ACCESS"

  tags = {
    Name = "${local.tag_name} Code-Based Eval"
  }
}

data "archive_file" "code_based_eval_executor" {
  for_each = var.enable_code_based_eval_executors ? local.code_based_eval_executor_lambda_configs : {}

  type        = "zip"
  output_path = "${path.module}/.terraform/code_based_eval_executor_${each.key}.zip"

  source {
    content  = file(each.value.source_path)
    filename = each.value.filename
  }
}

resource "aws_security_group" "code_based_eval_executor_lambda" {
  count = var.enable_code_based_eval_executors ? 1 : 0

  name        = "${var.name}-code-based-eval-executor-lambda"
  description = "No-ingress/no-egress security group for code-based eval executor Lambdas"
  vpc_id      = module.code_based_eval_executor_vpc[0].vpc_id

  # Defense-in-depth with the isolated route table: deny all Lambda ENI egress,
  # including VPC-local destinations.
  ingress = []
  egress  = []

  tags = {
    Name = "${local.tag_name} Code-Based Eval Executor Lambda"
  }
}

resource "aws_cloudwatch_log_group" "code_based_eval_executor" {
  for_each = var.enable_code_based_eval_executors ? local.code_based_eval_executor_lambda_names : {}

  name              = "/aws/lambda/${each.value}"
  retention_in_days = 30
}

resource "aws_iam_role" "code_based_eval_executor_lambda" {
  count = var.enable_code_based_eval_executors ? 1 : 0

  name = "${var.name}-code-based-eval-executor-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.tag_name} Code-Based Eval Executor Lambda"
  }
}

resource "aws_iam_role_policy" "code_based_eval_executor_lambda" {
  count = var.enable_code_based_eval_executors ? 1 : 0

  name = "${var.name}-code-based-eval-executor-lambda"
  role = aws_iam_role.code_based_eval_executor_lambda[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteFunctionLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          for log_group in values(aws_cloudwatch_log_group.code_based_eval_executor) : "${log_group.arn}:*"
        ]
      },
      {
        # AWS requires these permissions on "*" for VPC-attached Lambdas so the
        # Lambda service can manage Hyperplane ENIs on behalf of the function.
        # See: https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html#configuration-vpc-security
        Sid    = "ManageLambdaVpcNetworkInterfaces"
        Effect = "Allow"
        Action = [
          "ec2:AssignPrivateIpAddresses",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:UnassignPrivateIpAddresses",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_lambda_function" "code_based_eval_executor" {
  for_each = var.enable_code_based_eval_executors ? local.code_based_eval_executor_lambda_configs : {}

  function_name = each.value.function_name
  runtime       = each.value.runtime
  handler       = each.value.handler
  role          = aws_iam_role.code_based_eval_executor_lambda[0].arn

  filename         = data.archive_file.code_based_eval_executor[each.key].output_path
  source_code_hash = data.archive_file.code_based_eval_executor[each.key].output_base64sha256

  architectures                  = ["arm64"]
  memory_size                    = var.code_based_eval_executor_lambda_settings[each.key].memory_size
  timeout                        = var.code_based_eval_executor_lambda_settings[each.key].timeout
  reserved_concurrent_executions = var.code_based_eval_executor_lambda_settings[each.key].reserved_concurrent_executions

  ephemeral_storage {
    size = 512
  }

  tenancy_config {
    tenant_isolation_mode = "PER_TENANT"
  }

  vpc_config {
    security_group_ids = [aws_security_group.code_based_eval_executor_lambda[0].id]
    subnet_ids         = module.code_based_eval_executor_vpc[0].private_subnets
  }

  depends_on = [
    aws_cloudwatch_log_group.code_based_eval_executor,
    aws_iam_role_policy.code_based_eval_executor_lambda,
  ]
}

resource "aws_iam_role_policy" "code_based_eval_executor_lambda_deny_function_code_vpc_eni_management" {
  count = var.enable_code_based_eval_executors ? 1 : 0

  name = "${var.name}-code-based-eval-executor-lambda-deny-code-eni"
  role = aws_iam_role.code_based_eval_executor_lambda[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Match AWS's recommended least-privilege deny pattern: keep ENI management
        # available to the Lambda service, but deny those EC2 API calls from function code.
        # See: https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html#configuration-vpc-security
        Sid    = "DenyFunctionCodeVpcNetworkInterfaceManagement"
        Effect = "Deny"
        Action = [
          "ec2:AssignPrivateIpAddresses",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:UnassignPrivateIpAddresses",
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "lambda:SourceFunctionArn" = [
              for lambda_function in values(aws_lambda_function.code_based_eval_executor) : lambda_function.arn
            ]
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "langfuse_code_based_eval_executor_invoke" {
  count = var.enable_code_based_eval_executors ? 1 : 0

  name = "code-based-eval-executor-invoke"
  role = aws_iam_role.langfuse_irsa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeCodeBasedEvalExecutors"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
        ]
        Resource = [
          for lambda_function in values(aws_lambda_function.code_based_eval_executor) : lambda_function.arn
        ]
      },
    ]
  })

  depends_on = [aws_iam_role_policy.code_based_eval_executor_lambda_deny_function_code_vpc_eni_management]
}
