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
2. Wait for Ryan to apply it. That creates the repo, the Coolify project and
   the app (not yet deployed).
3. Push the app, a `Dockerfile` and a `README.md` linking to the post to
   `poc-<slug>`, then deploy with the Coolify API:
   `POST https://coolify.ardotconsulting.com/api/v1/deploy?uuid=<app uuid>`.
4. Link the POC from the post with a PR on `ardotconsulting-site`.

Only proofs of concept that run as one container from a `Dockerfile` fit here.
Anything that needs a database, another domain or other infrastructure: open
an issue in this repo for Ryan instead.

## Applying (Ryan)

```fish
atofu plan    # in this directory; .env.op holds only COOLIFY_TOKEN
atofu apply
```

State is `pocs/terraform.tfstate` in the `ardotconsulting-tfstate` bucket. The
GitHub provider uses your `gh` login (ryancheley).
