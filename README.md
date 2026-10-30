# TrackTool

**TRACK. MANAGE. RECOVER.**

A Next.js app, containerized with Docker and deployed to AWS ECS Fargate behind an Application Load Balancer, served at [https://tracktool.embate.dev](https://tracktool.embate.dev).

- **App:** Next.js 16, React 19, Tailwind CSS 4, pnpm
- **Container:** multi-stage Docker build on `node:22-alpine` using Next.js standalone output
- **Infrastructure:** Terraform (VPC, ECR, ECS Fargate, ALB, Route 53, ACM, IAM)
- **CI/CD:** GitHub Actions builds a versioned image on every push to `main` and deploys it to ECS

## Local development

```bash
pnpm install
pnpm dev
```

Open [http://localhost:3000](http://localhost:3000). The page lives in `app/page.tsx`.

## Docker

```bash
docker compose up --build
```

Or with plain Docker:

```bash
docker build -t track-tool .
docker run --rm -p 3000:3000 track-tool
```

The image runs the Next.js standalone server (`node server.js`) as a non-root user on port 3000.

## Infrastructure

Terraform lives in `infra/`, split into separately applied stacks, each with its own state in S3:

```
infra/
├── globals/                  # Shared across environments
│   ├── s3/                   # Terraform state bucket (apply first)
│   ├── ecr/                  # ECR repository per GitHub repo
│   ├── iam/                  # GitHub Actions OIDC role for CI/CD
│   ├── global.tfvars
│   └── state.config          # S3 backend settings
└── dev/
    ├── vpc/                  # VPC, 2 public + 2 private subnets, optional NAT
    ├── ecs/                  # Fargate service, ALB, security groups, HTTPS, DNS
    ├── dev.tfvars
    └── state.config
```

### Apply order

```bash
# 1. State bucket. On a fresh account the bucket doesn't exist yet: comment out the
#    backend block in s3/state.tf, apply with local state, then restore the block and
#    run `terraform init -migrate-state -backend-config=../state.config`.
cd infra/globals/s3
terraform init -backend-config=../state.config && terraform apply -var-file=../global.tfvars

# 2. ECR and the GitHub Actions IAM role
cd ../ecr
terraform init -backend-config=../state.config && terraform apply -var-file=../global.tfvars
cd ../iam
terraform init -backend-config=../state.config && terraform apply -var-file=../global.tfvars

# 3. Push an initial image to ECR (see "Pushing an image manually")

# 4. Networking, then the app
cd ../../dev/vpc
terraform init -backend-config=../state.config && terraform apply -var-file=../dev.tfvars -var-file=vpc.tfvars
cd ../ecs
terraform init -backend-config=../state.config && terraform apply -var-file=../dev.tfvars -var-file=ecs.tfvars
```

The ECS stack reads the VPC's outputs from its remote state, so the VPC must be applied first.

### HTTPS and DNS

The ALB redirects HTTP to HTTPS and serves `tracktool.embate.dev` using an ACM wildcard certificate for `embate.dev` / `*.embate.dev`. The certificate and the Route 53 hosted zone are created outside Terraform; the ECS stack looks up the certificate (it must be `ISSUED`) and creates the `A` alias record to the ALB. Change the domain with `domain_name` and `app_subdomain` in `infra/dev/ecs/ecs.tfvars`.

### Cost settings (dev)

| Setting | Where | Default | Effect |
|---|---|---|---|
| `enable_nat_gateway` | `dev/vpc` | `false` | NAT gateway off saves ~$36/month. Tasks then run in public subnets with public IPs. |
| `use_private_subnets` | `dev/ecs/ecs.tfvars` | `false` | Set to `true` only after enabling the NAT gateway; otherwise tasks can't pull from ECR. |
| `use_fargate_spot` | `dev/ecs/ecs.tfvars` | `true` | ~70% cheaper; tasks can be interrupted and are replaced automatically. |

App tasks only accept traffic from the ALB security group, even while they have public IPs.

To move tasks into private subnets: set `enable_nat_gateway = true` and apply `dev/vpc`, then set `use_private_subnets = true` and apply `dev/ecs`.

## CI/CD

`.github/workflows/deploy.yml` runs on every push to `main` (changes only under `infra/` or to Markdown files are skipped), and can also be run manually from the Actions tab.

1. Computes the next version with `scripts/git_update.sh`
2. Builds the image for `linux/amd64` and pushes it to ECR tagged with that version
3. Pushes the version as a git tag
4. Registers a new task definition revision with the new image and deploys it, waiting for the service to become stable

The ECS deployment circuit breaker rolls back automatically if the new tasks fail health checks.

### Versioning

Images and git tags use semantic versions (`vX.Y.Z`), incremented from the latest version tag in git:

- Every push to `main` bumps the **patch** version: `v0.1.1` → `v0.1.2`
- For a **minor** or **major** bump, run the workflow manually (*Actions → Build and Deploy to ECS → Run workflow*) and choose the bump type

ECR tags are immutable, so every release gets a new tag. Re-running a workflow on an already tagged commit reuses its version and skips the build if the image already exists.

To preview the next version locally (this creates a local git tag; delete it with `git tag -d <tag>`):

```bash
./scripts/git_update.sh -v patch
```

### Required GitHub secrets

| Secret | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `AWS_IAM_ROLE` | ARN of the `track-tool-github-actions` role from `infra/globals/iam` |

GitHub Actions authenticates to AWS through OIDC; no AWS access keys are stored in GitHub.

### Terraform and CI together

GitHub Actions owns which task definition revision the service runs, so the ECS service ignores `task_definition` changes in Terraform. `image_tag` in `ecs.tfvars` only sets the image for the initial task definition. Terraform changes to the task definition (CPU, memory, etc.) register a new revision that the next CI deploy builds on.

## Pushing an image manually

Only needed for the first deploy or outside CI. Build without attestations, because ECS can't pull images pushed with provenance or SBOM attestations, and use a tag that won't collide with CI's `vX.Y.Z` tags:

```bash
REGISTRY=<account-id>.dkr.ecr.us-east-1.amazonaws.com
TAG=v0.1.0-$(git rev-parse --short HEAD)

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REGISTRY
docker build --platform linux/amd64 --provenance=false --sbom=false -t $REGISTRY/track-tool-req:$TAG .
docker push $REGISTRY/track-tool-req:$TAG
```

## Troubleshooting

- **App logs:** CloudWatch log group `/ecs/dev-track-tool`
- **`CannotPullContainerError: mismatched image rootfs and manifest layers`:** the image was pushed with attestations. Rebuild with `--provenance=false --sbom=false` and push under a new tag.
- **`exec format error`:** the image was built for ARM (e.g. on Apple Silicon). Rebuild with `--platform linux/amd64`.
- **`Not authorized to perform sts:AssumeRoleWithWebIdentity` in CI:** the role's trust policy `sub` condition in `infra/globals/iam/iam-role.tf` doesn't match the token GitHub sends for this repo.
