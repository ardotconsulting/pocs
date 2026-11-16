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
    #   data_path   = "/data" # optional: kept across redeploys (a Coolify volume)
    # }
    "uptime-kuma" = {
      description = "Proof of concept for Building a Self-Hosted Monitoring Stack with Uptime Kuma"
      port        = "3001"
      data_path   = "/app/data" # admin, monitors and status page survive redeploys
    }

    "flame-dashboard" = {
      description = "Proof of concept for Self-Hosting Flame Dashboard: Centralize Access to All Your Self-Hosted Tools"
      port        = "5005"
      data_path   = "/app/data" # apps, bookmarks, themes and settings survive redeploys
    }
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

# Not deployed on create: the repo starts empty. Every push to main deploys it
# (the webhook below).
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

  # Checks GitHub's signature on the webhook below. Our token can't read it
  # back, so the provider keeps the value from state.
  manual_webhook_secret_github = random_password.poc_webhook[each.key].result

  # Same as the personal repo: the API doesn't return these on read.
  lifecycle {
    ignore_changes = [
      project_uuid,
      server_uuid,
      manual_webhook_secret_bitbucket,
      manual_webhook_secret_gitea,
      manual_webhook_secret_gitlab,
    ]
  }
}

# Auto-deploy: GitHub calls Coolify's manual webhook on every push, and Coolify
# deploys the app whose repo and branch match.
resource "random_password" "poc_webhook" {
  for_each = local.pocs

  length  = 40
  special = false
}

resource "github_repository_webhook" "poc_deploy" {
  for_each = local.pocs

  repository = github_repository.poc[each.key].name
  events     = ["push"]
  active     = true

  configuration {
    url          = "https://coolify.ardotconsulting.com/webhooks/source/github/events/manual"
    content_type = "json"
    secret       = random_password.poc_webhook[each.key].result
    insecure_ssl = false
  }
}

# Persistent storage for entries with data_path: a Coolify volume mounted there,
# so redeploys keep the data. Attaching it takes effect on the next deploy.
resource "coolify_storage" "poc_data" {
  for_each = { for k, v in local.pocs : k => v if try(v.data_path, null) != null }

  application_uuid = coolify_application.poc[each.key].uuid
  name             = "data"
  mount_path       = each.value.data_path
}
