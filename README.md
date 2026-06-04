# tfc-aws-ec2-metadata-policy-violation

**Platform:** Terraform Cloud (Free Tier) · **Policy engine:** OPA / Rego · **Time:** ~30 min

Intentionally vulnerable Terraform configuration that deploys an AWS EC2 instance with
`http_tokens = "optional"`, allowing IMDSv1 access. A hard-mandatory OPA policy in
Terraform Cloud blocks the plan until `http_tokens = "required"` is set, enforcing IMDSv2.

---

## Why This Matters

IMDSv1 requires no authentication — any process that can reach `169.254.169.254` can retrieve
the instance role's live IAM credentials. This is the SSRF attack path used in the
[Capital One breach (2019)](https://aws.amazon.com/blogs/security/defense-in-depth-open-firewalls-reverse-proxies-and-ssrf-vulnerabilities-aws/).
IMDSv2 breaks that path by requiring a session token obtained via `PUT` before any metadata
can be read.

Full risk analysis and IMDSv2 mechanics: [docs/imdsv1-security-risks.md](docs/imdsv1-security-risks.md)

---

## Repository Layout

```
tfc-aws-ec2-metadata-policy-violation/
├── .github/
│   └── workflows/
│       ├── terraform.yml          # fmt check → validate → speculative plan (PR comment)
│       └── rego-tests.yml         # OPA unit tests for the Rego policy
├── docs/
│   ├── imdsv1-security-risks.md   # IMDSv1 attack surface; IMDSv2 as the fix
│   ├── policy-enforcement.md      # TFC setup, failed run output, compliant run output
│   └── scp-comparison.md          # Governance layering: OPA policies vs SCPs
├── terraform/
│   ├── versions.tf                # TFC cloud block + required providers
│   ├── variables.tf               # aws_region variable
│   └── main.tf                    # EC2 resource — starts noncompliant; fix shown inline
└── policies/
    ├── require_imdsv2.rego        # OPA policy that enforces http_tokens = "required"
    └── require_imdsv2_test.rego   # OPA unit tests (run by rego-tests.yml)
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Terraform CLI ≥ 1.6 | `brew install terraform` or [download](https://developer.hashicorp.com/terraform/install) |
| Terraform Cloud account | Free at [app.terraform.io](https://app.terraform.io) |
| AWS account + IAM credentials | `ec2:DescribeImages` for plan; add `ec2:RunInstances` to apply |
| Git + VCS provider connected to TFC | GitHub, GitLab, or Bitbucket |

**GitHub repository secrets** required for the Actions workflows:

| Secret | Where to get it |
|---|---|
| `TF_API_TOKEN` | TFC → User settings → Tokens → Create API token |

No OPA CLI required locally — Terraform Cloud runs the policy engine server-side; the
`rego-tests.yml` workflow installs OPA in CI automatically.

---

## Walkthrough

### 1. Configure Terraform Cloud

In `terraform/versions.tf`, replace `"your-org-name"` with your TFC organization name.

Create a workspace named `ec2-imdsv2-demo` with the **Terraform Working Directory** set to
`terraform/`. Add your AWS credentials as sensitive environment variables
(`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`).

### 2. Attach the OPA Policy Set

In **Settings → Policy sets → Connect a new policy set**, point at this repository with:

- **Policies path:** `policies/`
- **Policy framework:** OPA
- **Enforcement level:** Hard mandatory
- **Scope:** attach to the `ec2-imdsv2-demo` workspace

Full setup steps: [docs/policy-enforcement.md](docs/policy-enforcement.md)

### 3. Trigger the Noncompliant Run

With `main.tf` in its default state (`http_tokens = "optional"`), initialize and push:

```bash
cd terraform
terraform login
terraform init
git add . && git commit -m "demo: noncompliant IMDSv1 configuration"
git push origin main
```

The plan completes, the policy check runs, and the run is **hard-denied**. No apply button
appears. The violation message names the exact resource and value. Expected output is in
[docs/policy-enforcement.md § Demonstrating the Hard Deny](docs/policy-enforcement.md#demonstrating-the-hard-deny).

### 4. Fix and Rerun

In `terraform/main.tf`, change `http_tokens = "optional"` to `http_tokens = "required"`.

```bash
git add terraform/main.tf
git commit -m "fix: enforce IMDSv2 (http_tokens = required)"
git push origin main
```

The policy check passes. The apply is unblocked. Expected output is in
[docs/policy-enforcement.md § Fixing the Configuration](docs/policy-enforcement.md#fixing-the-configuration).

### 5. Understand the Full Control Stack

This OPA policy covers Terraform-managed runs only. Pair it with an SCP on your AWS
Organization to enforce the same invariant at the API layer for every principal and toolchain.

Comparison, SCP JSON, and governance layering diagram:
[docs/scp-comparison.md](docs/scp-comparison.md)

---

## Cleanup

```bash
# Destroy the EC2 instance (if applied)
cd terraform && terraform destroy -auto-approve
```

Then in Terraform Cloud:

1. **Settings → Policy sets** → open the policy set → **Edit → Delete policy set**
2. Open the `ec2-imdsv2-demo` workspace → **Settings → Destruction and Deletion → Delete from Terraform Cloud**

Remove demo AWS credentials:

```bash
aws iam delete-access-key --user-name <demo-user> --access-key-id <key-id>
aws iam delete-user --user-name <demo-user>
```

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
