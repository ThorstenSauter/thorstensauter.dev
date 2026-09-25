# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal website for thorstensauter.dev. Right now the site is only a redirect to the GitHub profile. `src/staticwebapp.config.json` sends every path there with a 301 (the same pattern as the `westphalia-kn.de` repo). `src/index.html` is a meta-refresh fallback, and the Static Web Apps deploy action requires it, so don't delete it. The plan is to grow it into a full personal website. There is no app build step: `src/` is uploaded as-is to Azure Static Web Apps (`skip_app_build: true`).

## Layout

- `src/`: static site content, deployed as-is.
- `infra/production/`: Terraform root module for the single (production) environment.
- `infra/.tflint.hcl`: TFLint config with the azurerm ruleset.
- `.github/workflows/`: CI/CD. Renovate (`.github/renovate.json`, which extends `ThorstenSauter/renovate-config`) opens most commits as dependency bumps for Terraform providers, TFLint plugins, and pinned action SHAs.

## Infrastructure architecture

`infra/production/main.tf` provisions:
- An Azure resource group and an Azure Static Web App (Free SKU by default). `repository_branch` and `repository_url` are in `ignore_changes` because deployments come from GitHub Actions, not a linked repo.
- Two custom domains on the Static Web App:
  - The apex `thorstensauter.dev` is validated with `dns-txt-token`.
  - `www.thorstensauter.dev` is validated with `cname-delegation`.
- Cloudflare DNS records in the existing `thorstensauter.dev` zone (looked up via a data source):
  - The TXT validation record.
  - A CNAME at the apex, which Cloudflare flattens.
  - A CNAME for `www`.
  - All records use `proxied = false`.
- A `time_sleep` of 120s, so the `www` cname-delegation validation runs only after DNS has propagated. Keep this ordering when you touch domain resources.

The `deployment_token` output is the Static Web App's API key. CI reads it with `terraform output -raw deployment_token` to deploy the site, so do not remove or rename it.

Providers are `azurerm ~> 5.6`, `cloudflare ~> 5.25`, and `time`, and Terraform must be `>= 1.9`. The state backend is `azurerm` with an empty block. Backend settings come from CI variables: resource group, storage account, container, and state file. Locally they would go in a `*.conf` backend config file, which `infra/.gitignore` ignores. Auth uses Azure AD/OIDC (`ARM_USE_OIDC`, `storage_use_azuread`) plus `CLOUDFLARE_API_TOKEN`.

## CI/CD flow

- **PR to main** runs two workflows:
  - `terraform-plan.yml`: validate plus a production plan.
  - `build.yml`: runs a refresh-only apply to read the token, then uploads `src/` to a Static Web Apps preview environment. When the PR closes, it tears down the preview environment.
- **Release published** (or manual dispatch) runs `deploy-production.yml`: a full `terraform apply`, then uploads `src/` to production.
- Every job that touches the production state shares the `terraform-state-production` concurrency group with `cancel-in-progress: false`. `deploy-production.yml` sets the group at the workflow level; the other workflows set it per job. Add the group to any new job that runs Terraform against production.
- The refresh-only apply before `terraform output` is intentional: it pulls the current deployment token from Azure in case it was rotated.
- Terraform steps use the composite actions from `ThorstenSauter/terraform-actions` (init, validate, plan, apply). Actions are pinned by commit SHA with a version comment.

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
