package terraform.policies.require_imdsv2

import input.plan as plan
import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Actions that create or modify infrastructure
applicable_actions := {"create", "update"}

# EC2 instance has IMDSv1 enabled, or does not explicitly require IMDSv2.
deny contains msg if {
    some resource in plan.resource_changes
    resource.type == "aws_instance"

    some action in resource.change.actions
    action in applicable_actions

    some opts in resource.change.after.metadata_options
    opts.http_tokens != "required"

    msg := sprintf(
        "EC2 instance '%s' must enforce IMDSv2. http_tokens must be \"required\", found: \"%s\".",
        [resource.address, opts.http_tokens],
    )
}

# EC2 instance has no metadata_options block at all.
deny contains msg if {
    some resource in plan.resource_changes
    resource.type == "aws_instance"

    some action in resource.change.actions
    action in applicable_actions

    not resource.change.after.metadata_options

    msg := sprintf(
        "EC2 instance '%s' does not define metadata_options. http_tokens must be explicitly set to \"required\".",
        [resource.address],
    )
}