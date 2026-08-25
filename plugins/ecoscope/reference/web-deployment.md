# Web deployment (compose repo)

How a tagged catalog workflow release reaches the ecoscope-web environments (dev / preview / stage
/ prod). The CI gates that produce the tag are in [ci.md](ci.md).

## Contents
- Scope — which workflows, and why
- Requirements on the workflow repo
- Dev and preview deploys
- WIP-tag flow for workflow changes in QA
- Naming trap: `stage` vs `staging`

## Scope — which workflows, and why

Workflow repos' own CI deploys nothing. The org's `compose` repo pins each deployable as a git
submodule (workflow repos under `ecoscope-platform-workflows-releases/<template>` — their
**committed compiled package** is what gets built into an image), with one reusable build-deploy
pipeline per environment (`main.yaml`/`stage.yaml`/`prod.yaml`). **This path exists only for
workflows in the workflow template catalog** — i.e. the ones vendored as compose submodules; custom
workflows are not deployed through compose. And it is **only needed for manual web QA** (a human
exercising the workflow in the ecoscope-web app) — the desktop app imports a
workflow from its release tag directly, no compose deploy needed.

## Requirements on the workflow repo

- **Deployment needs version tags on the workflow repo.** The per-template ref inputs on the
  dev-deploy dispatch must be a version tag (not a branch or SHA), and post-deploy the tag is read
  back via `git submodule status` (git-describe) and registered as the template's service-URL
  version — which must be ≥ the version already registered for that env.
- Tag shapes: `vMAJ.MIN.PATCH` deploys to dev/stage/prod (and preview);
  `vMAJ.MIN.PATCH.N` is a **pre-release tag, accepted by preview environments only** and rejected
  by dev/stage/prod.

## Dev and preview deploys

Dev deploys are dispatched (**Create PR to deploy dev** = `dispatch-create-dev-deploy-pr.yaml`)
against refs; the bot PR to compose `main` carries the `automerge` label and merges itself.
Ticking **Deploy Preview Environment** instead labels the PR for an isolated per-PR stack at
`https://app-preview-<pr>.dev.ecoscope.io` (dev login, seeded from a dev DB snapshot; torn down
when the PR is closed). Promotion `main`→`stage`→`prod` is always a human PR — automerge is
disabled for those bases.

## WIP-tag flow for workflow changes in QA

1. On a branch in the release repo, recompile and tag `vMAJ.MIN.PATCH.0` (the intended next
   version + `.0`).
2. Deploy it to a preview env (previous section).
3. Fixes during QA: bump the fourth segment (`.0`→`.1`) and push the submodule bump to the open
   deploy PR. The registered version is unchanged, so the cached params schema / image URI are
   **not** refreshed — bump VERSION.yaml and cut a fresh `.0` tag if you need that. Never lower
   VERSION.yaml mid-QA.
4. When QA passes: delete the WIP tags, set VERSION.yaml to the real version, PR the branch to
   `main`, and **close** (don't merge) the preview deploy PR.

## Naming trap: `stage` vs `staging`

The compose `stage` branch/environment is unrelated to the `staging` branch in catalog workflow
repos. Workflow-repo `staging` gates what enters a workflow release; compose `stage` gates which
platform release reaches the stage environment.
