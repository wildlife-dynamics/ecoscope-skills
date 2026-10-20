# Publishing a release to the shared workflow catalog

How a tagged release of a v2 (sandboxed) workflow becomes a card every user can add, in every
environment. The whole process runs in the org's `compose` repo, not the workflow repo, and its
authority is compose's `add-a-catalog-workflow.md` (introduced by compose PR #2998, 2026-10);
re-read that file before relying on a detail here. Nothing in this topic is run by a skill:
`/ecoscope:publish` stops at the workflow repo's green CI and hands off here.

## Contents

- The shape of it
- The `ecoscope-web` branch — where catalog releases come from
- Before the tag — what the release must satisfy
- `prepare` — attach the release artifacts
- The security review
- The compose PR — manifest entry and overlay
- What CI does on the PR (`catalog-gate.yml`)
- Merge is the dev approval (`catalog-approve.yml`)
- Promote to stage and prod (`catalog-promote.yml`)
- Approving by hand
- Traps
- Where to verify

## The shape of it

```
workflow repo                      compose repo                                   environments
─────────────                      ────────────                                   ────────────
tag vX.Y.0 (numeric)  ─────►  prepare  ──►  review  ──►  PR: manifest + overlay
                                                           │ catalog-gate (CVE gate + dep delta)
                                                           ▼
                                                         merge ───────────────────────────►  dev   (approve + publish)
                                                           │  QA in dev
                                                           ▼
                                                 dispatch "Catalog promote" ──────────────►  stage
                                                 dispatch again ──────────────────────────►  prod
```

Two things are decoupled on purpose: **approval** (an allowlist object in a per-environment GCS
bucket, which lets a release be registered and run) and **publishing** (a POST that lists the
version in that environment's catalog). Both are needed before a user sees a new version. The
catalog lifecycle is also separate from the platform deploys — compose's `stage.yaml` /
`prod.yaml` no longer sync the catalog (`ci.md` § Web deployment (compose)).

## The `ecoscope-web` branch — where catalog releases come from

The catalogued workflow repos (`wildlife-dynamics/home-range`, `wildlife-dynamics/ndvi`) carry
**two release lanes on one `spec.yaml`**, and every ref in the compose manifest was tagged from
the second:

| | `main` (Desktop lane) | `ecoscope-web` (shared-catalog lane) |
|---|---|---|
| Compiled for | Ecoscope Desktop — `_recompile.yml` runs the compile **without** `--variant=gcp`; inner `pixi.toml` has no `wt-task-gcp` / `wt-runner-gcp` | the sandbox — `_recompile.yml` passes **`--variant=gcp`**; inner `pixi.toml` pins `wt-task-gcp` and `wt-runner-gcp` |
| Spec `metadata:` | may be absent | present, with the fleet extras incl. `outputs` (`catalog.md` § Spec `metadata:`) |
| `tag.yml` | ndvi: triggers on PRs to `main` / `patch-*`; home-range: none | triggers on PRs to **`ecoscope-web`** / `patch-*` — merging cuts `vMAJ.MIN.PATCH` and the GitHub release that `prepare` attaches to |
| `staging` / `guard-main-prs` / `promote-staging` | where the repo has them (ndvi) | not on this lane — PRs go straight to `ecoscope-web` |
| `VERSION.yaml` | its own sequence (home-range 0.6.0, ndvi 0.4.0 at the time of writing) | its own, **higher** sequence (home-range 1.1.0, ndvi 1.0.1) — the compiler decides each bump against *this* branch's previous build |

Verify the lane before trusting it: `git show origin/ecoscope-web:.github/workflows/_recompile.yml`
for the variant flag, `…:.github/workflows/tag.yml` for the trigger branches, and `grep -c
wt-task-gcp <WF>/pixi.toml` on each branch (`compile.md` § `--variant=gcp`).

**How work reaches it.** Feature work lands on `main` as usual (`/ecoscope:develop` →
`/ecoscope:publish`). When the catalog should pick it up, open a **"Merge `main` into
`ecoscope-web`"** PR (home-range #17 is the model), or a fix PR straight to `ecoscope-web` when
the change is catalog-only (home-range #18, ndvi #29). For the merge PR:

1. Merge `main` into a branch cut from `ecoscope-web`. Conflicts are **all in generated files**
   — `<WF>/README.md`, `VERSION.yaml`, `graph.png`, both `pixi.lock`s. Do not hand-resolve them.
2. Take `ecoscope-web`'s copies of the generated tree as the base
   (`git checkout origin/ecoscope-web -- <WF>/ pixi.lock`), keep `main`'s `spec.yaml` (plus the
   `metadata:` block, which only `ecoscope-web` has — keep it), then **recompile the merged spec
   with `ecoscope-web`'s toolchain**: the outer-pin compiler, `--update --variant=gcp`, exactly
   the flags its `_recompile.yml` passes (`/ecoscope:publish` § 3 with `<base>` =
   `ecoscope-web`). `--update` bumps from `ecoscope-web`'s VERSION, not `main`'s; a MAJ bump
   means the form schema changed and saved web configurations may stop validating — say so in
   the PR body, and remember it strands catalogued workflows pinned to the old major (§ Traps).
3. Confirm the compiled package still carries the GCP runtime (`grep -c wt-task-gcp
   <WF>/pixi.toml` ≥ 1) — a compile with `main`'s flags silently drops it, and CI's diff fails.
4. Run the mock cases; CI runs the full suite. The PR body lists what comes in from `main`, how
   conflicts were resolved, and the version and its reason.
5. Merging cuts the tag. Then this topic's lane: `prepare` → review → compose PR → promote.

**Two gates to know about.** The version gate in `test.yml` on *both* branches compares against
**`origin/main`**, so an `ecoscope-web` PR needs a VERSION above `main`'s as well as above
`ecoscope-web`'s — true as long as `ecoscope-web` runs ahead, which the lane relies on. And
`test.yml`'s `push` trigger lists `[main, ecoscope-web]` in home-range only; ndvi's runs on PRs
alone.

## Before the tag — what the release must satisfy

Checked in the workflow repo, before or during `/ecoscope:publish` (with `<base>` =
`ecoscope-web` when the release is for the catalog — previous section):

- **Config form is web-safe**: `ecoscope:transform` keys set where the web app needs them; no
  direct file inputs or arbitrary file downloads; no sensitive inputs such as API keys.
- **Compiled with `--variant=gcp`** (`compile.md` § `--variant=gcp`). The repo's `dev/recompile.sh`
  is the record; a Desktop-only variant cannot run in the sandbox.
- **Strictly numeric tag** `vMAJ.MIN.PATCH`, derived from `VERSION.yaml`, never chosen by hand. The
  server orders versions with `string_to_array(version, '.')::int[]`, so a `-rc1` or `.N` suffix
  breaks the **whole listing endpoint**, not just that row. WIP tags (`ci.md` § WIP-tag flow) are
  for preview environments only and never go in the manifest.
- The release repo's layout is what `prepare` expects: exactly one `*-workflow/` directory holding
  `VERSION.yaml`, `pixi.toml` and the package's `rjsf.json` / `params.json`, and a `layout.json`
  at the repo root (a bare JSON array — `prepare` wraps it as `{"layout": [...]}`).

## `prepare` — attach the release artifacts

The workflow repo's `tag.yml` creates the tag and the GitHub release, nothing more. `prepare`
builds the wheel, pixi-packs `environment.tar`, writes `metadata.json`, and uploads both to that
release. Needs `pixi`, `pixi-pack` and an authenticated `gh` on `PATH`; run from a compose
checkout, pointed at a local clone of the *release* repo:

```bash
uv run scripts/custom-workflows/templates.py prepare ~/code/<workflow-repo>
```

Flags: `--no-upload` builds without pushing; `--create-release` when the release does not exist
yet; `--clobber` replaces assets after a recompile.

Afterwards, open the release and confirm `environment.tar` and `metadata.json` are attached. Note
the printed **`metadata.json` digest**: the allowlist object is content-addressed from it, so any
re-run of `prepare` that changes `metadata.json` yields a new digest and silently **invalidates an
existing approval** — the next `sync-catalog` 403s on that environment.

## The security review

The reviewer runbook is compose `scripts/security/README.md`: Part 1 is the
`/custom-workflow-review` skill (symlinked into compose's `.claude/skills/`), Part 2 is a manual
pass. Invoke the skill naming the catalog explicitly — it changes which paths it writes:

```
/custom-workflow-review review github.com/wildlife-dynamics/<repo> at tag v1.2.0 —
this is a candidate for the shared catalog
```

With "for the shared catalog" it writes one overlay at
`scripts/security/catalog/suppressions/<repo>.grype.yaml` and one manifest entry in
`scripts/security/catalog/workflows.yaml`; without it, it assumes the per-environment
`environments/<env>/…` paths, which are the wrong home for a shared template.

**Run it in a disposable sandbox / VM / container.** Its build step runs `pixi install --locked`,
which executes the author's install-time code on the reviewing machine.

The skill does static supply-chain triage, the `scan.py` CVE gate, a post-build inventory, a full
read of every author-supplied task, and drafts a security-posture report; it will author
justified suppressions for findings it proves unreachable. It never runs `approve` / `revoke` /
`register`, and it does **not** produce the verdict — Part 2 does: provenance of the
non-first-party closure (compiled extensions, pre/post-link scripts), an adversarial re-read of
the author tasks, and re-deriving every "safe because…" from code rather than the author's prose.

If a suppression was added, prove it through the manifest-driven path rather than a hand-passed
`--suppressions` (which accepts any path and masks a filename mismatch). A first-time entry has
no manifest row yet, so add it first — it belongs in the PR anyway:

```bash
uv run scripts/security/scan.py --all \
  --manifest scripts/security/catalog/workflows.yaml --only <repo>
```

and confirm the finding moved from active into the suppressed audit trail.

## The compose PR — manifest entry and overlay

A PR to compose `main` containing:

- the entry in `scripts/security/catalog/workflows.yaml` — `name`, `source` (git URL of the
  release repo), `refs` with the new tag **added** (older refs stay; see Traps), `envs`
  (default `[default, runner]`), `suppressions`, and the hand-authored `display_name` and
  `description` (one line, written for users — deliberately *not* the spec's maintainer-facing
  description);
- the overlay at `scripts/security/catalog/suppressions/<repo>.grype.yaml`, if the review
  produced one. `<repo>` is the GitHub repository name **verbatim from the release URL** — a
  misnamed overlay is silently ignored and every rule in it applies to nothing;
- the **review verdict in the PR description**. The allowlist object records only the service
  account that wrote it and the PR number from the merge commit, so the PR body is the audit
  trail: say which parts of the runbook ran and what was concluded (the Pre-flight checklist in
  `add-a-catalog-workflow.md` is its shape).

**Tag a security reviewer.** Nothing routes a catalog PR to one; an approving review from whoever
is around is enough to approve a release.

A preview deployment on this PR gets its own copy of dev's database (catalog publishing is
additive and entries are never removed automatically), which adds 10–20 minutes before the
preview comes up. Nothing to do; just expect it.

## What CI does on the PR (`catalog-gate.yml`)

Triggered by any change under `scripts/security/catalog/**`. It runs the same fail-closed
dependency gate `approve` runs — `sync-approvals --dry-run` on the **shipped** `environment.tar`,
not a rebuild — scoped to the refs this PR adds (and to every ref of an entry whose overlay
changed), and it writes nothing. It holds no cloud credentials by design: a `pull_request` run
executes the workflow file from the PR head, so a job that could write an allowlist object would
be one a PR could rewrite to approve anything.

It upserts one PR comment with, per ref, the gate verdict and a **dependency delta** against the
previously-approved ref. For a fast-follow that delta is the review surface: added packages are
Part 2's provenance worklist, and everything else was vetted by the previous approval. A first
approval has no baseline and the comment says so — the whole closure is unvetted.

A red gate means an un-suppressed high/critical CVE in the artifact: bump the vulnerable pin (a
new workflow release, back through `/ecoscope:publish`) or add a justified suppression. Never
suppress a reachable exposure to turn the gate green.

> A green gate is **not** a security verdict. It means no un-suppressed high/critical CVE —
> nothing about malicious code, which has no CVE to match.

## Merge is the dev approval (`catalog-approve.yml`)

**Merging the PR is what approves the release in dev.** On push to `main` touching
`scripts/security/catalog/**`, the workflow reconciles the dev allowlist bucket against the
manifest (`sync-approvals --envs dev`, recording the commit, run URL and PR number on the object),
then publishes the manifest's refs to dev's catalog via `template-service-url-version-bump.py
sync-catalog`. Refs already approved are skipped without a download or scan, which is what makes
it cheap to run on every merge. Nothing is needed locally — no `gcloud`, no scan.

Then **QA in dev**: add the workflow from the catalog, configure and run it. "Live in dev" is the
gate for everything after this.

## Promote to stage and prod (`catalog-promote.yml`)

Run the **Catalog promote (stage/prod)** workflow (`workflow_dispatch`, from `main` only): pick
the environment and either one manifest entry `name` or `all`. It:

1. asserts the entry is **live in dev's catalog** (not merely approved there — an approval nobody
   published proves nothing was exercised; `skip_dev_check` exists for the rare exception and
   wants a reason in the run notes);
2. re-derives and re-gates the approval in the target bucket rather than copying dev's object —
   it re-verifies `metadata.json` and the `environment_tar_digest` against the shipped artifact,
   so a release mutated after its dev approval is caught here;
3. POSTs the refs to that environment's catalog.

Run it for `stage`, QA there if the change warrants it, then again for `prod`. Where the `prod`
GitHub environment has required reviewers, the run waits for one. It is deliberately not a bucket
mirror: only refs in the catalog manifest are ever written, so per-environment templates never
reach prod by accident.

Check what is where, without writing anything (needs `gcloud` read on the three buckets):

```bash
uv run scripts/custom-workflows/templates.py sync-approvals \
  --manifest scripts/security/catalog/workflows.yaml --envs all --report-only
```

## Approving by hand

Still supported, and the only way to approve a **per-environment** (non-catalog) template:

```bash
uv run scripts/custom-workflows/templates.py approve --catalog \
  --release-url https://github.com/wildlife-dynamics/<repo>/releases/tag/v1.2.0 \
  --bucket ecoscope-custom-workflows-digest-allowlist-dev
```

Targets dev alone; `--envs all` or `--envs stage,prod` widens it, but prefer the promote
workflow, which gates on dev QA. Unlike CI it also upserts the manifest in the working tree —
commit that in the PR. Prerequisites: `gcloud` logged in with **write** IAM on the bucket
(`roles/storage.objectAdmin`), and `pixi-unpack`, `syft`, `grype` on `PATH`
(`pixi global install pixi-unpack syft grype`).

`failed to interact with the package cache layer`, naming a *different random package each run*,
is `pixi-unpack` overflowing a tmpfs `$TMPDIR`, not a cache problem. Use a disk-backed temp dir:
`TMPDIR=$HOME/.cache/tmp uv run … approve --catalog …`.

## Traps

- **Older refs stay in the manifest.** The server serves only the latest as the catalog entry, but
  users' existing workflows are pinned to older refs and still run, so the scan must keep
  covering them. Prune a ref only once it is below the current latest major.
- **A MAJOR bump strands pinned workflows.** Adding a ref that raises MAJ makes every workflow
  pinned to the old major 409 at dispatch as soon as it syncs. Deliberate migration only — say so
  in the compose PR, and in the workflow PR body (`/ecoscope:publish` § 1 already flags a MAJ
  bump).
- **`display_name` / `description` only reach the server with a new tag.** `sync-catalog` 409s
  on an already-published version before display metadata is applied, so editing them alone
  does not move an existing card. They are hand-authored and preserved across `approve` /
  `revoke`; omit them and the server falls back to the GitHub repo name and About text
  (`catalog.md` § Web catalog).
- **Overlay filename must match the repo name verbatim.** A mismatch is silent: the overlay is
  ignored and nothing in it applies.
- **Re-running `prepare` invalidates the approval** when it changes `metadata.json`; the digest
  moves and the allowlist object no longer matches.
- **`revoke --catalog` only blocks new runs.** A revoked entry stays listed and addable until an
  ADMIN retires it with `DELETE /v1/workflow_catalog/<id>`. Pair the two.
- **A repo cannot be both catalog and per-environment.** `approve --catalog` refuses a repo also
  present in an `environments/<env>/workflows.yaml`.

## Where to verify

| Fact | Look at (compose repo) |
|---|---|
| The procedure and its checklist | `add-a-catalog-workflow.md` |
| `prepare` / `approve` / `revoke` / `sync-approvals` flags and semantics | `scripts/custom-workflows/README.md`; `templates.py <cmd> -h` |
| Reviewer runbook, Parts 1 and 2 | `scripts/security/README.md`; `.agents/skills/custom-workflow-review/SKILL.md` |
| Manifest schema and field comments | `scripts/security/catalog/workflows.yaml` header |
| PR gate, delta computation | `.github/workflows/catalog-gate.yml`; `scripts/security/catalog_delta.py`, `sbom_delta.py` |
| Dev approval on merge | `.github/workflows/catalog-approve.yml` |
| Promotion and the live-in-dev assertion | `.github/workflows/catalog-promote.yml`; `template-service-url-version-bump.py assert-published` |
| Allowlist enforcement (register + run dispatch) | ecoscope-server `README.md` § v2 (sandboxed) workflow templates |
