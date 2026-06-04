package terraform.policies.require_imdsv2

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Actions that create or modify infrastructure (excludes deletes and no-ops)
applicable_actions := {"create", "update"}

# HARD DENY: EC2 instance has http_tokens explicitly set to "optional"
deny contains msg if {
    some resource in input.resource_changes
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

# HARD DENY: EC2 instance does not define metadata_options at all
deny contains msg if {
    some resource in input.resource_changes
    resource.type == "aws_instance"
    some action in resource.change.actions
    action in applicable_actions

    not resource.change.after.metadata_options

    msg := sprintf(
        "EC2 instance '%s' does not define metadata_options. http_tokens must be explicitly set to \"required\".",
        [resource.address],
    )
}
