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

# Invoke permission is not sufficient on its own: each Bedrock model has to be
# activated in the account first, which means a Marketplace agreement and, for
# Anthropic models, a one-time use-case form.
#
# Deliberately not managed here, though the provider can do it with
# data.aws_bedrock_foundation_model_agreement_offers,
# aws_bedrock_use_case_for_model_access and
# aws_bedrock_foundation_model_agreement. Three reasons: the form carries the
# operator's own company and use-case details, which a module cannot invent and
# should not accept terms on behalf of; the agreement is account-wide rather
# than per deployment, so two stacks in one account would fight over it, and a
# destroy here would revoke access for everything else using that model; and
# ai_features_model takes an inference profile, which can span several
# foundation model IDs.
#
# Do it once per account before enabling the AI features. The README shows the
# resources for anyone who wants it in their own root module.
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
