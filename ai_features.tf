# One instance-wide Langfuse AI model powers the AI features: the in-app agent
# and Ask AI in the filter search bar. See
# https://langfuse.com/security/ai-features
#
# On AWS the model is normally Amazon Bedrock, which authenticates through the
# AWS credential chain rather than an API key, so the only resource needed here
# is invoke permission on the Langfuse IRSA role. Web and worker share that role
# via a single Kubernetes ServiceAccount, and both call the model: web for Ask AI
# and conversation titles, worker for agent runs. The LANGFUSE_AI_* variables are
# rendered in langfuse.tf.
#
# Non-Bedrock providers (anthropic, openai) need no AWS resources; pass their
# API key through additional_env with a secretKeyRef.

# Invoke permission is not sufficient on its own: each Bedrock model must be
# activated in the account first. The first invocation of a third-party model
# starts an AWS Marketplace subscription, and Anthropic models additionally
# require a one-time first-use form. Both are console actions that Terraform
# cannot perform, so do them with an administrator identity before enabling the
# AI features, and confirm the model responds in the Bedrock playground.
resource "aws_iam_role_policy" "langfuse_ai_features_bedrock" {
  count = var.ai_features_provider == "bedrock" && var.ai_features_model != null ? 1 : 0

  name = "ai-features-bedrock"
  role = aws_iam_role.langfuse_irsa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Invoke-only, and by default on every model: this is cost exposure
        # rather than privilege. Narrow it with ai_features_bedrock_model_arns.
        Sid    = "InvokeBedrockModels"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = var.ai_features_bedrock_model_arns
      },
    ]
  })
}
