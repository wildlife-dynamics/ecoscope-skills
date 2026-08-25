# Workflow repo CI

What CI actually checks in a workflow repo, where each gate lives, and how merges to `main` become
release tags. Safety rules (never merge without go-ahead, etc.) are in
[process-rules.md](process-rules.md); how a tagged release reaches the web app is in
[web-deployment.md](web-deployment.md).

## Contents
- The two CI families
- The wt-family gates, one by one
- Release tagging and legacy tags
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
- **`test.yml` → validate-spec**: rejects wildcard `version: "*"`, `channel: file://`, and
  `path:`/`editable:` requirements; requires `test-cases.yaml` with ≥1 case; and
  enforces the **version gate** — numeric compare of the inner `VERSION.yaml` against
  `git show origin/main:<version-path>`: **must be strictly greater than `origin/main`, even when
  the PR targets `staging`**.
- **`test.yml` → test-workflows**: 3-OS matrix (ubuntu/macos/windows, fail-fast off), connection
  secrets injected ([connections.md](connections.md)), runs `dev/run-test-cases.sh --all`.
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
- Verify an upstream task-library release before depending on it: the symbol exists at the
  task-library tag (`git grep -l <fn> v<X.Y.Z>`) AND the conda build exists in the channel's
  repodata (`https://repo.prefix.dev/ecoscope-workflows/noarch/repodata.json`).

## Repo-specific variation

CI has drifted into multiple shapes (script-style vs inline recompile, different pinned
pixi/setup-pixi versions, gcp vs non-gcp, secrets for different connections, some repos carrying
catalog-only workflow files that should be deleted). **Always read the repo's own
`.github/workflows/` before opening a PR** and mirror what it does — the hub template is the
canonical source the files are vendored from ([repo-layout.md](repo-layout.md)), but the repo's
checked-in copy is what CI will actually run.
