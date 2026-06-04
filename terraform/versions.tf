terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Replace "your-org-name" with your Terraform Cloud organization name.
  cloud {
    organization = "your-org-name"

    workspaces {
      name = "ec2-imdsv2-demo"
    }
  }
}
