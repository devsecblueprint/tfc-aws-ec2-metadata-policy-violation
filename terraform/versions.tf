terraform {
  required_version = "1.15.5"

  cloud {

    organization = "devsecblueprint"

    workspaces {
      name = "tfc-aws-ec2-metadata-policy-violation"
    }
  }
}
