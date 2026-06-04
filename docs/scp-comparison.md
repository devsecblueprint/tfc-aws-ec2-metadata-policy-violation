# Governance Layering: OPA Policies and SCPs

## What SCPs Enforce

AWS Service Control Policies (SCPs) are permission guardrails applied to AWS Organizations accounts and organizational units (OUs). Unlike IAM policies — which grant permissions — SCPs define the **ceiling** of what any principal within the OU can be allowed to do. Every IAM authorization evaluation intersects with the active SCPs; if the SCP says deny, IAM says deny, regardless of what the identity's own policies grant.

SCPs are evaluated at the **API layer**, at the moment an AWS API call is made.

### SCP: Deny EC2 Launch Without IMDSv2

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyIMDSv1Launch",
      "Effect": "Deny",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringNotEquals": {
          "ec2:MetadataHttpTokens": "required"
        }
      }
    }
  ]
}
```

This SCP denies `ec2:RunInstances` for any instance where `MetadataHttpTokens` is not `"required"`. It applies to every principal in the OU — IAM users, assumed roles, Lambda execution roles, service accounts, and any other identity — regardless of the tool used to make the call.

---

## Control Comparison

| Dimension | Terraform Cloud OPA Policy | SCP |
|---|---|---|
| **Where it enforces** | Terraform plan (pre-deployment, developer workflow) | AWS IAM API layer (runtime, every API call) |
| **Who it covers** | Only Terraform-managed runs through TFC | Every AWS principal in the OU — console, CLI, SDK, CI/CD, other IaC tools |
| **Bypass risk** | Anyone not using Terraform Cloud is not covered | No bypass path short of moving the account out of the OU |
| **Feedback quality** | Custom violation message from Rego `sprintf`; names the exact resource and value | Generic `Access Denied` with an IAM error code; requires CloudTrail to trace |
| **Feedback timing** | Plan phase — before any API call is attempted | At `RunInstances` — after Terraform has committed to applying |
| **Developer loop** | Visible in the PR/plan output; fast iteration | Visible only in CloudTrail and operational alerts |
| **Retroactive enforcement** | No — evaluates plans, not live state | No — enforces at API call, not on existing instances |
| **Policy lifecycle** | Git-versioned `.rego` file, reviewed like application code | Managed in AWS Organizations; changes require org-level permissions |
| **Free tier accessible** | Yes — OPA policy sets included at no cost on TFC free tier | Yes — SCPs are included with AWS Organizations |

---

## Why Neither Control Alone Is Sufficient

**OPA policy only:** Any developer or CI system that bypasses Terraform Cloud — a direct `aws ec2 run-instances` call, a CloudFormation template, a console click — is completely uncovered. The policy has no visibility outside TFC runs.

**SCP only:** The SCP catches everything at the API layer, but the developer finds out only when the `RunInstances` call is rejected — after writing the configuration, submitting it for review, and triggering an apply. The error is a generic IAM denial; the developer must cross-reference CloudTrail and the SCP document to understand what changed. There is no fast feedback loop and no connection to the specific resource or line of code that caused the denial.

---

## The Governance Stack

A mature AWS governance posture layers both controls across the deployment lifecycle:

```
Developer writes Terraform
         │
         ▼
┌─────────────────────────────────────────────┐
│  Terraform Cloud OPA Policy                 │  ← plan-time
│  policies/require_imdsv2.rego               │    developer feedback
│  Enforcement: hard-mandatory                │    precise violation message
│  Scope: TFC-managed runs only               │
└─────────────────────────────────────────────┘
         │ plan passes
         ▼
┌─────────────────────────────────────────────┐
│  Terraform Cloud applies                    │  ← calls ec2:RunInstances
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  AWS SCP: DenyIMDSv1Launch                  │  ← API-time
│  Scope: every principal in the OU           │    universal backstop
│  Bypass: none (short of OU removal)         │
└─────────────────────────────────────────────┘
```

The OPA policy is the **developer-facing feedback layer** — it shifts detection left into the Git workflow, surfaces an exact remediation message, and prevents the plan from progressing before any AWS API is touched. It reduces the cost of misconfiguration by catching it early.

The SCP is the **infrastructure-level backstop** — it enforces the same control universally, regardless of toolchain. It ensures that a team member using the console, a script using the AWS CLI, or a third-party tool that does not integrate with Terraform Cloud cannot launch IMDSv1-accessible instances.

Both controls enforce the same invariant (`http_tokens = "required"`). They are not redundant — they cover different threat surfaces and operate at different points in the lifecycle. Neither replaces the other.

---

## Applying This Pattern to Other Controls

The same pairing applies to any AWS configuration invariant that can be expressed as an IAM condition key:

| Control | OPA Policy Check | SCP Condition Key |
|---|---|---|
| IMDSv2 required | `http_tokens != "required"` | `ec2:MetadataHttpTokens` |
| EBS encryption at rest | `encrypted != true` on `aws_ebs_volume` | `ec2:Encrypted` |
| S3 block public access | missing `block_public_acls = true` | `s3:PublicAccessBlockConfiguration` |
| RDS encryption | `storage_encrypted != true` | `rds:StorageEncrypted` |
| IMDSv2 hop limit | `http_put_response_hop_limit > 1` | `ec2:MetadataHttpPutResponseHopLimit` |

For each: write the Rego rule to catch misconfigurations at plan time, and pair it with the SCP condition to enforce at the API layer. The policy-as-code file and the SCP document both belong in version control.
