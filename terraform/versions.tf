terraform {
  cloud {
    organization = "devsecblueprint"

    workspaces {
      name = "tfc-aws-ec2-metadata-policy-violation"
    }
  }
}
