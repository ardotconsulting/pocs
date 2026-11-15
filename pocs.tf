# Proofs of concept from blog posts. Each entry creates a public repo
# ardotconsulting/poc-<slug> (miloardot can push), a Coolify project and an app
# served at https://<slug>.poc.ardotconsulting.com. DNS is the *.poc wildcard in
# hetzner/dns.tf in ardotconsulting/infra. Agents add entries by PR; Ryan
# approves and applies.
locals {
  pocs = {
    # "invoice-ocr" = {
    #   description = "Proof of concept for <post title>"
    #   port        = "8000" # the port the app's Dockerfile listens on
    # }
  }
}

resource "github_repository" "poc" {
  for_each = local.pocs

  name                   = "poc-${each.key}"
  description            = each.value.description
  homepage_url           = "https://${each.key}.poc.ardotconsulting.com"
  visibility             = "public"
  auto_init              = true
  has_issues             = true
  delete_branch_on_merge = true
  archive_on_destroy     = true
}

resource "github_repository_collaborator" "poc_agents" {
  for_each = local.pocs

  repository = github_repository.poc[each.key].name
  username   = "miloardot"
  permission = "push"
}

resource "coolify_project" "poc" {
  for_each = local.pocs

  name        = "poc-${each.key}"
  description = each.value.description
}

# Not deployed on create: the repo starts empty. The agents deploy after pushing code.
resource "coolify_application" "poc" {
  for_each = local.pocs

  name             = "poc-${each.key}"
  project_uuid     = coolify_project.poc[each.key].uuid
  server_uuid      = local.server_uuid
  environment_name = "production"
  git_repository   = github_repository.poc[each.key].html_url
  git_branch       = "main"
  build_pack       = "dockerfile"
  ports_exposes    = each.value.port
  domains          = "https://${each.key}.poc.ardotconsulting.com"

  # Same as the personal repo: the API doesn't return these on read.
  lifecycle {
    ignore_changes = [
      project_uuid,
      server_uuid,
      manual_webhook_secret_bitbucket,
      manual_webhook_secret_gitea,
      manual_webhook_secret_github,
      manual_webhook_secret_gitlab,
    ]
  }
}
