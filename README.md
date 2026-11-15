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
   }
   ```

   Change nothing else in the PR. `main` is protected: Ryan reviews and merges.
2. Wait for the apply. After Ryan merges, CI plans, Ryan approves the
   `production` deployment, and CI applies, creating the repo, the Coolify
   project and the app (not yet deployed). CI then comments
   `✅ Applied: ...` on your PR: watch for that comment instead of asking.
3. Push the app, a `Dockerfile` and a `README.md` linking to the post to
   `poc-<slug>`, then deploy with the Coolify API:
   `POST https://coolify.ardotconsulting.com/api/v1/deploy?uuid=<app uuid>`.
4. Link the POC from the post with a PR on `ardotconsulting-site`.

Only proofs of concept that run as one container from a `Dockerfile` fit here.
Anything that needs a database, another domain or other infrastructure: open
an issue in this repo for Ryan instead.

## Applying (Ryan)

CI does it ([`.github/workflows/tofu.yml`](.github/workflows/tofu.yml)):

- **PRs:** `tofu fmt` and `validate` only, with no secrets.
- **Merge to `main`:** the `plan` job writes the plan to the run summary; read
  it, then approve the `production` deployment and the `apply` job applies and
  comments on the PR.

Secrets live only in the `plan` and `production` environments, which only
`main` can use: `COOLIFY_TOKEN` (`coolify-lab-tofu`) and `POCS_APP_PRIVATE_KEY`
(the `ardot-pocs-tofu` GitHub App). Repo variables: `POCS_APP_CLIENT_ID`,
`POCS_AWS_ROLE_ARN`. State is `pocs/terraform.tfstate` in the
`ardotconsulting-tfstate` bucket.

Locally (fallback), from this directory: `atofu plan` / `atofu apply`, with the
GitHub provider using your `gh` login.
