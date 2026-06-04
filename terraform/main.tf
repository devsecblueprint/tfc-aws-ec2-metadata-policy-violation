provider "aws" {
  region = var.aws_region
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "demo" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  # NONCOMPLIANT: http_tokens = "optional" permits IMDSv1 requests.
  # The OPA policy will hard-deny this plan.
  # Change http_tokens to "required" to enforce IMDSv2 and pass the policy.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "imdsv2-demo"
    Environment = "security-demo"
  }
}

output "instance_id" {
  description = "ID of the demo EC2 instance."
  value       = aws_instance.demo.id
}
