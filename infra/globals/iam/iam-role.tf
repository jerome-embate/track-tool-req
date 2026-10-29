locals {
  github_subs = [for name, ids in var.github_repos : "repo:${var.github_account}/${name}@${ids.repo_id}:ref:refs/heads/*"]
  ecr_repos   = [for name, ids in var.github_repos : "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${lower(name)}"]
}

module "iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "6.2.1"

  name = var.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = local.ecr_repos
      },
    ]
  })
}

module "iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.2.1"

  name = var.iam_role_name

  use_name_prefix = false

  trust_policy_permissions = {
    TrustRoleAndServiceToAssume = {
      actions = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]
      principals = [{
        type        = "Federated"
        identifiers = [data.aws_iam_openid_connect_provider.github.arn]
      }]
      condition = [{
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
        },
        {
          test     = "StringLike"
          variable = "token.actions.githubusercontent.com:sub"
          values   = local.github_subs
        }
      ]
    }
  }

  policies = {
    ECRReadWrite = module.iam_policy.arn
  }
}
