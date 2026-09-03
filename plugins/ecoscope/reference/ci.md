# Workflow repo CI and deployment

What CI actually checks in a workflow repo, where each gate lives, how merges to `main` become
release tags, and how a tagged catalog release reaches the web environments. Safety rules (never
merge without go-ahead, etc.) are in [process-rules.md](process-rules.md).

## Contents
- The two CI families
- The wt-family gates, one by one
- Release tagging and legacy tags
- Repo-specific variation
- Web deployment (compose): scope, requirements, dev/preview deploys, WIP-tag flow, `stage` vs `staging`

## The two CI families

**wt family** (current) — `test.yml` orchestrating reusable `_discover.yml` + `_recompile.yml`;
optionally `guard-main-prs.yml`, `promote-staging.yml`, `tag.yml` on published repos.

**Legacy catalog family** — `ci.yml` + `tag.yml`, pytest via pixi tasks, a docker job, a
label-gated snapshot-update job; **no recompile gate, no version gate**. Recognize it by: no
`dev/`, no outer `pixi.toml`, a committed `__results_snapshots__/` tree. Repos mid-migration can
carry **both** families.

## The wt-family gates, one by one

- **`_discover.yml`** greps `^id:` from spec.yaml to find the workflow.
- **`_recompile.yml`** — pinned pixi via setup-pixi, recompiles the way the repo's script/inline
  step says (this is the authoritative record of `--variant` for this repo —
  [compile.md](compile.md)), then:

  ```bash
  git diff --exit-code -- "${GENERATED_DIR}" \
    ":(exclude)${GENERATED_DIR}/pixi.lock" ":(exclude)${GENERATED_DIR}/README.md" \
    ":(exclude)${GENERATED_DIR}/VERSION.yaml" ":(exclude)${GENERATED_DIR}/graph.png" \
    || { echo "::error::Generated files differ from committed files"; exit 1; }
  ```

  followed by a step asserting those four excluded files still exist. **`_recompile.yml` does NOT
  compare VERSION** (it explicitly excludes `VERSION.yaml` from its diff) — the version gate lives
  in `test.yml`.
- **`test.yml` → validate-spec**: rejects wildcard `version: "*"` and `channel: file://` —
  those are its only requirement greps; **`path:`/`editable:` requirements slip past it** and
  fail later, confusingly, in `_recompile.yml`'s compile step (the runner has no local path)
  and the 3-OS solve. It also requires `test-cases.yaml` with ≥1 case, and
  enforces the **version gate** — numeric compare of the inner `VERSION.yaml` against
  `git show origin/main:<version-path>`: **must be strictly greater than `origin/main`, even when
  the PR targets `staging`**.
- **`test.yml` → test-workflows**: 3-OS matrix (ubuntu/macos/windows, fail-fast off), connection
  secrets injected ([connections.md](connections.md)), runs the repo's test script with `--all`
  — `dev/run-test-cases.sh` in most repos, `dev/pytest-cli.sh <workflow_id>` in some (same
  harness shape driving the generated CLI, but it runs `pixi update` on the inner manifest
  first unless `--skip-setup`).
  Windows in the matrix means the **outer `pixi.toml` platforms must include `win-64`** (the
  scaffold emits only linux-64/osx-arm64 → setup-pixi fails `unsupported-platform`); after adding
  it, re-lock and **commit the outer `pixi.lock`** — it is tracked in these repos.
- **`guard-main-prs.yml`**: reads `tool.wt.published` from the **outer `pixi.toml`** (these repos
  have no root pyproject); if true, a PR to `main` must come from `staging` or `patch-*`.
- **`promote-staging.yml`**: manual dispatch; builds the staging→main promotion PR from the
  commit log.

## Release tagging and legacy tags

`tag.yml` (where present): on PRs to `main`/`patch-*` it builds `v$MAJ.$MIN.$PATCH` from
VERSION.yaml, asserts the tag doesn't already exist, and on merge tags + creates the GitHub
release. Consequences:

- **Every PR to main in such a repo must bump VERSION** or the tag job fails on the duplicate.
- **Bump VERSION.yaml by hand before each push**, and only by +1 on MAJ or MIN (reset the lower
  fields) — never jump several versions at once. VERSION.yaml is the only place the version is
  embedded (the generated pyproject uses dynamic versioning), so bumping it causes no recompile
  diff.
- **Renamed repos may carry legacy tags** from their old identity — VERSION must stay above the
  highest existing tag to keep tagging monotonic. Check `git tag --list 'v*'` before setting
  VERSION, and verify content by `git grep` **at the tag** (squash merges mean commit SHAs may not
  appear in `git tag --contains`).
- **Validate that every task library the workflow depends on is a published package** before
  tagging a release: each one must resolve from the conda channel (check the version exists in
  `https://repo.prefix.dev/ecoscope-workflows/noarch/repodata.json`), with no `path:`/`editable:`
  requirements or `channel: file://` left in spec.yaml. `validate-spec` rejects the wildcard and
  `file://` forms (`path:`/`editable:` die later, in the recompile step), and only a channel
  lookup proves the pinned version was actually published.
- Verify an upstream task-library release before depending on it: the symbol exists at the
  task-library tag (`git grep -l <fn> v<X.Y.Z>`) AND the conda build exists in the same repodata.

## Repo-specific variation

CI has drifted into multiple shapes (script-style vs inline recompile, different pinned
pixi/setup-pixi versions, gcp vs non-gcp, secrets for different connections, some repos carrying
catalog-only workflow files that should be deleted). **Always read the repo's own
`.github/workflows/` before opening a PR** and mirror what it does — the hub template is the
canonical source the files are vendored from ([repo-layout.md](repo-layout.md)), but the repo's
checked-in copy is what CI will actually run.

## Web deployment (compose)

How a tagged catalog workflow release reaches the ecoscope-web environments (dev / preview /
stage / prod).

### Scope — which workflows, and why

Workflow repos' own CI deploys nothing. The org's `compose` repo pins each deployable as a git
submodule (workflow repos under `ecoscope-platform-workflows-releases/<template>` — their
**committed compiled package** is what gets built into an image), with one reusable build-deploy
pipeline per environment (`main.yaml`/`stage.yaml`/`prod.yaml`). **This path exists only for
workflows in the workflow template catalog** — i.e. the ones vendored as compose submodules; custom
workflows are not deployed through compose. And it is **only needed for manual web QA** (a human
exercising the workflow in the ecoscope-web app) — the desktop app imports a
workflow from its release tag directly, no compose deploy needed.

### Requirements on the workflow repo

- **Deployment needs version tags on the workflow repo.** The per-template ref inputs on the
  dev-deploy dispatch must be a version tag (not a branch or SHA), and post-deploy the tag is read
  back via `git submodule status` (git-describe) and registered as the template's service-URL
  version — which must be ≥ the version already registered for that env.
- Tag shapes: `vMAJ.MIN.PATCH` deploys to dev/stage/prod (and preview);
  `vMAJ.MIN.PATCH.N` is a **pre-release tag, accepted by preview environments only** and rejected
  by dev/stage/prod.

### Dev and preview deploys

Dev deploys are dispatched (**Create PR to deploy dev** = `dispatch-create-dev-deploy-pr.yaml`)
against refs; the bot PR to compose `main` carries the `automerge` label and merges itself.
Ticking **Deploy Preview Environment** instead labels the PR for an isolated per-PR stack at
`https://app-preview-<pr>.dev.ecoscope.io` (dev login, seeded from a dev DB snapshot; torn down
when the PR is closed). Promotion `main`→`stage`→`prod` is always a human PR — automerge is
disabled for those bases.

### WIP-tag flow for workflow changes in QA

1. On a branch in the release repo, recompile and tag `vMAJ.MIN.PATCH.0` (the intended next
   version + `.0`).
2. Deploy it to a preview env (previous section).
3. Fixes during QA: bump the fourth segment (`.0`→`.1`) and push the submodule bump to the open
   deploy PR. The registered version is unchanged, so the cached params schema / image URI are
   **not** refreshed — bump VERSION.yaml and cut a fresh `.0` tag if you need that. Never lower
   VERSION.yaml mid-QA.
4. When QA passes: delete the WIP tags, set VERSION.yaml to the real version, PR the branch to
   `main`, and **close** (don't merge) the preview deploy PR.

### Naming trap: `stage` vs `staging`

The compose `stage` branch/environment is unrelated to the `staging` branch in catalog workflow
repos. Workflow-repo `staging` gates what enters a workflow release; compose `stage` gates which
platform release reaches the stage environment.
