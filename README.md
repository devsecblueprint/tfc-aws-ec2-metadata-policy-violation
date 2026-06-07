# tfc-aws-ec2-metadata-policy-violation

**Platform:** Terraform Cloud (Free Tier) · **Policy engine:** OPA / Rego · **Time:** ~30 min  
**Org:** `devsecblueprint` · **Workspace:** `tfc-aws-ec2-metadata-policy-violation`

Demonstrates how Terraform Cloud OPA policy enforcement and AWS Service Control Policies
(SCPs) work together to block EC2 instances that do not enforce IMDSv2. The repository
ships in the **compliant state** (`http_tokens = "required"`). To observe the deny
behaviour, revert that one value to `"optional"` — the OPA policy hard-denies the plan,
and if the policy set is not yet attached, the org-level SCP denies `ec2:RunInstances` at
the AWS API layer.

---

## Why This Matters

IMDSv1 requires no authentication — any process that can reach `169.254.169.254` can
retrieve the instance role's live IAM credentials. This is the SSRF attack path exploited
in the [Capital One breach (2019)](https://aws.amazon.com/blogs/security/defense-in-depth-open-firewalls-reverse-proxies-and-ssrf-vulnerabilities-aws/).
IMDSv2 breaks that path by requiring a session token obtained via `PUT` before any
metadata can be read.

Full risk analysis and IMDSv2 mechanics: [docs/imdsv1-security-risks.md](docs/imdsv1-security-risks.md)

---

## Repository Layout

```
tfc-aws-ec2-metadata-policy-violation/
├── .github/
│   └── workflows/
│       ├── terraform.yml          # fmt check → validate → speculative plan (PR comment)
│       └── rego-tests.yml         # OPA unit tests via opa test + opa check
├── docs/
│   ├── imdsv1-security-risks.md   # IMDSv1 attack surface; IMDSv2 mechanics
│   ├── policy-enforcement.md      # TFC OPA setup, failed run output, passing run output
│   ├── scp-comparison.md          # Governance layering: TFC OPA policies vs SCPs
│   └── issues.md                  # Documented issues and resolutions from this project
├── terraform/
│   ├── versions.tf                # TFC cloud block (org: devsecblueprint)
│   ├── variables.tf               # aws_region variable
│   ├── main.tf                    # EC2 resource — compliant by default
│   └── .terraform.lock.hcl       # Provider lock file (hashicorp/aws v6.48.0)
└── policies/
    ├── require_imdsv2.rego        # OPA policy: hard-deny if http_tokens != "required"
    └── require_imdsv2_test.rego   # 13 OPA unit tests (run by rego-tests.yml)
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Terraform CLI | [Download](https://developer.hashicorp.com/terraform/install) or `brew install terraform` |
| Terraform Cloud account | Free at [app.terraform.io](https://app.terraform.io) |
| AWS account + IAM credentials | `ec2:DescribeImages` for plan; `ec2:RunInstances` to apply |
| Git + VCS provider connected to TFC | GitHub, GitLab, or Bitbucket |

**GitHub repository secret** required for the Actions workflows:

| Secret | Source |
|---|---|
| `TF_API_TOKEN` | TFC → User Settings → Tokens → Create API token (Plan + Write access) |

No OPA CLI required locally — the `rego-tests.yml` workflow installs OPA `v0.68.0` in CI
automatically. Terraform Cloud runs the policy engine server-side for plan-time checks.

---

## CI Workflows

### `terraform.yml`

Triggers on push to `main` or PRs touching `terraform/**`.

| Job | Runs on | What it does |
|---|---|---|
| `fmt` | all events | `terraform fmt -check -recursive` |
| `validate` | all events | `terraform init` + `terraform validate` via TFC backend |
| `plan` | PRs only | TFC speculative plan; posts output as a PR comment (updates on re-push) |

On push to `main`, TFC's VCS integration triggers the real plan + apply automatically.
The `plan` job only runs on PRs to provide early feedback without duplicating the
VCS-triggered run.

### `rego-tests.yml`

Triggers on push to `main` or PRs touching `policies/**`.

Installs OPA `v0.68.0`, runs `opa test policies/ --verbose` against all 13 unit tests in
`policies/require_imdsv2_test.rego`, then runs `opa check policies/ --strict` to validate
policy syntax.

---

## Walkthrough

### 1. Confirm Workspace Configuration

The workspace and org are already configured in `terraform/versions.tf`. AWS credentials
are set as workspace environment variables in TFC (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`).

To authenticate the local CLI:

```bash
terraform login
cd terraform && terraform init
```

### 2. Attach the OPA Policy Set

In TFC: **Settings → Policy sets → Connect a new policy set**

| Setting | Value |
|---|---|
| VCS repository | this repository |
| Policies path | `policies/` |
| Policy framework | OPA |
| Enforcement level | Hard mandatory |
| Scope | `tfc-aws-ec2-metadata-policy-violation` workspace |

Full setup steps: [docs/policy-enforcement.md](docs/policy-enforcement.md)

### 3. Observe the Noncompliant Deny

In `terraform/main.tf`, change `http_tokens = "required"` to `http_tokens = "optional"`,
then push:

```bash
git add terraform/main.tf
git commit -m "demo: revert to noncompliant IMDSv1 configuration"
git push origin main
```

**With the policy set attached:** TFC hard-denies at the policy check phase — no apply
button appears.

**Without the policy set attached:** The plan passes TFC but the org SCP
(`p-8sjoex3z`) denies `ec2:RunInstances` at the AWS API layer with a 403:

```
api error UnauthorizedOperation: ... with an explicit deny in a service control policy
```

Both outcomes are documented in [docs/issues.md § Issue 4](docs/issues.md#issue-4--scp-denied-ec2runinstances-when-http_tokens--optional).

### 4. Fix and Confirm the Compliant Run

Revert to `http_tokens = "required"`:

```bash
git add terraform/main.tf
git commit -m "fix: enforce IMDSv2 (http_tokens = required)"
git push origin main
```

The OPA policy check passes, the SCP condition is satisfied, and the EC2 instance is
created. In the live demonstration run, the instance was created as `i-01703456fda7dfcf8`
in `us-east-1`.

### 5. Understand the Full Control Stack

The OPA policy covers Terraform-managed runs only. The SCP enforces the same invariant
universally at the AWS API layer — catching any `ec2:RunInstances` call regardless of
toolchain. See [docs/scp-comparison.md](docs/scp-comparison.md) for the comparison table,
SCP JSON, and governance layering diagram.

---

## Live Run Results

These results are from the demonstration run against the `devsecblueprint` org.

| Run | `http_tokens` | TFC OPA | AWS SCP | Result |
|---|---|---|---|---|
| `run-vhswq1CP4gwJkeui` | `optional` | Passed (`deny_public_sg` only — `require_imdsv2` not yet attached) | **Denied** | No instance created |
| `run-q4415sdzmcgCxMbm` | `required` | Passed | Allowed | `i-01703456fda7dfcf8` created |

Provider version used: `hashicorp/aws v6.48.0` · Terraform runtime: `v1.15.5 linux_amd64`

---

## Cleanup

```bash
# Destroy the running EC2 instance
cd terraform && terraform destroy -auto-approve
```

Then in Terraform Cloud:

1. **Settings → Policy sets** → open `require_imdsv2` → **Edit → Delete policy set**
2. Open the workspace → **Settings → Destruction and Deletion → Delete from Terraform Cloud**

Remove demo AWS credentials:

```bash
aws iam delete-access-key --user-name <demo-user> --access-key-id <key-id>
aws iam delete-user --user-name <demo-user>
```

---

## Known Issues

Setup and CI issues encountered during this project — version constraint failures, Node.js
runtime deprecations, SCP deny on noncompliant apply — are documented with root causes and
resolutions in [docs/issues.md](docs/issues.md).

---

## References

**OPA / Rego**
- [OPA Documentation](https://www.openpolicyagent.org/docs/latest/)
- [Rego Language Reference](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [OPA Playground](https://play.openpolicyagent.org/)

**Terraform Cloud**
- [TFC OPA Policy Sets](https://developer.hashicorp.com/terraform/cloud-docs/policy-enforcement/opa)
- [Terraform Plan JSON Format](https://developer.hashicorp.com/terraform/internals/json-format)

**AWS**
- [Configuring IMDSv2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html)
- [aws_instance metadata_options — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance#metadata_options)
- [SCP example: Require IMDSv2](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_ec2.html#example_ec2_6)
