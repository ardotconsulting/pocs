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
3. Push the app, a `Dockerfile` and a `README.md` linking to the post to
   `main` of `poc-<slug>`. **Every push to `main` deploys** (a webhook calls
   Coolify), so don't push code you don't want live. If a deploy needs
   retrying without a new commit, use the Coolify API:
   `POST https://coolify.ardotconsulting.com/api/v1/deploy?uuid=<app uuid>`.

   **If the app gives admin to its first visitor** (Uptime Kuma, for example),
   ask Ryan before the first push that makes it runnable, because that push
   deploys it; Ryan claims the admin right after. With `data_path` set, the
   admin survives later deploys, so you only ask once.
4. Link the POC from the post with a PR on `ardotconsulting-site`.

Every POC also gets a public tile on the
[Flame dashboard](https://flame-dashboard.poc.ardotconsulting.com), added when
it's created and removed when its entry goes (`flame-tile.sh`, run by
OpenTofu); nothing to do by hand.

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
(the `ardot-pocs-tofu` GitHub App). Repo variables: `POCS_APP_CLIENT_ID`,
`POCS_AWS_ROLE_ARN`. State is `pocs/terraform.tfstate` in the
`ardotconsulting-tfstate` bucket.

Locally (fallback), from this directory: `atofu plan` / `atofu apply`, with the
GitHub provider using your `gh` login.
