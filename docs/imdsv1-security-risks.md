# EC2 Instance Metadata: IMDSv1 Risks and IMDSv2 as the Secure Default

## What IMDS Is

Every EC2 instance can reach a link-local HTTP server at `169.254.169.254`. This is the **Instance Metadata Service (IMDS)**. It answers questions like:

- What IAM role is attached to this instance, and what are its current credentials?
- What is in the instance user-data script?
- What is this instance's public IP, VPC ID, security groups?

Workloads running on the instance use IMDS to discover their environment and obtain short-lived IAM credentials without embedding secrets in code or configuration.

---

## IMDSv1: No Authentication Required

IMDSv1 answers any local HTTP `GET` request:

```
GET http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>
```

No token. No session. No proof that the caller is an authorized process. If any software on the instance — or any software that can make outbound HTTP requests on the instance's behalf — can reach `169.254.169.254`, it can retrieve the instance role's full credentials.

### The SSRF Attack Path

Server-Side Request Forgery (SSRF) is a vulnerability where an attacker tricks a server into making HTTP requests to an internal address. Against IMDSv1, the attack is three steps:

```
Attacker                     Vulnerable App               IMDS
   │                               │                        │
   │  POST /fetch?url=             │                        │
   │  http://169.254.169.254/      │                        │
   │  latest/meta-data/iam/        │                        │
   │  security-credentials/role    │                        │
   │──────────────────────────────▶│                        │
   │                               │  GET /latest/meta-data │
   │                               │  /iam/security-        │
   │                               │  credentials/role      │
   │                               │───────────────────────▶│
   │                               │                        │
   │                               │◀───────────────────────│
   │                               │  AccessKeyId           │
   │                               │  SecretAccessKey       │
   │                               │  Token (session)       │
   │◀──────────────────────────────│                        │
   │  Full IAM credentials         │                        │
```

The attacker now holds valid, short-lived AWS credentials scoped to the instance role — with no foothold on the host itself.

### What Is Exposed

| Metadata Path | Contents |
|---|---|
| `/iam/security-credentials/<role>` | `AccessKeyId`, `SecretAccessKey`, `Token` — valid for 6 hours |
| `/user-data` | Bootstrap scripts, which often contain secrets, database URLs, or API tokens |
| `/network/interfaces/` | VPC IDs, subnet IDs, private IPs — useful for lateral movement planning |
| `/public-keys/` | SSH public key names |
| `/placement/` | Region, AZ, partition — useful for targeted API calls |

### Real Incident: Capital One (2019)

A misconfigured WAF allowed an SSRF request to reach the EC2 metadata endpoint of a running instance. The attacker retrieved the attached IAM role's credentials, then used them to list and download S3 objects across over 100 million customer records. The underlying vulnerability was IMDSv1 — the metadata service answered without any authentication. See the [AWS post-incident summary](https://aws.amazon.com/blogs/security/defense-in-depth-open-firewalls-reverse-proxies-and-ssrf-vulnerabilities-aws/).

---

## IMDSv2: Session-Oriented, SSRF-Resistant

IMDSv2 requires a two-step protocol. Before reading any metadata, the caller must first obtain a session token via a `PUT` request:

```bash
# Step 1: acquire a session token (TTL: 21600 seconds = 6 hours)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Step 2: use the token in all subsequent metadata requests
curl -s "http://169.254.169.254/latest/meta-data/iam/security-credentials/" \
  -H "X-aws-ec2-metadata-token: $TOKEN"
```

### Why SSRF Cannot Abuse IMDSv2

The `PUT` verb breaks SSRF in most web frameworks:

- Standard SSRF primitives (URL fetch helpers, curl, image loaders, webhooks) typically only issue `GET` requests. A `PUT` with a custom header is not a cross-site-capable request.
- Even if an attacker can force a server to issue `PUT`, the `X-aws-ec2-metadata-token-ttl-seconds` header must be present. Browsers and most HTTP clients strip custom headers on cross-origin requests.
- The token is bound to the session and expires. A leaked token is not re-usable across sessions.

Additionally, IMDSv2 respects the **hop limit** (`http_put_response_hop_limit`). Setting this to `1` (the default) means the token request cannot survive a network hop — so a request that passes through a proxy or container boundary will never receive a valid token.

### The One Setting That Enforces It

```hcl
metadata_options {
  http_tokens = "required"   # enforces IMDSv2; rejects all IMDSv1 requests
}
```

When `http_tokens = "optional"` (the AWS default), both IMDSv1 and IMDSv2 are accepted. Setting it to `"required"` rejects unauthenticated `GET` requests with `HTTP 401`, eliminating the SSRF attack path entirely.

---

## Why the AWS Default Is Still Insecure

AWS set `http_tokens = "optional"` as the default for backwards compatibility — workloads that use the AWS SDKs on older versions may not support IMDSv2 automatically. As of IMDSv2 support landing in all AWS SDK versions (2021+), there is no valid reason to leave `http_tokens = "optional"` in new infrastructure. The risk surface it leaves open is severe, and the fix is a one-line change.

The OPA policy in this repository ([policies/require_imdsv2.rego](../policies/require_imdsv2.rego)) enforces `http_tokens = "required"` at Terraform plan time, blocking any `aws_instance` resource that does not explicitly opt in to IMDSv2.
