---
name: publish
description: Use when the user asks to publish, release, ship, or cut a version of an ecoscope workflow, to open or fix its publish PR, or to get a finished develop branch through CI — "publish X", "release X", "get X ready for the catalog / Desktop", "bump the version and recompile for CI", "CI says generated files differ / VERSION.yaml must be greater than main". Also fires when a repo needs its editable or path requirements reverted to released pins, a pixi.lock or VERSION.yaml restored, or a compile that matches the repo's own CI. Does not fire for building or fixing the workflow itself (develop), and never merges or tags.
---

# Publish an ecoscope workflow

Mirror this repo's CI exactly, prove it locally, hand the branch to the PR. This is a narrow
bridge: the commands below are copied, not composed — substitute `<base>` and `<WF>` and nothing
else. Every fact lives in `${CLAUDE_PLUGIN_ROOT}/reference/` and is linked at the point of use.

## Contents

0. Preflight
1. Read the repo, propose the release — then approval
2. Pins and release gates
3. The CI-mirroring recompile (checklist)
4. Test as CI tests
5. VERSION
6. Commit, PR, watch — and stop
7. Hard rules
8. Handoffs

## 0. Preflight

**Environment: any shell, from the workflow repo root.** Run
`${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh`; fix every `FAIL` before going on. Note the line
comparing this repo's outer compiler pin with the global compiler — a mismatch is normal and is
exactly why § 3 compiles through the outer pixi env, never with the global compiler
(`${CLAUDE_PLUGIN_ROOT}/reference/environments.md` § Why publish compiles go through pixi).
Then `git fetch origin` — § 5's gate is measured against `origin/main`, and a stale ref hides a
merged PR. If `.scratch/progress.yaml` exists, read it: a publish cycle in progress records the
gate it was waiting on.

## 1. Read the repo, propose the release — then approval

**Environment: git and the editor; nothing is compiled or edited yet.** The repo's checked-in
files are the authority for how *this* workflow publishes — the hub template is where they come
from, but the copy in the repo is what CI runs (`${CLAUDE_PLUGIN_ROOT}/reference/ci.md` §
Repo-specific variation). Read, and write down what each says:

| Read | Take from it |
|---|---|
| `.github/workflows/` listing | CI family (`test.yml` + `_discover` + `_recompile` = wt family; `ci.yml` with snapshots = legacy catalog — this procedure does not apply, see `ci.md` § The two CI families). Presence of `tag.yml` (merge cuts a release), `guard-main-prs.yml` / `promote-staging.yml` (PRs go to `staging`). |
| `_recompile.yml` "Recompile workflow" step | the exact recompile invocation: `bash dev/recompile.sh --update`, or an inline `pixi run … wt-compiler compile …`. |
| `dev/recompile.sh` (when CI calls it) | every flag it passes — `--variant=gcp` or not, `pixi update` on the outer manifest or not, `dot -c`. This is the record of this workflow's deployment target (`${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § `--variant=gcp`). |
| `test.yml` | the version gate (compares to `origin/main`), the OS matrix, the test command (`dev/run-test-cases.sh --all` in most repos; `dev/pytest-cli.sh <id> --all` in some — the same harness shape, but it runs `pixi update` on the inner manifest first unless `--skip-setup`), and the `env:` block naming the secrets the live cases need. |
| outer `pixi.toml` + `pixi.lock` | compiler pin; `platforms` must list `win-64` when the matrix has Windows; `[tool.wt] published`, if present. |
| `spec.yaml` `requirements:` | every pin; any `path:` / `editable:` / `channel: file://` / `version: "*"` (`validate-spec` rejects them). |
| repo-state signals (`${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md` § Repo-state signals) | branch and lane; `VERSION.yaml` here vs `git show origin/main:<WF>/VERSION.yaml`; whether the inner `pixi.lock` exists; `wt-task-gcp` in the inner `pixi.toml`; `git status` clean. |
| `git tag --list 'v*'`, `gh pr list --state open`, root `README.md` | highest existing tag; an open publish PR to update instead of a new one; whether the user guide describes the options this release ships. |

Then propose the release, concretely, opening with one line stating your reading — "Publishing
`<repo>`: `develop/<topic>` is N commits over `<base>`, VERSION 1.1.0 → 1.2.0, gcp variant per
`dev/recompile.sh`, pins unchanged, base `main`". If the request is really "fix it, then
publish", route the fix to `/ecoscope:develop` first. Settle:

| Item | Proposal |
|---|---|
| Base branch | `staging` when the repo has `guard-main-prs.yml` / an `origin/staging` branch (catalog repos, QA'd on `staging`); otherwise `main`. Say which and why. |
| Branch | `publish/<repo-name>`, cut from the develop branch. If it already exists — locally, on origin, or with an open PR — continue it (switch to it, bring the develop branch in) or ask which; if it is *ahead* of develop (an earlier release attempt), list its commits and propose which stay — pins it already carries are listed as "already on the branch", and only further bumps are proposed. After switching, re-run § 0 on that tree. Never invent a suffixed variant. |
| Pins | **Propose the refresh.** Look up the latest released version of the compiler (outer `pixi.toml` pin) and of every task library in `requirements:` (§ 2's lookup) and list each as `current → latest`, recommending the update — a release is the moment to carry the fleet forward, and CI compiles at whatever the outer pin says. Editable / `path:` requirements revert to a released version regardless. The user approves or declines each line; what is approved passes § 2's gate and the tests prove it, what is declined stays exactly as develop proved it. |
| Recompile | the command copied from the repo (§ 3), with the flags it passes and no others. |
| Version | the intended `MAJ.MIN.0`: +1 on MIN, or +1 on MAJ (MIN reset) when the form's parameters changed — `--update` decides this from `params_sha256` (§ 5), and a MAJ bump means saved Desktop configurations must be redone, which goes in the PR body. |
| Tests | `--all` locally; live cases need the connection env vars in your shell or they are CI's job; the secrets `test.yml` names must exist in the repo (the user sets them). |
| Review and E2E | propose `/ecoscope:review` (verified passes plus the human checklist) and, when the workflow runs in Ecoscope Desktop, `/ecoscope:e2e` — both on the develop branch, **before** the release is cut; a red finding goes back to `/ecoscope:develop` first. |
| User guide | **a gate, not an offer**: the root `README.md` must describe this release — every config-form card and field (compiled `rjsf.json`) and every dashboard widget, at this release's defaults. Name what is missing or stale; `/ecoscope:guide` brings it current before § 6, and no PR opens without it. |
| Preview deploy | catalog workflows only (base `staging`, vendored into the compose repo): after CI is green, propose the preview-environment deploy — a manual step the user performs (§ 6). |
| Merge consequence | where `tag.yml` exists: "merging cuts `v<X.Y.0>` and publishes the template"; otherwise: "merging updates `<base>`, which is what the Desktop template URL installs — no tag". Stated now, repeated at the PR. |

**Stop and wait for approval.** After approval §§ 2–6 run without check-ins, per the user's
global workflow; come back for a red compile that the restore path cannot fix, a pin that fails
its release gate, a secret that is missing, or red CI.

## 2. Pins and release gates

**Environment: the editor, and read-only network.** Cut the branch: `git switch -c
publish/<repo-name>` from the develop branch. Then, in `spec.yaml`:

- Revert every `path:` / `editable:` requirement to a released pin
  (`${CLAUDE_PLUGIN_ROOT}/reference/spec.md` § `requirements:`) and delete
  `dev/postcompile-editable.sh` if it only served the editable phase (`chore: revert dev-mode
  requirements to released pins`).
- Every task-library pin must resolve from its channel — a pin that is only on someone's disk
  fails the 3-OS solve, and `validate-spec` cannot see that. Prove each one:

  ```bash
  curl -sL <channel>/noarch/repodata.json \
    | jq -r '(.packages // {}) + (."packages.conda" // {}) | keys[]' | grep '^<name>-<version>-'
  ```

  (channel `https://repo.prefix.dev/ecoscope-workflows/` or `…/ecoscope-workflows-custom/`;
  `ci.md` § Release tagging). For a library released *for* this workflow, also confirm the task
  symbol exists at the library's tag (`git grep -l <fn> v<X.Y.Z>` in the library checkout).
- Outer `pixi.toml`: set the approved compiler pin (`wt-compiler = "==<version>"`); `platforms`
  includes `win-64` when `test.yml` runs Windows. Either edit re-solves the outer lock in § 3,
  and it is committed with the tree (`ci.md` § test-workflows).

Nothing else in the repo is edited by hand from here on. The only file under `<WF>/` ever
written by hand is `VERSION.yaml` (§ 5).

## 3. The CI-mirroring recompile (checklist)

**Environment: the repo's outer pixi env, at the pinned compiler — through `pixi run
--manifest-path pixi.toml`, or through `dev/recompile.sh` which does that for you.** Never the
global `wt-compiler` here: codegen differs between compiler versions and CI's diff will show what
you cannot see locally (`compile.md` § Canonical commands, publish compile).

Run these in order, each bare or redirected to a file (`> <step>.log 2>&1; echo exit=$?`), read
the log — the compile stage in full, the `pixi update` churn above it for `error` / `warn` /
`refus` — and check the step off. `<WF>` is the single `*-workflow/` directory; `<base>` is
the base branch from § 1.

- [ ] **Restore the publish-state inputs from base.** A dev compile on the develop branch may
      have reset `VERSION.yaml` to 0.0.0 and dropped the inner `pixi.lock`; `--update` refuses to run without
      `pixi.lock`, `VERSION.yaml` *and* `README.md`, and the version bump in § 5 counts from
      whatever VERSION it finds. Restore the whole generated tree, not three files — everything
      under it is regenerated in the next step anyway, and this is also the restore path if the
      compile dies after `--clobber` (`compile.md` § Restore playbook):

      ```bash
      git checkout <base> -- <WF>/
      ```

- [ ] **Run exactly what CI runs.** When `_recompile.yml` calls the script:

      ```bash
      bash dev/recompile.sh --update
      ```

      When it inlines the compile instead, first `pixi run --manifest-path pixi.toml dot -c`
      (changes no output; without it the graph step dies *after* `--clobber` has emptied the
      tree — `compile.md` § Compile-time standing rules), then that inline block verbatim,
      prefixed the way CI does (`pixi run --manifest-path pixi.toml …`), with `pixi update
      --manifest-path pixi.toml` if CI runs it and `--variant=gcp` only if CI passes it. Do not
      add `--local`, do not drop `pixi update` to avoid lock churn, do not substitute the global
      compiler. The `pixi update` re-solves the **outer** lock — that churn is part of the release
      and is committed (`compile.md` § Canonical commands).

- [ ] **Exit code 0 and the tree is whole.** `<WF>/pixi.lock`, `<WF>/VERSION.yaml`,
      `<WF>/README.md` exist (CI's "Validate excluded files exist" step). If the compile failed:
      match `compile.md` § Common compile errors, then restore (`git checkout <base> -- <WF>/`),
      fix the cause, and re-run this checklist from the top. A prefix.dev fetch flake is a retry,
      not a bug.

- [ ] **Read the diff the way CI reads it.** CI diffs the generated tree excluding `pixi.lock`,
      `README.md`, `VERSION.yaml`, `graph.png` (`ci.md` § `_recompile.yml`). Run the same:

      ```bash
      git diff --stat -- <WF>/ ':(exclude)<WF>/pixi.lock' ':(exclude)<WF>/README.md' \
        ':(exclude)<WF>/VERSION.yaml' ':(exclude)<WF>/graph.png'
      ```

      Every file listed is a real output change: `params.json` / `rjsf.json` (the form),
      `dags/*.py` (the pipeline), `pixi.toml` (pins or **variant** — `wt-task-gcp` appearing or
      vanishing means the variant differs from base; check § 1's reading of `recompile.sh` before
      believing it). **Report this diff to the user now, before going on** — a short list, one
      line per file: what changed and which cause it traces to (the develop fix, a pin from § 2,
      a **compiler bump** whose codegen change touches files the spec never mentioned — expected,
      and CI will reproduce it at the same pin). Nothing listed and a spec that did change means
      the change had no compiled effect — say so. The same list goes into the PR body.

- [ ] **Variant check.** `grep -c 'wt-task-gcp' <WF>/pixi.toml` matches what § 1 said CI does
      (1+ for gcp, 0 for Desktop-only). Committing the wrong variant fails CI's diff in the
      direction you least expect (`compile.md` § `--variant=gcp`).

## 4. Test as CI tests

**Environment: the inner pixi env, only through the harness.** CI's `test-workflows` runs the
full case set on ubuntu, macOS and Windows with `pixi run --locked` — against the committed
inner lock § 3 just produced when its script is `run-test-cases.sh`, or against a freshly
re-solved one when it is `pytest-cli.sh` (§ 1), so a lock-dependent failure can appear only in
CI there. Run the same set locally:

```bash
./dev/run-test-cases.sh --all > test.log 2>&1; echo exit=$?
```

(`--frozen` when git-tag requirements are present — `compile.md` § Compile-time standing rules.)
Read the whole log. Pass = exit 0 and every case: `result.json` present, `.error == null`
(`${CLAUDE_PLUGIN_ROOT}/reference/testing.md` § `dev/run-test-cases.sh`). When the live cases
cannot run here, run the mock cases one at a time instead — `--case <name> > test-<name>.log
2>&1; echo <name> exit=$? >> test-summary.log` — so every exit code lands in a file; never in a
pipe. Then:

- **Live cases** (`mock_io: false`) need `ECOSCOPE_WORKFLOWS__CONNECTIONS__…` in your shell
  (`${CLAUDE_PLUGIN_ROOT}/reference/connections.md`). If they cannot run here, report them as
  CI's to run — and confirm `test.yml`'s `env:` block wires the secrets those connection names
  need. A missing secret is surfaced to the user with its exact name; it is never set by you.
- **The two OSes you are not on** are proven by the lock, not by you: the outer `pixi.toml`
  lists all three platforms and the inner lock solved for them (`grep -c 'win-64'
  <WF>/pixi.lock` > 0). Read the Windows leg's log in § 6 rather than assuming it.
- **Outputs, not just status.** Open the results of the `base` case: the widgets exist and carry
  data; the grouped views fan out as before. A green run with empty outputs is the silently-empty
  trap (`testing.md`).

A red case is a `develop` job: stop, report, offer `/ecoscope:develop`; do not patch the
generated tree or the case to make it pass.

## 5. VERSION

**Environment: git.** The gate: `<WF>/VERSION.yaml` must be **strictly greater than
`origin/main`'s**, even when the PR targets `staging` (`ci.md` § test.yml → validate-spec); where
`tag.yml` exists the merge tags `v<MAJ>.<MIN>.<PATCH>` and fails if the tag already exists.

1. What § 3 produced: `--update` bumped the restored base VERSION once — MIN+1, or MAJ+1 with
   MIN reset when `params_sha256` changed (`compile.md` § `--update` semantics). If you ran the
   checklist more than once it bumped more than once.
2. What it must clear: the larger of `git show origin/main:<WF>/VERSION.yaml` and the highest
   `git tag --list 'v*'` — renamed repos carry legacy tags from their old identity, and the tag
   job is monotonic over *all* of them (`ci.md` § Release tagging and legacy tags).
3. The intended value: exactly +1 on MIN — or +1 on MAJ with MIN 0 if step 1's bump was a MAJ
   bump — over the larger of the two numbers in step 2; PATCH 0 unless the base is a `patch-*`
   branch. Read `<WF>/VERSION.yaml`: when the checklist ran once and no legacy tag is higher it
   already says this, and you touch nothing; otherwise set it by hand. If it differs from what
   § 1 proposed, say so in the PR. `VERSION.yaml` is the only place the version lives, so editing it causes no
   recompile diff. Never lower a VERSION that has been pushed.
4. Say the number and its reason in the commit and the PR ("1.1.0 → 1.2.0, parameters
   unchanged").

## 6. Guide gate, commit, PR, watch — and stop

**Environment: git and `gh`.** **Guide gate first.** Compare the root `README.md` against
this release: the cards and fields in `<WF>/…/rjsf.json`, the widgets the `base` run produced,
the defaults. If any option, default or widget this release ships is missing or described
differently, stop here and hand to `/ecoscope:guide`; resume when the README is current. The
guide is part of the release, so it goes into the same PR.

One commit carrying the whole release: `spec.yaml` (if pins
changed), the outer `pixi.lock` (if re-solved), the regenerated `<WF>/` including its
`pixi.lock` and `VERSION.yaml`, the outer `pixi.toml` (if the compiler pin moved), the
`README.md` from the guide gate — `chore: publish-mode recompile (<variant>, <library>
<version>); VERSION <old> → <new>`. `git status` clean afterwards; a generated tree committed piecemeal is
the diff CI will find.

Then hand off to the user's `/pr` skill when it is available — it resolves the base, pushes
the branch, opens or updates the PR, and watches CI. Without it: `git push -u origin
publish/<repo-name>` and `gh pr create --base <base>`. Either way the PR body carries: what the
release contains (from `git log <base>..HEAD`), the generated-tree change list from § 3, pins
and compiler version, variant, VERSION and why, which cases ran locally and which are CI-only,
and — where `tag.yml` exists — the line "merging cuts `v<X.Y.0>` and publishes the template".

Watch `gh pr checks --watch` and read each failing job's log to its gate:

| Job | It means |
|---|---|
| `recompile-workflows` "Generated files differ" | the committed tree was not produced the way CI produces it: compiler version (global vs pinned), variant, or a hand edit under `<WF>/`. Re-run § 3 from the top. |
| `validate-spec` VERSION | § 5 — `origin/main` moved, or the bump did not clear a legacy tag. |
| `validate-spec` requirements | a `path:` / `file://` / `"*"` survived § 2. |
| `test-workflows` on one OS only | a platform-specific solve or path issue; read that leg's log — it is the one you could not run. |
| `test-workflows` auth / connection errors | secrets missing in the repo — name them for the user (`connections.md` § CI secrets). |

Green CI ends this skill. Report the PR URL, the version, and the merge consequence. For a
**catalog workflow** (base `staging`, vendored into the compose repo), also propose the
preview-environment deploy — the user performs it by hand, there is no skill for it yet: a
WIP tag `v<X.Y.0>.0` on the release branch and the compose repo's "Create PR to deploy dev"
dispatch with **Deploy Preview Environment** ticked
(`${CLAUDE_PLUGIN_ROOT}/reference/web-deployment.md` § WIP-tag flow). You cut no tag and
dispatch nothing. Then stop.
If the cycle waits on something (a secret, a library release, a review), offer to record it in
`.scratch/progress.yaml` (check `.scratch` is gitignored first — `repo-layout.md`).

## 7. Hard rules

Each has its mechanism in the linked file; they are prohibitions here because they get broken
under pressure ("it's only lock churn", "the old procedure had an update-deps step", "CI will
catch it", "they clearly want it merged").

- Never merge, tag, delete a tag, or push to `main` / `staging` / a default branch without an
  explicit go-ahead in this conversation. "Can we merge?" and "is it ready?" are questions —
  answer them, state the side effect ("merging cuts v1.2.0 and publishes the template"), and
  wait (`process-rules.md`).
- Never `gh secret set`. Name the secret and stop (`process-rules.md`, `connections.md`).
- Never bump a task-library or compiler pin without approval. The refresh is proposed line by
  line in § 1; a declined line stays exactly as `develop` proved it.
- Never compile for a publish branch with the global `wt-compiler`, and never change the flags
  the repo's CI passes — not `--local`, not dropping `pixi update`, not adding or removing
  `--variant=gcp` (`environments.md`, `compile.md`).
- Never pipe `wt-compiler`, `pixi`, `dev/recompile.sh` or `dev/run-test-cases.sh` through
  `tail`, `head`, or `grep -v`; redirect to a file, record the exit code, read the file
  (`environments.md`).
- Never `--clobber` without the restore path in hand (`git checkout <base> -- <WF>/`), and
  never hand-edit anything under `<WF>/` except `VERSION.yaml` (`compile.md`).
- Never publish with real organisational data anywhere in the tree (`process-rules.md`).

## 8. Handoffs

Offer each when it becomes relevant, and wait for a yes; never start one unasked.

| When | Offer |
|---|---|
| The request bundles a fix or feature with the release, or a case is red | `/ecoscope:develop` — first; come back here after its human verification |
| A task-library pin is not released yet | `/ecoscope:task` — release it, then § 2 again |
| The README does not describe this release (§ 6 gate) | `/ecoscope:guide` — no PR without it |
| Before the release is cut | `/ecoscope:review`, and `/ecoscope:e2e` for Desktop workflows |
| The branch is committed and ready | `/pr` — or the manual push and `gh pr create` in § 6 |
| CI is green on a catalog workflow | the preview-environment deploy, by hand — `${CLAUDE_PLUGIN_ROOT}/reference/web-deployment.md` |

Close every session by naming what comes next — usually "CI is green; merging is yours". Do not
start it.
