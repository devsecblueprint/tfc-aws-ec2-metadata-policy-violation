# DevSecOps Lesson: Enforcing IMDSv2 with Terraform Cloud OPA Policies and AWS SCPs

## Lesson Title

**Defense-in-Depth Policy Enforcement for EC2 Instance Metadata Security**

## Lesson Overview

In this lesson, learners explore how DevSecOps teams can enforce secure cloud infrastructure by combining **Terraform Cloud OPA/Rego policy checks** with **AWS Service Control Policies (SCPs)**.

The lab demonstrates how to prevent EC2 instances from launching unless they enforce **IMDSv2** by setting:

```hcl
http_tokens = "required"
```

The repository begins in a compliant state. Learners intentionally change the configuration to a noncompliant state by setting:

```hcl
http_tokens = "optional"
```

They then observe how Terraform Cloud and AWS governance controls respond.

This lesson teaches a core DevSecOps principle: **security should be enforced as early as possible in the delivery pipeline and again at the cloud control plane.**

---

## Target Audience

This lesson is designed for:

- DevSecOps learners
- Cloud security students
- Terraform practitioners
- AWS engineers
- Platform engineering teams
- Security governance teams
- Candidates preparing for AWS, Terraform, DevOps, or DevSecOps roles

---

## Estimated Time

**30-45 minutes**

---

## Platform and Tools

| Component | Tool |
|---|---|
| Infrastructure as Code | Terraform |
| Cloud Platform | AWS |
| IaC Governance | Terraform Cloud |
| Policy Engine | OPA / Rego |
| Cloud Governance | AWS Service Control Policies |
| CI/CD | GitHub Actions |
| Version Control | GitHub |
| Runtime Target | EC2 |

---

## Repository Context

**Repository:** `tfc-aws-ec2-metadata-policy-violation`  
**Terraform Cloud Organization:** `devsecblueprint`  
**Terraform Cloud Workspace:** `tfc-aws-ec2-metadata-policy-violation`  
**Policy Engine:** OPA / Rego  
**Primary Security Control:** Require IMDSv2 for EC2 instances

The repository includes:

- Terraform code for an EC2 instance
- An OPA policy that blocks noncompliant metadata options
- OPA unit tests
- GitHub Actions workflows for Terraform and Rego validation
- Documentation explaining IMDSv1 risk, IMDSv2 mechanics, policy enforcement, and SCP governance layering

---

## Learning Objectives

By the end of this lesson, learners will be able to:

1. Explain why IMDSv1 creates security risk for EC2 workloads.
2. Describe how IMDSv2 reduces the risk of metadata credential theft.
3. Identify the Terraform configuration required to enforce IMDSv2.
4. Explain how Terraform Cloud OPA policies can block insecure infrastructure before apply.
5. Explain how AWS Service Control Policies provide organization-level enforcement at the AWS API layer.
6. Compare policy-as-code enforcement with cloud-native governance enforcement.
7. Interpret failed Terraform Cloud policy checks and AWS SCP deny messages.
8. Fix a noncompliant EC2 configuration and confirm a successful compliant run.
9. Describe how CI workflows support DevSecOps quality gates.
10. Explain why layered controls are important in real-world DevSecOps environments.

---

## Learning Outcomes

After completing this lesson, learners should be able to:

- Build a simple DevSecOps governance workflow using Terraform Cloud and OPA.
- Write or interpret an OPA policy that denies EC2 instances without IMDSv2.
- Understand how Rego unit tests validate policy behavior before deployment.
- Recognize the difference between pipeline-level controls and AWS account-level controls.
- Demonstrate how a noncompliant Terraform plan is denied.
- Demonstrate how an AWS SCP can deny the same insecure action even when Terraform Cloud policy enforcement is missing or misconfigured.
- Explain defense-in-depth using a practical cloud security example.
- Document policy enforcement results as evidence for security, compliance, or audit review.

---

## Key Concepts

### 1. Instance Metadata Service

AWS EC2 instances use the Instance Metadata Service to access information about themselves, including temporary IAM role credentials.

The metadata endpoint is available at:

```text
169.254.169.254
```

### 2. IMDSv1 Risk

IMDSv1 does not require session authentication. Any process that can reach the metadata endpoint may be able to retrieve live IAM credentials from the instance role.

This creates risk in scenarios involving:

- Server-side request forgery
- Misconfigured reverse proxies
- Vulnerable web applications
- Open firewalls
- Overly permissive network paths

### 3. IMDSv2 Protection

IMDSv2 requires a session token. A client must first make a `PUT` request to obtain a token before metadata can be read.

This makes metadata credential theft harder because simple request-forwarding attacks are less likely to succeed.

### 4. Policy as Code

Policy as code allows teams to define security rules in version-controlled files.

In this project, OPA/Rego is used to deny Terraform plans where EC2 instances do not require IMDSv2.

### 5. AWS Service Control Policies

SCPs enforce permission boundaries across AWS accounts in an organization.

Unlike Terraform Cloud policies, SCPs apply directly at the AWS API layer. This means they can block noncompliant actions regardless of whether the request comes from Terraform, the AWS CLI, the AWS Console, an SDK, or another automation tool.

---

## Security Principle

This lesson demonstrates **defense-in-depth**.

Terraform Cloud OPA policies enforce security before infrastructure is applied.

AWS SCPs enforce security at the cloud provider boundary.

Together, they reduce the chance that insecure EC2 instances are created.

---

## Repository Layout

```text
tfc-aws-ec2-metadata-policy-violation/
├── .github/
│   └── workflows/
│       ├── terraform.yml
│       └── rego-tests.yml
├── docs/
│   ├── imdsv1-security-risks.md
│   ├── policy-enforcement.md
│   ├── scp-comparison.md
│   └── issues.md
├── terraform/
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   └── .terraform.lock.hcl
└── policies/
    ├── require_imdsv2.rego
    └── require_imdsv2_test.rego
```

---

## Lesson Flow

### Part 1: Understand the Security Problem

Begin by reviewing the purpose of EC2 instance metadata.

Discuss why metadata credentials are sensitive.

The main issue is that IMDSv1 allows metadata access without requiring a session token. If an attacker can trick an application into making a request to the metadata endpoint, they may be able to retrieve temporary IAM credentials.

Learners should understand that this is not just a theoretical issue. Metadata credential exposure has been part of real-world cloud security incidents.

---

### Part 2: Review the Secure Terraform Configuration

The repository ships in a compliant state.

In `terraform/main.tf`, the EC2 instance should include:

```hcl
metadata_options {
  http_tokens = "required"
}
```

This setting requires IMDSv2.

The secure state is:

```hcl
http_tokens = "required"
```

The insecure state is:

```hcl
http_tokens = "optional"
```

---

### Part 3: Review the OPA Policy

The OPA policy is stored at:

```text
policies/require_imdsv2.rego
```

Its purpose is to deny Terraform plans where EC2 instances do not require IMDSv2.

The policy acts as a Terraform Cloud quality gate.

If the EC2 instance allows IMDSv1, the policy produces a hard deny and prevents the run from reaching apply.

---

### Part 4: Review the Rego Unit Tests

The test file is stored at:

```text
policies/require_imdsv2_test.rego
```

The project includes 13 OPA unit tests.

These tests are executed by the GitHub Actions workflow:

```text
.github/workflows/rego-tests.yml
```

The workflow performs two checks:

```bash
opa test policies/ --verbose
opa check policies/ --strict
```

This helps ensure that the security policy itself is tested before it is trusted as a governance control.

---

### Part 5: Review the Terraform CI Workflow

The Terraform workflow is stored at:

```text
.github/workflows/terraform.yml
```

It runs on pushes to `main` and pull requests that touch the Terraform directory.

The workflow performs:

1. Terraform formatting check
2. Terraform initialization
3. Terraform validation
4. Speculative plan on pull requests
5. PR feedback through plan comments

This gives developers earlier feedback before changes reach the main branch.

---

## Hands-On Walkthrough

### Step 1: Authenticate Terraform CLI

Run:

```bash
terraform login
cd terraform
terraform init
```

This connects the local Terraform CLI to Terraform Cloud.

---

### Step 2: Confirm Terraform Cloud Workspace Settings

Verify that the Terraform Cloud workspace is configured with AWS environment variables:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION
```

The workspace should be connected to:

```text
Organization: devsecblueprint
Workspace: tfc-aws-ec2-metadata-policy-violation
```

---

### Step 3: Attach the OPA Policy Set

In Terraform Cloud, configure a new policy set.

| Setting | Value |
|---|---|
| VCS repository | This repository |
| Policies path | `policies/` |
| Policy framework | OPA |
| Enforcement level | Hard mandatory |
| Scope | `tfc-aws-ec2-metadata-policy-violation` workspace |

The important setting is:

```text
Enforcement level: Hard mandatory
```

This means a failed policy check blocks the Terraform run.

---

### Step 4: Create a Noncompliant Configuration

In `terraform/main.tf`, change:

```hcl
http_tokens = "required"
```

to:

```hcl
http_tokens = "optional"
```

Then commit and push:

```bash
git add terraform/main.tf
git commit -m "demo: revert to noncompliant IMDSv1 configuration"
git push origin main
```

---

### Step 5: Observe the Deny Behavior

#### Expected Result with OPA Policy Attached

Terraform Cloud should deny the run during the policy check phase.

The apply button should not appear.

This demonstrates early pipeline enforcement.

#### Expected Result without OPA Policy Attached

If the policy set is not attached, Terraform Cloud may allow the plan to continue.

However, the AWS organization SCP should deny the EC2 launch request at the AWS API layer.

Expected error pattern:

```text
api error UnauthorizedOperation: ... with an explicit deny in a service control policy
```

This demonstrates cloud-side enforcement.

---

### Step 6: Fix the Configuration

Return the EC2 metadata option to the compliant value:

```hcl
http_tokens = "required"
```

Commit and push:

```bash
git add terraform/main.tf
git commit -m "fix: enforce IMDSv2 (http_tokens = required)"
git push origin main
```

Expected result:

- Terraform Cloud OPA policy passes
- AWS SCP condition is satisfied
- EC2 instance creation is allowed

---

## Live Demonstration Results

| Run | `http_tokens` | TFC OPA | AWS SCP | Result |
|---|---|---|---|---|
| `run-vhswq1CP4gwJkeui` | `optional` | Passed because `require_imdsv2` was not yet attached | Denied | No instance created |
| `run-q4415sdzmcgCxMbm` | `required` | Passed | Allowed | Instance created |

Live demonstration instance:

```text
i-01703456fda7dfcf8
```

Region:

```text
us-east-1
```

Provider version:

```text
hashicorp/aws v6.48.0
```

Terraform runtime:

```text
v1.15.5 linux_amd64
```

---

## Discussion: OPA Policy vs AWS SCP

| Control | Enforcement Point | Scope | Strength |
|---|---|---|---|
| Terraform Cloud OPA | Terraform plan phase | Terraform-managed runs | Blocks insecure IaC before apply |
| AWS SCP | AWS API layer | Entire AWS organization/account boundary | Blocks noncompliant API calls from any source |

### Key Difference

OPA protects the Terraform workflow.

SCP protects the AWS environment.

A mature DevSecOps program should use both.

---

## DevSecOps Takeaways

### 1. Shift Left Is Not Enough

OPA policy checks shift security earlier into the delivery process, but they only protect the workflows where they are attached.

If a team forgets to attach the policy set, or if someone uses another tool, the OPA policy may not run.

### 2. Guardrails Must Also Exist at the Platform Layer

The SCP catches noncompliant EC2 launch attempts at the AWS API layer.

This provides stronger governance because it applies regardless of toolchain.

### 3. Security Policies Should Be Tested

The Rego test workflow validates the policy before relying on it.

Security rules are code. They need tests, syntax checks, and CI validation like any other code.

### 4. Developers Need Fast Feedback

The Terraform workflow gives early feedback on formatting, validation, and speculative plans.

This reduces friction and helps developers fix issues before merge.

### 5. Defense-in-Depth Reduces Misconfiguration Risk

The best result is not choosing between OPA and SCP.

The best result is using both:

```text
Developer workflow control + Cloud provider control = stronger security enforcement
```

---

## Assessment Questions

### Knowledge Check

1. What risk does IMDSv1 introduce for EC2 instances?
2. Why does IMDSv2 reduce the likelihood of metadata credential theft?
3. What Terraform setting enforces IMDSv2?
4. What happens when `http_tokens` is set to `optional`?
5. What is the purpose of an OPA policy in Terraform Cloud?
6. What is the purpose of an AWS SCP?
7. Why is an SCP stronger than a Terraform-only control?
8. Why should Rego policies have unit tests?
9. What does “hard mandatory” mean in Terraform Cloud policy enforcement?
10. Why is defense-in-depth important in DevSecOps?

---

## Practical Assessment

Learners should be able to complete the following tasks:

1. Locate the EC2 metadata configuration in `terraform/main.tf`.
2. Change the configuration from compliant to noncompliant.
3. Trigger a Terraform Cloud run.
4. Identify whether the run was blocked by OPA or by AWS SCP.
5. Restore the compliant configuration.
6. Confirm that the OPA policy passes.
7. Explain the difference between the failed and successful runs.
8. Describe how this control could be applied across multiple teams or AWS accounts.

---

## Expected Learner Explanation

A strong learner should be able to explain the project like this:

> This project demonstrates layered DevSecOps governance for EC2 metadata security. Terraform defines an EC2 instance that must require IMDSv2. Terraform Cloud uses an OPA/Rego policy to block plans where `http_tokens` is not set to `required`. If that policy is missing or not attached, an AWS Service Control Policy still blocks noncompliant `ec2:RunInstances` calls at the AWS API layer. This shows why DevSecOps teams should enforce security both in the pipeline and at the cloud platform boundary.

---

## Cleanup

Destroy the EC2 instance:

```bash
cd terraform
terraform destroy -auto-approve
```

Delete the Terraform Cloud policy set:

1. Open Terraform Cloud.
2. Go to **Settings -> Policy sets**.
3. Open the `require_imdsv2` policy set.
4. Select **Edit**.
5. Delete the policy set.

Delete the Terraform Cloud workspace:

1. Open the workspace.
2. Go to **Settings -> Destruction and Deletion**.
3. Delete the workspace from Terraform Cloud.

Remove demo AWS credentials:

```bash
aws iam delete-access-key --user-name <demo-user> --access-key-id <key-id>
aws iam delete-user --user-name <demo-user>
```

---

## Final Lesson Summary

This lesson shows how DevSecOps teams can prevent insecure EC2 configurations by enforcing IMDSv2 through multiple layers of control.

Terraform Cloud OPA policies provide early feedback and block insecure Terraform plans.

AWS SCPs provide organization-level enforcement that blocks noncompliant EC2 launches at the AWS API layer.

Together, these controls demonstrate a practical defense-in-depth model for cloud infrastructure security.

The major lesson is simple:

```text
Do not rely on one control when the risk matters.
Test the policy, enforce it early, and backstop it at the platform layer.
```
