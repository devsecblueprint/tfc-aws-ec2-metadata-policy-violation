package terraform.policies.require_imdsv2_test

import data.terraform.policies.require_imdsv2.deny
import future.keywords.if
import future.keywords.in

# ── Helpers ──────────────────────────────────────────────────────────────────

# Build a resource_changes entry for an aws_instance with metadata_options set.
mock_instance(address, actions, http_tokens) := {
    "address": address,
    "type": "aws_instance",
    "change": {
        "actions": actions,
        "after": {"metadata_options": [{
            "http_endpoint": "enabled",
            "http_tokens": http_tokens,
            "http_put_response_hop_limit": 1,
        }]},
    },
}

# Build a resource_changes entry for an aws_instance with no metadata_options block.
mock_instance_no_metadata(address, actions) := {
    "address": address,
    "type": "aws_instance",
    "change": {
        "actions": actions,
        "after": {},
    },
}

# ── Deny cases ───────────────────────────────────────────────────────────────

test_deny_create_with_optional if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.demo", ["create"], "optional"),
    ]}
    count(violations) == 1
}

test_deny_update_with_optional if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.demo", ["update"], "optional"),
    ]}
    count(violations) == 1
}

test_deny_when_metadata_options_absent if {
    violations := deny with input as {"resource_changes": [
        mock_instance_no_metadata("aws_instance.demo", ["create"]),
    ]}
    count(violations) == 1
}

test_deny_multiple_noncompliant_instances if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.web", ["create"], "optional"),
        mock_instance("aws_instance.api", ["create"], "optional"),
    ]}
    count(violations) == 2
}

# ── Pass cases ───────────────────────────────────────────────────────────────

test_pass_create_with_required if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.demo", ["create"], "required"),
    ]}
    count(violations) == 0
}

test_pass_update_with_required if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.demo", ["update"], "required"),
    ]}
    count(violations) == 0
}

# Delete actions must never trigger a violation.
test_no_deny_on_delete if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.demo", ["delete"], "optional"),
    ]}
    count(violations) == 0
}

# No-op actions (drift check runs) must not trigger a violation.
test_no_deny_on_no_op if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.demo", ["no-op"], "optional"),
    ]}
    count(violations) == 0
}

# Non-EC2 resource types are out of scope.
test_no_deny_for_non_ec2_resource if {
    violations := deny with input as {"resource_changes": [{
        "address": "aws_s3_bucket.data",
        "type": "aws_s3_bucket",
        "change": {
            "actions": ["create"],
            "after": {},
        },
    }]}
    count(violations) == 0
}

# A compliant instance alongside a noncompliant one: only the bad one is flagged.
test_mixed_compliance if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.good", ["create"], "required"),
        mock_instance("aws_instance.bad", ["create"], "optional"),
    ]}
    count(violations) == 1
    some msg in violations
    contains(msg, "aws_instance.bad")
}

# ── Violation message content ─────────────────────────────────────────────────

test_message_contains_resource_address if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.my_server", ["create"], "optional"),
    ]}
    some msg in violations
    contains(msg, "aws_instance.my_server")
}

test_message_contains_found_value if {
    violations := deny with input as {"resource_changes": [
        mock_instance("aws_instance.demo", ["create"], "optional"),
    ]}
    some msg in violations
    contains(msg, "optional")
}

test_absent_metadata_message_contains_address if {
    violations := deny with input as {"resource_changes": [
        mock_instance_no_metadata("aws_instance.missing_meta", ["create"]),
    ]}
    some msg in violations
    contains(msg, "aws_instance.missing_meta")
}
