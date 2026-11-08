# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal website for thorstensauter.dev. Right now the site is only a redirect to the GitHub profile. `src/staticwebapp.config.json` sends every path there with a 301 (the same pattern as the `westphalia-kn.de` repo). `src/index.html` is a meta-refresh fallback, and the Static Web Apps deployment requires it, so don't delete it. The plan is to grow it into a full personal website. There is no app build step: `src/` is uploaded as-is to Azure Static Web Apps with the Static Web Apps CLI pinned in `tools/swa-cli`.

## Layout

- `src/`: static site content, deployed as-is.
- `infra/production/`: Terraform root module for the single (production) environment.
- `infra/.tflint.hcl`: TFLint config with the azurerm ruleset.
- `tools/swa-cli/`: the pinned Static Web Apps CLI (with its `package-lock.json`) that both workflows deploy with.
- `.github/workflows/`: CI/CD. Renovate (`.github/renovate.json`, which extends `ThorstenSauter/renovate-config`) opens most commits as dependency bumps for Terraform providers, TFLint plugins, the Static Web Apps CLI and action tags.

## Infrastructure architecture

`infra/production/main.tf` creates the resource group and calls the shared module [`ThorstenSauter/cloudflare-azure-static-web-app`](https://github.com/ThorstenSauter/cloudflare-azure-static-web-app) (pinned with `?ref=X.Y.Z`, bumped by Renovate). The module owns the Azure Static Web App (Free SKU by default, `repository_*` ignored because CI deploys the content), the Cloudflare DNS records (DNS-only, zone looked up by `cloudflare_zone_name`) and both custom domains: the apex with `dns-txt-token` validation and a CNAME Cloudflare flattens, and `www` with `cname-delegation` after a 120s propagation wait. Change domain or DNS behaviour in the module, not here. Resource names follow `<type>-${app_name}-${env}-${resource_id}`.

Don't rename the module call (`module.static_web_app`): Terraform would recreate the Static Web App and its custom domains. A rename needs a `moved` block.

The `deployment_token` output is the Static Web App's API key. CI reads it with `terraform output -raw deployment_token` to deploy the site, so don't remove or rename it.

Provider versions (`azurerm`, `cloudflare`, `time`) are pinned in `terraform.tf` and bumped by Renovate; the module only sets lower bounds.

## CI/CD flow

- **PR to main** runs two workflows:
  - `terraform-plan.yml`: validate plus a production plan, run in the `plan-production` environment with read-only credentials (a Reader managed identity and a Zone:Read/DNS:Read Cloudflare token). `production`, with write access, is restricted to `main` and release tags and used only by the deploy.
  - `build.yml`: uploads `src/` to a Static Web Apps preview environment named after the PR number (`swa deploy src --env <number>`) and comments its URL on the PR, using the deployment token stored as `AZURE_STATIC_WEB_APPS_API_TOKEN` in the `preview` GitHub environment (no Azure or Cloudflare credentials). When the PR closes, it tears down the preview environment. The CLI can't do that, so the job runs the CLI's `StaticSitesClient` binary itself the way the old `Azure/static-web-apps-deploy` action did (`StaticSitesClient close` with `INPUT_AZURE_STATIC_WEB_APPS_API_TOKEN`), so it reads the PR number from the GitHub event. In the CLI's own mode (`DEPLOYMENT_PROVIDER=SwaCli`) Azure rejects a close for missing the pull request ID. It gets the binary through the CLI's internal `getDeployClientPath()`, so check that step after a CLI major update. If the deployment token is rotated, update that secret.
- **Release published** (or manual dispatch) runs `deploy-production.yml`: a full `terraform apply`, then uploads `src/` to production.
- `deploy-production.yml` runs in the `terraform-state-production` concurrency group (workflow level, `cancel-in-progress: false`), so deploys run one at a time and are never cancelled. PR jobs (`terraform-plan.yml`) stay out of that group on purpose: a third queued job in a group cancels the pending one, which could drop a deployment. They wait on the state lock instead (`lock-timeout`, 10m in the `terraform-actions` steps), so pass `-lock-timeout` to any new raw Terraform command.
- Terraform steps use the composite actions from `ThorstenSauter/terraform-actions` (init, validate, plan, apply). Actions are referenced by full version tag and `.github/workflows/actions.lock` locks the commits; after changing a `uses:` line by hand, run `gh actions-lock` and commit the lockfile.

## Commands

Run these from `infra/production`:

```sh
terraform fmt -recursive
terraform init -backend-config=<local>.conf   # or: terraform init -backend=false  (for validate only)
terraform validate
tflint --init && tflint --config ../.tflint.hcl
terraform plan
```

The site has no tests or build. To preview it, open `src/index.html` directly.

## Conventions

- Files are UTF-8 without a BOM, with LF line endings, and end with a newline. Indent with 2 spaces, except HTML, which uses 4 (`.editorconfig`).
- Resource names follow `<type-abbrev>-${app_name}-${env}-${resource_id}` (for example `stapp-thorstensauter-website-prod-001`).
