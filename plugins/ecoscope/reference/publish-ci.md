# Publish gates and CI

What CI actually checks, where each gate lives, and how workflow releases reach users. The
publish *procedure* lives in the publish skill; this file is the single source for the gates and
mechanics it enforces. Safety rules (never merge without go-ahead, etc.) are in
[process-rules.md](process-rules.md).

## Contents
- The two CI families
- The wt-family gates, one by one
- Publication signals and base-branch resolution
- Release tagging and legacy tags
- Deployment (compose repo) — how releases reach environments
- Repo-specific variation

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
- **`test.yml` → validate-spec**: rejects wildcard `version: "*"` and `channel: file://` (and
  publish specs must carry no `path:`/`editable:`); requires `test-cases.yaml` with ≥1 case; and
  enforces the **version gate** — numeric compare of the inner `VERSION.yaml` against
  `git show origin/main:<version-path>`: **must be strictly greater than `origin/main`, even when
  the PR targets `staging`**.
- **`test.yml` → test-workflows**: 3-OS matrix (ubuntu/macos/windows, fail-fast off), connection
  secrets injected ([connections.md](connections.md)), runs `dev/run-test-cases.sh --all`.
  Windows in the matrix means the **outer `pixi.toml` platforms must include `win-64`** (the
  scaffold emits only linux-64/osx-arm64 → setup-pixi fails `unsupported-platform`); after adding
  it, re-lock and **commit the outer `pixi.lock`** — it is tracked in publish repos.
- **`guard-main-prs.yml`**: reads `tool.wt.published` from the **outer `pixi.toml`** (these repos
  have no root pyproject); if true, a PR to `main` must come from `staging` or `patch-*`.
- **`promote-staging.yml`**: manual dispatch; builds the staging→main promotion PR from the
  commit log.

## Publication signals and base-branch resolution

**Derive publication state from the repo itself** — do not maintain a hardcoded catalog list:

| Signal | Meaning |
|---|---|
| `[tool.wt] published = true` in the outer `pixi.toml` | catalog-published: PRs must target `staging` |
| `guard-main-prs.yml` + `promote-staging.yml` present | the repo uses the staging QA flow |
| `tag.yml` present + `vMAJ.MIN.PATCH` tags | merges to main cut releases |
| none of the above | plain repo: PRs target `main` |

Base-branch algorithm: if the published flag is true (or the guard workflows are present), rebase
on `origin/staging` and open the PR with base `staging` (create `staging` from `origin/main` if it
doesn't exist yet); allow an explicit `main` base for hotfixes, and back-merge `main`→`staging`
afterward. Otherwise base `main`. Note **`published = false` is the right setting even for some
released repos** — `true` blocks ordinary feature-branch→main PRs; flipping it is a policy
decision, not housekeeping.

VERSION.yaml lives at `<generated-dir>/VERSION.yaml` as `{MAJ, MIN, PATCH}` — every compiled repo
has one, so its presence is NOT a publication signal. Only VERSION.yaml embeds the version (the
generated pyproject uses dynamic versioning), so bumping it alone causes no recompile diff.

## Release tagging and legacy tags

`tag.yml` (where present): on PRs to `main`/`patch-*` it builds `v$MAJ.$MIN.$PATCH` from
VERSION.yaml, asserts the tag doesn't already exist, and on merge tags + creates the GitHub
release. Consequences:

- **Every PR to main in such a repo must bump VERSION** or the tag job fails on the duplicate.
- **Renamed repos may carry legacy tags** from their old identity — VERSION must stay above the
  highest existing tag to keep tagging monotonic. Check `git tag --list 'v*'` before setting
  VERSION, and verify content by `git grep` **at the tag** (squash merges mean commit SHAs may not
  appear in `git tag --contains`).
- Verify an upstream release gate before publishing against it: the symbol exists at the
  task-library tag (`git grep -l <fn> v<X.Y.Z>`) AND the conda build exists in the channel's
  repodata (`https://repo.prefix.dev/ecoscope-workflows/noarch/repodata.json`).

## Deployment (compose repo)

Workflow repos' own CI deploys nothing. The org's `compose` repo pins each deployable as a git
submodule (workflow repos included — their **committed compiled package** is what gets built into
an image), with a reusable build-deploy pipeline per environment. Facts that matter from a
workflow repo's perspective:

- Version resolution is git-describe based, so deployment **needs version tags** on the workflow
  repo.
- Dev deploys are dispatched (`dispatch-create-dev-deploy-pr.yaml` in compose) against a ref;
  a preview-env checkbox deploys to an isolated preview instead of dev. Bot PRs to compose `main`
  automerge; promotion `main`→`stage`→`prod` is always a human PR.
- **Naming trap: the compose `stage` branch/environment is unrelated to the `staging` branch in
  catalog workflow repos.** Workflow-repo `staging` gates what enters a workflow release; compose
  `stage` gates which platform release reaches the stage environment.

## Repo-specific variation

CI has drifted into multiple shapes (script-style vs inline recompile, different pinned
pixi/setup-pixi versions, gcp vs non-gcp, secrets for different connections, some repos carrying
catalog-only workflow files that should be deleted). **Always read the repo's own
`.github/workflows/` before publishing** and mirror what it does — the hub template is the
canonical source the files are vendored from ([repo-layout.md](repo-layout.md)), but the repo's
checked-in copy is what CI will actually run.
