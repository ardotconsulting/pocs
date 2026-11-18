# pocs

Proofs of concept from the [ardotconsulting blog](https://www.ardotconsulting.com/blog/),
deployed on the lab Coolify with OpenTofu.

Each entry in `local.pocs` in [`pocs.tf`](pocs.tf) creates:

| What | Name |
|------|------|
| GitHub repo (public; miloardot can push) | `ardotconsulting/poc-<slug>` |
| Coolify project and app (Dockerfile build) | `poc-<slug>` |
| URL | `https://<slug>.poc.ardotconsulting.com` |

DNS is already in place: `*.poc.ardotconsulting.com` points at the lab server,
and Coolify gets each certificate itself.

## Adding a proof of concept (agents)

1. Branch from `main` in this repo, add an entry to `local.pocs`, and open a PR:

   ```hcl
   "invoice-ocr" = {
     description = "Proof of concept for <post title>"
     port        = "8000" # the port the app's Dockerfile listens on
     data_path   = "/data" # optional: where the app keeps data that must
                           # survive redeploys (a persistent volume)
   }
   ```

   Set `data_path` for any app with state (users, settings, an admin account),
   for example `/app/data` for Uptime Kuma. If the app's front page is a login
   rather than something visitors can use, set `flame_path` to the public page
   (Uptime Kuma: `/status/kuma`) so its Flame tile points there.

   If the app needs a password or other secret as an environment variable
   (Flame's `PASSWORD`, for example), add `generated_secrets = ["PASSWORD"]`:
   OpenTofu generates a random value and sets it on the app before its first
   deploy, so it's never live unprotected and nobody handles the value. Ryan
   reads it in Coolify. Never put a secret value in the PR or the repo.

   Change nothing else in the PR. `main` is protected: Ryan reviews and merges.
   Don't worry about `tofu fmt`: CI fixes the formatting on your branch.
2. Wait for the apply. After Ryan merges, CI plans, Ryan approves the
   `production` deployment, and CI applies, creating the repo, the Coolify
   project and the app (not yet deployed). CI then comments
   `✅ Applied: ...` on your PR: watch for that comment instead of asking.
3. Put the app, a `Dockerfile` and a `README.md` linking to the post on a
   **branch** of `poc-<slug>` and open a PR there. Its **smoke** check builds the
   image, starts it, waits for it to answer on the entry's port, and runs
   `post_deploy` twice if set. When it passes, merge the PR yourself (no review
   needed); **the merge deploys it** (a webhook calls Coolify). `main` only takes
   PRs with a passing smoke check, so a broken build never goes live. If a deploy needs
   retrying without a new commit, use the Coolify API:
   `POST https://coolify.ardotconsulting.com/api/v1/deploy?uuid=<app uuid>`.

   **If the app gives admin to its first visitor** (Ghost, n8n, Metabase…),
   claim it automatically instead of waiting for Ryan:
   - Add `generated_secrets = ["ADMIN_PASSWORD"]` and
     `post_deploy = "sh /setup-admin.sh"` to the entry.
   - In the POC repo, add `setup-admin.sh` and copy it to `/setup-admin.sh` in
     the `Dockerfile`. It waits until the app answers, then claims the admin
     through the app's own setup API as `admin@ardotconsulting.com` with
     `$ADMIN_PASSWORD`, and does nothing if setup is already done. Use only tools
     the image has (`wget`, `curl` or `node`).
   - Coolify runs it inside the container after every deploy. Ryan reads the
     password in the app's Environment Variables in Coolify.
   Only if the app's setup can't be scripted (Uptime Kuma's runs over a
   websocket), ask Ryan on the `pocs` PR before the first push that makes it
   runnable, and wait for his `go`.
4. Link the POC from the post with a PR on `ardotconsulting-site`.

Every POC also gets a public tile on the
[Flame dashboard](https://flame-dashboard.poc.ardotconsulting.com), added when
it's created and removed when its entry goes (`flame-tile.sh`, run by
OpenTofu), and an HTTP monitor in
[Uptime Kuma](https://uptime-kuma.poc.ardotconsulting.com) (`kuma-monitor.py`),
listed on its [public status page](https://uptime-kuma.poc.ardotconsulting.com/status/kuma);
nothing to do by hand. Until the app is serving, the monitor is paused and off the
status page and the tile is hidden; `activate.yml` switches them on within 15
minutes of the first successful deploy. Both are named from the slug, or from `display_name` when
capitalising the slug gets it wrong (`n8n`, `NocoDB`).

Only proofs of concept that run as one container from a `Dockerfile` fit here.
Anything that needs a database, another domain or other infrastructure: open
an issue in this repo for Ryan instead.

## Applying (Ryan)

CI does it ([`.github/workflows/tofu.yml`](.github/workflows/tofu.yml)):

- **PRs:** `tofu fmt` and `validate` only, with no secrets.
- **Merge to `main`:** the `plan` job writes the plan to the run summary. If
  the plan destroys nothing, the `apply` job applies it straight away (the
  `apply` environment has no reviewers). If it destroys anything, including a
  replacement, it waits for Ryan to approve the `production` deployment. Either
  way it comments `✅ Applied` on the PR.

Secrets live only in the `plan`, `apply` and `production` environments, which
only `main` can use: `COOLIFY_TOKEN` (`coolify-lab-tofu`) and `POCS_APP_PRIVATE_KEY`
(the `ardot-pocs-tofu` GitHub App), `KUMA_USERNAME` and `KUMA_PASSWORD`
(the Uptime Kuma admin, `poc-uptime-kuma-admin`). `activate.yml` also uses
`FLAME_PASSWORD` (`poc-flame-dashboard-admin`), in `apply` only. Repo variables: `POCS_APP_CLIENT_ID`,
`POCS_AWS_ROLE_ARN`. State is `pocs/terraform.tfstate` in the
`ardotconsulting-tfstate` bucket.

Locally (fallback), from this directory: `atofu plan` / `atofu apply`, with the
GitHub provider using your `gh` login.
