# Enforcing IMDSv2 with Terraform Cloud OPA Policies

## How TFC OPA Enforcement Works

When a run triggers in Terraform Cloud, it executes in this sequence:

```
git push → TFC queues run → Plan → Policy Check → Apply (if unblocked)
```

During the **Policy Check** phase, TFC evaluates all OPA policies in the attached policy sets against the **Terraform plan JSON** — the structured representation of what the plan intends to create, update, or destroy. If any policy's `deny` rule produces a non-empty set, the result depends on the enforcement level:

| Enforcement Level | Behavior |
|---|---|
| `advisory` | Logs violations; does not block apply |
| `soft-mandatory` | Blocks apply; workspace owner can override |
| `hard-mandatory` | Blocks apply; **no override path exists** |

This walkthrough uses `hard-mandatory`. The EC2 instance cannot be created unless the policy passes.

---

## The Plan JSON Structure OPA Evaluates

Every `aws_instance` resource change in the plan appears in `input.resource_changes`. The relevant shape:

```json
{
  "resource_changes": [
    {
      "address": "aws_instance.demo",
      "type": "aws_instance",
      "change": {
        "actions": ["create"],
        "after": {
          "metadata_options": [
            {
              "http_endpoint": "enabled",
              "http_tokens": "optional",
              "http_put_response_hop_limit": 1
            }
          ]
        }
      }
    }
  ]
}
```

The policy reads `input.resource_changes`, finds entries of type `aws_instance`, and checks `change.after.metadata_options[*].http_tokens`.

---

## The Rego Policy

See [policies/require_imdsv2.rego](../policies/require_imdsv2.rego) for the full source. It defines two `deny` rules:

**Rule 1 — `http_tokens` is present but not `"required"`**

Iterates every create or update action on an `aws_instance`. For each `metadata_options` block where `http_tokens != "required"`, it emits a violation message naming the resource address and the actual value found.

**Rule 2 — `metadata_options` is absent entirely**

Catches the omission case. If no `metadata_options` block is defined, the AWS provider uses the insecure default (`http_tokens = "optional"`). This rule flags the resource before that default can take effect.

Both rules scope to `applicable_actions := {"create", "update"}` — destroy-only runs are not evaluated, preventing false positives on teardown.

The `deny` set is what Terraform Cloud reads. A non-empty `deny` set with `hard-mandatory` enforcement terminates the run.

---

## Terraform Cloud Setup (Free Tier)

### 1. Create an Organization

Sign in at [app.terraform.io](https://app.terraform.io). Click **Create new organization** and accept the free tier defaults. OPA policy sets are included at no cost.

### 2. Create the Workspace

1. **Projects & workspaces → New workspace → Version control workflow**
2. Connect your VCS provider (GitHub, GitLab, Bitbucket).
3. Select this repository. Set **Terraform Working Directory** to `terraform/`.
4. Name the workspace `ec2-imdsv2-demo`.

### 3. Set AWS Credentials

In the workspace **Variables** tab, add these as **Environment variables** and mark them sensitive:

| Key | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |
| `AWS_DEFAULT_REGION` | `us-east-1` |

The IAM principal needs `ec2:DescribeImages` (for the AMI data source) and `ec2:RunInstances` (for the instance). For demo purposes, `AmazonEC2ReadOnlyAccess` covers the plan phase; add `ec2:RunInstances` only if you intend to apply.

### 4. Create a VCS-Backed Policy Set

1. **Settings → Policy sets → Connect a new policy set**
2. Choose **VCS** and select this repository.
3. Set **Policies path** to `policies/`.
4. Set **Policy framework** to `OPA`.
5. Set **Enforcement level** to `Hard mandatory`.
6. Under **Scope**, attach this policy set to the `ec2-imdsv2-demo` workspace.
7. Save.

TFC will now pull `policies/require_imdsv2.rego` from the repository on every run for the attached workspace.

To verify attachment: open the workspace → **Settings → Policies**. Confirm `require_imdsv2` is listed with enforcement mode `hard-mandatory`.

---

## Demonstrating the Hard Deny

With `terraform/main.tf` containing `http_tokens = "optional"` (the starting state in this repository), push to trigger a run:

```bash
terraform login                        # authenticate CLI to TFC
cd terraform && terraform init         # initialize the cloud backend
git add . && git commit -m "demo: noncompliant IMDSv1 configuration"
git push origin main
```

TFC queues a plan automatically on push. After planning completes, the policy check runs.

### Policy Check Output — Fail

```
┌──────────────────────────────────────────────────────────────────┐
│ Policy check                                                     │
│ ─────────────────────────────────────────────────────────────── │
│ require_imdsv2 (hard-mandatory)                       × FAILED   │
│                                                                  │
│   1 violation:                                                   │
│                                                                  │
│   EC2 instance 'aws_instance.demo' must enforce IMDSv2.          │
│   http_tokens must be "required", found: "optional".             │
│                                                                  │
│ This result means Terraform Cloud prevented the planned changes  │
│ from being applied. A hard mandatory policy cannot be            │
│ overridden.                                                      │
└──────────────────────────────────────────────────────────────────┘
```

No apply button appears. The run is terminated. The violation message comes directly from the `sprintf` in the Rego policy.

---

## Fixing the Configuration

In `terraform/main.tf`, change one line:

```diff
  metadata_options {
    http_endpoint               = "enabled"
-   http_tokens                 = "optional"
+   http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
```

Push the fix:

```bash
git add terraform/main.tf
git commit -m "fix: enforce IMDSv2 (http_tokens = required)"
git push origin main
```

### Policy Check Output — Pass

```
┌──────────────────────────────────────────────────────────────────┐
│ Policy check                                                     │
│ ─────────────────────────────────────────────────────────────── │
│ require_imdsv2 (hard-mandatory)                       ✓ PASSED   │
│                                                                  │
│   No violations found.                                           │
└──────────────────────────────────────────────────────────────────┘
```

The apply is now unblocked. The EC2 instance is only created after the policy is satisfied. If auto-apply is disabled (the default), a manual confirmation step appears in the TFC UI before the instance is launched.
