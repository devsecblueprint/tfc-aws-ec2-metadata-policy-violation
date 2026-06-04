# Known Issues and Resolutions

Issues encountered during the setup and CI configuration of this project, documented for reference.

---

## Issue 1 — Terraform Version Constraint Blocks TFC Workspace Runtime

**Symptom**

```
This configuration does not support Terraform version 1.6.6. To proceed,
either choose another supported Terraform version or update this version
constraint. Version constraints are normally set for good reason, so updating
the constraint may lead to other errors or unexpected behavior.

Error: Terraform exited with code 1.
Error: Process completed with exit code 1.
```

**Cause**

The `required_version` in `terraform/versions.tf` was initially set to an exact pin (`"1.15.5"`), which did not match the Terraform version configured in the TFC workspace (`1.6.6`). The constraint is evaluated at multiple independent layers:

1. The local Terraform CLI running in GitHub Actions
2. TFC during the remote `init`
3. TFC during the remote plan run

Any version string difference between these layers — including how TFC internally reports its build version — causes the check to fail. Attempts to relax the constraint to `">= 1.6"` and then `">= 1.6.6"` continued to fail for the same reason.

**Resolution**

Removed `required_version` from `terraform/versions.tf` entirely. The TFC workspace's **Terraform Version** setting (workspace **Settings → General**) is the authoritative control for which version runs. A local version gate adds no safety for TFC-backed workspaces and only introduces friction across layers.

```hcl
# Before (caused failure)
terraform {
  required_version = "1.15.5"
  cloud { ... }
}

# After (working)
terraform {
  cloud { ... }
}
```

---

## Issue 2 — `terraform_version: "~> 1.6"` Installs Wrong Version in CI

**Symptom**

The `hashicorp/setup-terraform` action installed the latest `1.x` release (e.g., `1.15.x`) instead of a `1.6.x` release, creating a version mismatch with the TFC workspace configured at `1.6.6`.

**Cause**

In Terraform's version constraint syntax, `~> 1.6` means `>= 1.6.0, < 2.0.0` — it allows any `1.x` release, not just `1.6.x` patch releases. To constrain to only `1.6.x` patches, the correct form is `~> 1.6.0` (with the patch component included). The `hashicorp/setup-terraform` action passes this value directly to HashiCorp's version resolution, so `~> 1.6` resolved to the latest `1.x` available.

**Resolution**

Removed the `terraform_version` pin from all three `setup-terraform` steps in `.github/workflows/terraform.yml`. The action uses its bundled default Terraform version, which is consistent and does not conflict with the TFC workspace version setting.

```yaml
# Before (installed latest 1.x, not 1.6.x)
- uses: hashicorp/setup-terraform@v4
  with:
    terraform_version: "~> 1.6"

# After (uses action default, no conflict)
- uses: hashicorp/setup-terraform@v4
  with:
    cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}
```

---

## Issue 3 — GitHub Actions Running on Deprecated Node.js 20 Runtime

**Symptom**

```
Node.js 20 actions are deprecated. The following actions are running on
Node.js 20 and may not work as expected: actions/checkout@v4,
hashicorp/setup-terraform@v3. Actions will be forced to run with Node.js 24
by default starting June 16th, 2026.
```

**Cause**

The workflow was pinned to action versions that use the Node.js 20 runtime:
- `actions/checkout@v4` — Node.js 20
- `hashicorp/setup-terraform@v3` — Node.js 20
- `actions/github-script@v7` — Node.js 20

GitHub announced that Node.js 20 would be deprecated for Actions runners as of June 16, 2026, requiring all actions to migrate to Node.js 24.

**Resolution**

Updated all three actions to their latest major versions, which ship with the Node.js 24 runtime:

| Action | Before | After |
|---|---|---|
| `actions/checkout` | `v4` | `v6` |
| `hashicorp/setup-terraform` | `v3` | `v4` |
| `actions/github-script` | `v7` | `v9` |

Both workflow files were updated: `.github/workflows/terraform.yml` and `.github/workflows/rego-tests.yml`.
