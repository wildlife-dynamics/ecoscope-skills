---
name: develop
description: Use when the user asks to develop, build, create, implement, add to, change, extend, or fix an ecoscope workflow — a new workflow from a description, a spec.yaml edit (new task, widget, grouper, filter, column, default, card), a form or dashboard tweak that needs a recompile, a failing or missing test case, "recompile and re-run the tests" — or whenever the work happens inside a workflow repo (spec.yaml + test-cases.yaml + a generated *-workflow/ package). Triggers on both "make me a workflow that …" and "I edited spec.yaml, can you compile and test". Does not fire for pure questions about syntax or mechanism with no edit in play (that's the reference skill) or for "publish/release the workflow" (publish).
---

# Develop an ecoscope workflow

The spine. It reads the repo's state, sizes the job, finds tasks, edits `spec.yaml`, runs the
compile→test loop until green, commits, and hands off. It links the knowledge base at
`${CLAUDE_PLUGIN_ROOT}/reference/` for every fact; it does not restate them.

**Violating the letter of a rule here is violating its spirit.** The rules in "Discipline"
exist because each one has silently destroyed work before.

## Contents

1. Preflight and derive the repo state
2. Size the job and choose the ceremony
3. Find the tasks
4. Author the spec and the test cases
5. The compile→test loop
6. Discipline (prohibitions), red flags, rationalizations
7. Handoffs
8. Quick reference

## 1. Preflight and derive the repo state

**Environment: any shell, from the directory that contains (or will contain) `spec.yaml`.**

Run the plugin's preflight if it ships: `${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh`. If it is
absent, do its checks by hand before anything else — `wt-compiler compile --help` (it runs;
the CLI has no `--version`, so read the global version from `uv tool list` or `pixi global
list`), `yq --version` (must be mikefarah go-yq), `dot -V`, `pixi --version`, and the outer pin
`grep wt-compiler pixi.toml` versus that global version. Read the diagnosis; repair before
compiling. Details: `${CLAUDE_PLUGIN_ROOT}/reference/environments.md`.

Then **derive** the phase from the filesystem and git. Never infer it from the words in the
request — "validate", "fix", "publish" in a sentence prove nothing about the tree. Read, in
order:

```bash
git branch --show-current; git status --short      # empty branch = detached HEAD: cut develop/<topic>
ls spec.yaml test-cases.yaml layout.json .scratch/progress.yaml 2>&1
WF=$(ls -d *-workflow 2>/dev/null)                       # exactly one, or none
cat $WF/VERSION.yaml; ls $WF/pixi.lock; grep -c 'wt-task-gcp' $WF/pixi.toml
grep -n 'path:\|editable:' spec.yaml
cat .github/workflows/_recompile.yml dev/recompile.sh 2>/dev/null   # the flag authority
grep -n '^\.scratch' .gitignore
```

Map what you saw onto the signals table in `${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md`
(§ Repo-state signals) and **state the result in one line before doing anything else**, e.g.
*"publish state: inner lock committed, VERSION 1.0.0, gcp variant, CI = `dev/recompile.sh
--update`, branch publish/x"* or *"greenfield: no spec.yaml"*. The three states that change what
you may run:

| Derived state | Consequence |
|---|---|
| **greenfield** (no `spec.yaml`) | go to § 2, greenfield row — plan first, then scaffold |
| **dev state** (`VERSION.yaml` 0.0.0, or no inner lock, or `path:`/`editable:` requirements) | dev compile with the global compiler (§ 5) |
| **publish state** (inner `pixi.lock` committed **and** VERSION > 0.0.0 **and** `wt-task-gcp` in inner `pixi.toml`) | the only compile you may run is the repo's CI recompile, verbatim (§ 5) — a dev compile here silently strips the variant, resets VERSION, and deletes the lock |

`.scratch/progress.yaml` present → read it and resume from it; it is a plan, not a state machine.

Also settle now, from the same read: this repo's CI family and base branch
(`${CLAUDE_PLUGIN_ROOT}/reference/ci.md`), whether the compiler pin differs from the global one,
and — from `_recompile.yml`/`dev/recompile.sh` — whether **this** workflow passes
`--variant=gcp`. That flag is a deployment-target fact (Web yes, Desktop-only no), confirmed
per repo; never assumed (`${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § `--variant=gcp`).

## 2. Size the job and choose the ceremony

Decide this explicitly and **say which row you chose and why** before editing anything.

| Job shape | Ceremony |
|---|---|
| One spec/test-case edit ("add a grouper", "hide that field", "fix the duplicate heading", "re-run the tests") | edit → compile → test → commit. No plan file, no task list, no progress artifact. |
| Several related edits in one session (new widget chain, a rename, a new card) | same loop, one green cycle per coherent edit; a short numbered plan in the reply is enough |
| Greenfield, or a migration, or anything that will span sessions | offer `/ecoscope:plan` (writes `.scratch/prd.md` + `.scratch/progress.yaml`) — first verify `.scratch` is in `.gitignore`, add it if not. Then stop at the **design-approval seam**: present the plan (data source, metrics, groupers, cards, widgets, test cases) and wait for approval per the user's global workflow. Do not build a greenfield workflow speculatively. |
| A task the libraries lack | offer `/ecoscope:task` (§ 7) — don't work around it inside the spec |

"Add X to the spec" can mean the spec already has X and a test case is missing (the baseline
found exactly this): part of sizing is naming **what is actually missing** — spec wiring, form
override, test coverage, fixture — and saying so.

**Branch lane.** Work on `develop/<topic>` cut from the base branch; `publish/<repo>` and
`staging` belong to `/ecoscope:publish`. If the tree is already on a `publish/*` branch, ask
whether the fix belongs to that release before committing on it. Conventions:
`${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md` § Branch and commit conventions.

## 3. Find the tasks

**Environment: none for the scan; the workflow's inner pixi env to confirm.**

Follow the quick path at the top of `${CLAUDE_PLUGIN_ROOT}/reference/task-discovery.md`: find
the name (`${CLAUDE_PLUGIN_ROOT}/scripts/search-tasks.py`), read the signature (`-s <name>`),
then **confirm it resolves in the registry the spec actually pins** (`wt-registry --function
<name>` in the inner env, or the `pixi exec` throwaway env when nothing is compiled yet). Reading
task-library source on disk is not confirmation — the checkout is routinely ahead of or behind
the pin. Reference tasks by bare name; qualify only on a reported collision.

Task semantics and the ones every workflow uses: `${CLAUDE_PLUGIN_ROOT}/reference/tasks.md`;
per-task gotchas: `${CLAUDE_PLUGIN_ROOT}/reference/task-pitfalls.md`. Nothing suitable, or
suitable but broken → § 7, `/ecoscope:task`.

## 4. Author the spec and the test cases

Syntax and validation rules: `${CLAUDE_PLUGIN_ROOT}/reference/spec.md` (the pydantic models in
`wt_compiler.spec` win over any doc). The recurring shapes to copy — pipeline skeleton, grouping
and the spatial-grouper resolver chain, widget chains, dashboard assembly, `groupbykey` —
`${CLAUDE_PLUGIN_ROOT}/reference/patterns.md`. The authoring idiom, in one breath: bind no-op
params with `partial:` so they leave the form; card order is task order; widget tasks carry
`skipif: {conditions: [never]}`; invisible glue tasks live outside any group; never duplicate a
group title. Form-level overrides (`rjsf-overrides`) are the form skill's territory
(`${CLAUDE_PLUGIN_ROOT}/reference/rjsf.md` for a single fact; `/ecoscope:form` for the job).

Test cases: build the recommended set in `${CLAUDE_PLUGIN_ROOT}/reference/testing.md`
(§ Recommended case set) — `base` at the rjsf defaults, each grouper kind covered (combined in
one case when the fixture carries every key, split when it doesn't), toggles flipped, an empty-fixture regression, live case last and only when asked. A param you just
bound via `partial:` must leave `test-cases.yaml` too. Spatial-grouper mock cases use the
fixture's display name (`SpatialGrouperTest` for the stock fixture). Real org data never enters
a fixture (`${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md`).

## 5. The compile→test loop

**Compile only when a compiler input changed** — `spec.yaml` (including `requirements:`). An
edit confined to `test-cases.yaml`, `layout.json`, or `dev/fixtures/` is not a compiler input:
skip straight to the test step. This matters most on a publish-state tree, where the CI
recompile bumps VERSION and re-solves the lock for nothing.

Pick the compile by the state derived in § 1. Both commands are copied from
`${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § Canonical commands — that file is the single
source; if it and this section ever differ, it wins.

**Dev compile — environment: the global `wt-compiler`, from the repo root.** For greenfield and
dev-state trees only.

```bash
wt-compiler compile \
    --spec spec.yaml \
    --pkg-name-prefix=ecoscope-workflows \
    --results-env-var=ECOSCOPE_WORKFLOWS_RESULTS \
    --clobber --no-progress [--install | --update]
```

Choose the trailing flag by what changed, because `dev/run-test-cases.sh` runs
`pixi run --locked` and a plain `--clobber` deletes the inner `pixi.lock`:

| Situation | Flag | Then |
|---|---|---|
| first compile ever (no inner lock) | `--install` | commit the new lock with the tree |
| spec edit, `requirements:` untouched | none | `git checkout HEAD -- $WF/pixi.lock` to put the lock back (no re-solve) |
| `requirements:` changed, or the lock is not in git | `--update` | carries the lock and re-solves it (`pixi update --no-install`); expect lock churn |

Never add `--variant=gcp` to a dev compile. Editable/`path:` requirements need
`./dev/postcompile-editable.sh` after every compile (`${CLAUDE_PLUGIN_ROOT}/reference/spec.md`
§ Editable).

**CI recompile — environment: the repo's outer pixi env, at the pinned compiler.** The only
compile allowed on a publish-state tree. Run **exactly** what `_recompile.yml` runs — usually
`bash dev/recompile.sh --update`, or the inline `pixi run --manifest-path pixi.toml wt-compiler
compile … --clobber --update` step, `--variant=gcp` only if it is there. Do not hand-assemble a
variant of it (dropping `pixi update`, dropping `--update`): the diff gate compares against what
CI produces, and `--update` is what preserves the lock and the VERSION lineage. Before it:
`pixi run --manifest-path pixi.toml dot -c` (a fresh or re-solved outer env has no graphviz
plugin cache; the compile dies at the graph step *after* `--clobber` emptied the dir).

**Before any `--clobber`:** know the restore path — `git checkout <base> -- $WF/` (compile.md
§ Restore playbook). A compile that dies mid-way leaves the tree gutted.

**Read the whole output.** Run the compile bare, or `> compile.log 2>&1` and read the file. On
failure, match the message against compile.md § Common compile errors, fix `spec.yaml`, recompile.

**Test — environment: the inner pixi env, via the harness (never bare `python`).**

```bash
./dev/run-test-cases.sh --case <name>     # while iterating on one path
./dev/run-test-cases.sh --all             # before every commit
```

`--frozen` when git-tag requirements are present; `--local` only from inside the inner env.
Pass = `result.json` exists, `.error == null`, exit 0 — and then **look at the outputs** (the
widget files, the trace values); a green run with empty widgets is the silent-empty-run trap.
Failure classes and fixes: `${CLAUDE_PLUGIN_ROOT}/reference/testing.md`; task-specific ones:
`${CLAUDE_PLUGIN_ROOT}/reference/task-pitfalls.md`. Debug an opaque failure from the inner
`default` env (testing.md § `dev/run-test-cases.sh`).

**Loop:** edit → compile (if a compiler input changed) → test → until green. Then commit.

**Commit discipline.** One commit per green cycle, conventional prefix (`feat:`, `fix:`,
`test:`, `chore:`), containing `spec.yaml`/`test-cases.yaml`/`layout.json` **and** the
regenerated `$WF/` tree. The user's global "commit at the end of every step" applies with the
loop as the step: an unrun test case or a red compile is not a step's end. On a publish-state
tree the CI recompile also moves `VERSION.yaml` and `pixi.lock`; report those two diffs
explicitly in the commit message and the reply — the version gate and the lock are
`/ecoscope:publish` decisions, not a side effect to bury in a `fix:`.

**Halt** and report instead of looping when: (a) the same error survives three consecutive
fix attempts; (b) the error is inside a task (a traceback in the task library, a signature
that can't do what the spec needs) — offer `/ecoscope:task`; (c) a `--clobber` failure gutted
the tree and the restore path doesn't apply cleanly.

## 6. Discipline

Prohibitions. Each has cost real work; none has an exception clause.

- **Never pipe `wt-compiler`, `pixi`, or `dev/run-test-cases.sh` output through `tail`,
  `head`, or `grep -v`.** The pipe returns the filter's status, not the tool's — `grep -v` with
  nothing to remove exits 1, `tail` exits 0 over a failed compile. Redirect to a file and read
  the file. Noise from post-link/librsvg warnings is not a reason.
- **Never dev-compile a publish-state tree.** Signals: committed inner `pixi.lock`, VERSION >
  0.0.0, `wt-task-gcp` in the inner `pixi.toml`. Only the CI recompile, verbatim.
- **Never run `--clobber` without knowing the restore path** (compile.md § Restore playbook).
- **Never hand-assemble the CI compile.** Read `_recompile.yml`/`dev/recompile.sh` and run what
  they run, `pixi update` and `--update` included.
- **Never assert `--variant=gcp` from convention.** It comes from this repo's CI file. Never on
  a dev compile.
- **Never merge, tag, push a default branch, or `gh secret set`** without an explicit go-ahead
  ("can we merge?" is a question, not authorization) —
  `${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md`.
- **Never commit real organisational data** — fixtures are synthetic and generated by a
  committed script.
- **Never `conda activate`; never bare `python` for a workflow run** — every command names its
  environment (`${CLAUDE_PLUGIN_ROOT}/reference/environments.md`).

**Red flags — stop, you are rationalizing:**

- "I'll just `tail` the compile, the top is only pixi noise."
- "It's a quick recompile" / "CI will catch it if the variant is wrong."
- "I'll call the compiler directly to avoid the script's `pixi update`."
- "Docs say `--clobber` alone for iteration" — and the lock is now gone.
- "Commit at the end of every step, so commit now, then run the tests."
- "It's greenfield, so I'll just build it and show them" — the design seam exists for this.
- "The task is right there in the source, no need to check the registry."
- "A local `fix/` branch is fine here."
- "The lock churn matches what CI produces, so I'll fold it into the fix commit."

| Rationalization heard | Reality |
|---|---|
| "Filtering the output just hides warnings" | It hides the exit code. The graphviz failure that gutted a tree was inside a `\| tail -30`. |
| "`--clobber` is the dev-iteration flag" | Alone, it deletes the lock the harness needs. Restore it or use `--update`. |
| "The script's `pixi update` is unnecessary churn" | If CI re-solves the outer lock, that lock is part of the change. Deviating is how the diff gate fails. |
| "Commit now, test after — the workflow says commit every step" | The loop is the step. Two baseline runs committed 0/4-green work. |
| "The user said develop, so build it" | Greenfield means plan, present, wait. Six design questions were guessed in the baseline. |
| "The checkout has the task, so the spec can use it" | The checkout ≠ the pin. Confirm in the registry the spec resolves against. |
| "VERSION bumped, but that's what `--update` does" | On a publish branch that is the version gate. Report it; let publish decide. |

## 7. Handoffs

Each is an **offer** at the point it becomes relevant — name it, say why, and wait for a yes.
Never invoke one automatically.

| When | Offer |
|---|---|
| Greenfield / multi-session, before any scaffold | `/ecoscope:plan` — PRD + `.scratch/progress.yaml` |
| A needed task doesn't exist or is broken | `/ecoscope:task` — then return here with the new pin |
| The job touched `rjsf-overrides`, field titles, conditionals, card layout | `/ecoscope:form` — override syntax, playground validation |
| The job touched `layout.json`, widget sizing, output styling | `/ecoscope:dashboard` |
| A new workflow or a user-visible option changed | `/ecoscope:guide` — the README for non-technical users |
| Desktop behaviour must be proven end to end | `/ecoscope:e2e` |
| The loop is green and the change is complete | `/ecoscope:review` — three verified passes plus the human checklist, **before** publish |
| The user wants it released, or the tree is in publish state and VERSION/lock moved | `/ecoscope:publish` — pins, lock/VERSION restore, CI-matching recompile, PR |

Close every session by naming what comes next from this table. Do not start it.

## 8. Quick reference

| Need | Where |
|---|---|
| Environments, standing rules, preflight | `${CLAUDE_PLUGIN_ROOT}/reference/environments.md` |
| Compile command, flags, `--variant`, restore playbook, error table, fingerprints | `${CLAUDE_PLUGIN_ROOT}/reference/compile.md` |
| Repo-state signals, vendored files, branch/commit conventions | `${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md` |
| Finding and confirming a task | `${CLAUDE_PLUGIN_ROOT}/reference/task-discovery.md` |
| Spec syntax, requirements, `skipif`, authoring idiom | `${CLAUDE_PLUGIN_ROOT}/reference/spec.md` |
| Pipeline shapes, spatial resolver chain, widgets, dashboard | `${CLAUDE_PLUGIN_ROOT}/reference/patterns.md` |
| test-cases.yaml, mock-io, fixtures, the harness | `${CLAUDE_PLUGIN_ROOT}/reference/testing.md` |
| CI gates, base branch, version gate | `${CLAUDE_PLUGIN_ROOT}/reference/ci.md` |
| Sensitive data, merge authorization | `${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md` |
