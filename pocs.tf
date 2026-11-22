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
    #   generated_secrets = ["PASSWORD"] # optional: random runtime env vars, see below
    #   flame_path  = "/status/demo" # optional: where the Flame tile points, if not /
    #   post_deploy = "sh /setup-admin.sh" # optional: runs in the container after each deploy
    #   display_name = "Invoice OCR" # optional: Flame tile and Uptime Kuma monitor name
    # }
    "uptime-kuma" = {
      description = "Proof of concept for Building a Self-Hosted Monitoring Stack with Uptime Kuma"
      port        = "3001"
      data_path   = "/app/data"    # admin, monitors and status page survive redeploys
      flame_path  = "/status/kuma" # the public status page; / is the admin login
    }

    "flame-dashboard" = {
      description = "Proof of concept for Self-Hosting Flame Dashboard: Centralize Access to All Your Self-Hosted Tools"
      port        = "5005"
      data_path   = "/app/data" # apps, bookmarks, themes and settings survive redeploys
      # Flame's login; without it anyone can edit the dashboard.
      generated_secrets = ["PASSWORD"]
    }

    "ghost" = {
      description = "Proof of concept for Self-Hosting Ghost: Replace Medium and Substack With Your Own Publishing Platform"
      port        = "2368"
      data_path   = "/var/lib/ghost/content" # posts, images and settings survive redeploys
    }

    "nocodb" = {
      display_name = "NocoDB"
      description  = "Proof of concept for Self-Hosting NocoDB: Replace Airtable with Your Own No-Code Database Platform"
      port         = "8080"
      data_path    = "/usr/app/data" # bases, tables and admin account survive redeploys
    }

    "n8n" = {
      display_name      = "n8n"
      description       = "Proof of concept for How to Build Your First AI Automation Workflow with n8n"
      port              = "5678"
      data_path         = "/home/node/.n8n"      # workflows, credentials and owner account survive redeploys
      generated_secrets = ["N8N_ENCRYPTION_KEY"] # encrypts stored credentials; OpenTofu generates it
    }

    "roi-calculator" = {
      display_name = "ROI Calculator"
      description  = "Proof of concept for The Real ROI of AI Automation: How to Measure It"
      port         = "80"
    }

    "automation-audit" = {
      display_name = "Automation Audit"
      description  = "Proof of concept for How to Audit Your Business Processes for Automation Opportunities"
      port         = "80"
    }

    "directus" = {
      display_name      = "Directus"
      description       = "Proof of concept for Self-Hosting Directus: Build Custom Business Apps Without Code"
      port              = "8055"
      data_path         = "/directus/data"
      generated_secrets = ["KEY", "SECRET", "ADMIN_PASSWORD"]
      post_deploy       = "sh /setup-admin.sh"
    }

    "metabase" = {
      display_name      = "Metabase"
      description       = "Proof of concept for Self-Hosting Metabase: Open-Source Business Analytics Without SaaS"
      port              = "3000"
      data_path         = "/metabase-data"
      generated_secrets = ["ADMIN_PASSWORD"]
      post_deploy       = "sh /setup-admin.sh"
    }

    "document-extraction" = {
      display_name = "Document Extraction"
      description  = "Proof of concept for AI-Powered Document Extraction with Tesseract and Ollama"
      port         = "8000"
    }

    "nextcloud" = {
      description       = "Proof of concept for Self-Hosting Nextcloud: Replace Google Workspace with Your Own File Sync and Collaboration Platform"
      port              = "80"
      data_path         = "/var/www/html"
      generated_secrets = ["NEXTCLOUD_ADMIN_PASSWORD"]
    }
    "vaultwarden" = {
      description       = "Proof of concept for Self-Hosting Vaultwarden: Replace LastPass with Your Own Password Manager"
      port              = "80"
      data_path         = "/data"
      generated_secrets = ["ADMIN_TOKEN"]
    }

    "mattermost" = {
      display_name      = "Mattermost"
      description       = "Proof of concept for Self-Hosting Mattermost: Replace Slack with Your Own Team Chat Platform"
      port              = "8065"
      data_path         = "/mattermost/data"
      generated_secrets = ["ADMIN_PASSWORD"]
      post_deploy       = "sh /setup-admin.sh"
    }

    "offboarding-checklist" = {
      display_name = "Offboarding Checklist"
      description  = "Proof of concept for Automating Employee Offboarding with Open Source Tools"
      port         = "80"
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

  name = "poc-${each.key}"
  # Coolify only accepts letters, numbers, spaces and - _ . , ! ? ( ) ' " + = * / @ &
  # in descriptions; post titles often have a colon. GitHub keeps the original.
  description = trimspace(replace(each.value.description, "/[^\\p{L}\\p{N} _.,!?()'\"+=*/@&-]+/", " "))
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
      # Set by terraform_data.post_deploy: the API never returns it, so setting
      # it here fails every create with "inconsistent result after apply".
      post_deployment_command,
    ]
  }
}

# Runs inside the container after each deploy. Apps that give admin to their
# first visitor use it to claim the admin through their own setup API with a
# generated ADMIN_PASSWORD, seconds after the deploy (scripts must be safe to
# re-run). See the README. Set through the API because Coolify hides the field
# on read (see coolify_application.poc). COOLIFY_TOKEN comes from the environment.
resource "terraform_data" "post_deploy" {
  for_each = { for k, v in local.pocs : k => v.post_deploy if try(v.post_deploy, null) != null }

  triggers_replace = [coolify_application.poc[each.key].uuid, each.value]

  provisioner "local-exec" {
    command = <<-EOT
      jq -n --arg c "$POST_DEPLOY" '{post_deployment_command: $c}' |
        curl -sf -m 20 -o /dev/null -X PATCH -H "Authorization: Bearer $COOLIFY_TOKEN" \
          -H "Content-Type: application/json" --data @- "$APP_URL"
    EOT
    environment = {
      POST_DEPLOY = each.value
      APP_URL     = "https://coolify.ardotconsulting.com/api/v1/applications/${coolify_application.poc[each.key].uuid}"
    }
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

  # Created after the smoke workflow is committed, so that commit doesn't
  # trigger a deploy of a repo that has no app yet.
  depends_on = [github_repository_file.poc_smoke]
}

# Persistent storage for entries with data_path: a Coolify volume mounted there,
# so redeploys keep the data. Attaching it takes effect on the next deploy.
resource "coolify_storage" "poc_data" {
  for_each = { for k, v in local.pocs : k => v if try(v.data_path, null) != null }

  application_uuid = coolify_application.poc[each.key].uuid
  name             = "data"
  mount_path       = each.value.data_path
}

# Generated secrets for entries with generated_secrets: OpenTofu makes a random
# value for each name and sets it on the Coolify app as a runtime-only
# environment variable, so apps that need a password never depend on a
# hand-set value. The value lives only in the private state and in Coolify;
# read it in the app's Environment Variables in Coolify.
locals {
  poc_secrets = {
    for pair in flatten([
      for k, v in local.pocs : [for name in try(v.generated_secrets, []) : { poc = k, name = name }]
    ]) : "${pair.poc}/${pair.name}" => pair
  }
}

resource "random_password" "poc_secret" {
  for_each = local.poc_secrets

  length  = 32
  special = false # safe in any app's config parser
}

resource "coolify_environment_variable" "poc_secret" {
  for_each = local.poc_secrets

  application_uuid = coolify_application.poc[each.value.poc].uuid
  key              = each.value.name
  value            = random_password.poc_secret[each.key].result
  is_build         = false # never baked into the image
  is_runtime       = true
  is_literal       = true
  comment          = "Generated by OpenTofu (ardotconsulting/pocs)"
}

# Flame tiles: every POC (except Flame itself) gets a public tile on the Flame
# dashboard, added when the POC is created and removed when its entry goes.
# OpenTofu has no Flame provider, so flame-tile.sh calls Flame's API, signing
# in with Flame's generated PASSWORD. Tiles are matched by name, so re-runs
# update instead of duplicating. Tiles added by hand in Flame aren't touched.
locals {
  flame_url = "https://flame-dashboard.poc.ardotconsulting.com"
  flame_tiles = contains(keys(local.pocs), "flame-dashboard") ? {
    for k, v in local.pocs : k => {
      name        = try(v.display_name, title(replace(k, "-", " ")))
      url         = "https://${k}.poc.ardotconsulting.com${try(v.flame_path, "")}"
      description = trimprefix(v.description, "Proof of concept for ")
    } if k != "flame-dashboard"
  } : {}
}

resource "terraform_data" "flame_tile" {
  for_each = local.flame_tiles

  # Destroy-time provisioners can only read self, so everything the removal
  # needs is kept here; the password is marked sensitive, so plans hide it.
  input = merge(each.value, {
    flame_url      = local.flame_url
    flame_password = sensitive(random_password.poc_secret["flame-dashboard/PASSWORD"].result)
  })
  triggers_replace = each.value

  provisioner "local-exec" {
    command = "${path.module}/flame-tile.sh add"
    environment = {
      FLAME_URL        = self.input.flame_url
      FLAME_PASSWORD   = self.input.flame_password
      TILE_NAME        = self.input.name
      TILE_URL         = self.input.url
      TILE_DESCRIPTION = self.input.description
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/flame-tile.sh remove"
    environment = {
      FLAME_URL      = self.input.flame_url
      FLAME_PASSWORD = self.input.flame_password
      TILE_NAME      = self.input.name
    }
  }

  depends_on = [coolify_environment_variable.poc_secret]
}

# Smoke test and protected main in every POC repo: a merge into main deploys,
# so main only takes PRs whose smoke check passes (no human approval needed;
# the agents merge their own green PRs). Ryan and this stack's GitHub App can
# bypass. Writing the workflow pushes to main, which redeploys the app once.
locals {
  pocs_app_id = 5773899 # GitHub App ardot-pocs-tofu
}

resource "github_repository_file" "poc_smoke" {
  for_each = local.pocs

  repository = github_repository.poc[each.key].name
  branch     = "main"
  file       = ".github/workflows/smoke.yml"
  content = templatefile("${path.module}/smoke.yml.tftpl", {
    port        = each.value.port
    secrets     = try(each.value.generated_secrets, [])
    post_deploy = try(each.value.post_deploy, "")
  })
  commit_message      = "🧪 Smoke test (managed by ardotconsulting/pocs)"
  overwrite_on_create = true
}

resource "github_repository_ruleset" "poc_main" {
  for_each = local.pocs

  name        = "smoke-tested main"
  repository  = github_repository.poc[each.key].name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = 0 # GitHub stores 0 for OrganizationAdmin
    actor_type  = "OrganizationAdmin"
    bypass_mode = "always"
  }

  bypass_actors {
    actor_id    = local.pocs_app_id
    actor_type  = "Integration"
    bypass_mode = "always"
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      required_approving_review_count = 0
    }

    required_status_checks {
      required_check {
        context = "smoke"
      }
    }
  }

  depends_on = [github_repository_file.poc_smoke]
}

# Uptime Kuma monitors: every POC except Uptime Kuma itself gets an HTTP monitor
# named like its Flame tile, listed in the "Proofs of concept" group of the
# public status page, added when it's created and removed when its entry goes. kuma-monitor.py speaks Uptime Kuma's Socket.IO API (it has no REST API
# for monitors) as the admin; KUMA_USERNAME and KUMA_PASSWORD come from the
# CI environment, never from state. Monitors added by hand aren't touched.
locals {
  kuma_url         = "https://uptime-kuma.poc.ardotconsulting.com"
  kuma_status_page = "kuma" # public page; POCs go in its "Proofs of concept" group
  kuma_monitors = contains(keys(local.pocs), "uptime-kuma") ? {
    for k, v in local.pocs : k => {
      name        = try(v.display_name, title(replace(k, "-", " ")))
      url         = "https://${k}.poc.ardotconsulting.com${try(v.flame_path, "")}"
      status_page = local.kuma_status_page
    } if k != "uptime-kuma"
  } : {}
}

resource "terraform_data" "kuma_monitor" {
  for_each = local.kuma_monitors

  # Destroy-time provisioners can only read self, so the removal reads
  # everything it needs from here.
  input            = merge(each.value, { kuma_url = local.kuma_url })
  triggers_replace = each.value

  provisioner "local-exec" {
    command = "python3 ${path.module}/kuma-monitor.py add"
    environment = {
      KUMA_URL         = self.input.kuma_url
      KUMA_STATUS_PAGE = self.input.status_page
      MONITOR_NAME     = self.input.name
      MONITOR_URL      = self.input.url
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "python3 ${path.module}/kuma-monitor.py remove"
    environment = {
      KUMA_URL = self.input.kuma_url
      # Monitors created before status_page existed don't have it in state.
      KUMA_STATUS_PAGE = try(self.input.status_page, "kuma")
      MONITOR_NAME     = self.input.name
    }
  }
}
