terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "ardotconsulting-tfstate"
    key          = "pocs/terraform.tfstate"
    region       = "us-west-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    coolify = {
      source  = "coolify-terraform/coolify"
      version = "~> 0.1.29"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Token from COOLIFY_TOKEN (.env.op).
provider "coolify" {
  endpoint = "https://coolify.ardotconsulting.com"
}

# Uses the gh CLI login (ryancheley) when GITHUB_TOKEN isn't set.
provider "github" {
  owner = "ardotconsulting"
}

locals {
  # The lab Coolify's own server (h-ac-web-p-001), created by the Coolify install.
  # ponytail: hardcoded, it never changes; import it as a resource if its settings ever need managing.
  server_uuid = "jqrchg46aq85noy7ec9fsmx0"
}
