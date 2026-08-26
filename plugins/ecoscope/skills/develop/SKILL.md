---
name: develop
description: Use when the user asks to develop, build, create, implement, add to, change, extend, or fix an ecoscope workflow — a new workflow from a description, a spec.yaml edit (new task, widget, grouper, filter, column, default, card), a config-form or dashboard-layout change, a failing or missing test case, "recompile and re-run the tests" — or whenever the work happens inside a workflow repo (spec.yaml + test-cases.yaml + layout.json + a generated *-workflow/ package). Triggers on both "make me a workflow that …" and "I edited spec.yaml, can you compile and test". Does not fire for pure questions about syntax or mechanism with no edit in play (the reference skill) or for "publish/release the workflow" (publish).
---

# Develop an ecoscope workflow

Design it with the user, build it, prove it, hand it over. The config form and the dashboard
are the product — they are requirements to agree on up front and to have a human sign off at
the end, not polish. Every fact lives in `${CLAUDE_PLUGIN_ROOT}/reference/` and is linked at
the point of use; nothing is restated here.

## Contents

0. Preflight
1. Design — always, then approval
2. Implement
3. Compile→test loop
4. Verify — yours, then the user's
5. Hard rules
6. Handoffs

## 0. Preflight

**Environment: any shell.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh`. It reports —
never repairs — whether the global compiler runs and imports `jsonschema`, graphviz renders,
`yq` is go-yq, and pixi is present; each `FAIL` carries its repair command. Run the repairs
before compiling. Environments and standing rules:
`${CLAUDE_PLUGIN_ROOT}/reference/environments.md`.

## 1. Design — always, then approval

Every job gets a design, including "hide that field". Open with one line that states your
reading of the job, and route two of the three:

- **New workflow, no repo** ("develop a workflow that …" with no `spec.yaml` around) — offer
  `/ecoscope:plan` to write the PRD (`.scratch/prd.md`), then come back here and design the
  build from it. Check `.scratch` is gitignored before anything is written there.
- **Publish / release** — hand to `/ecoscope:publish`; it owns the CI-matching recompile,
  pins, lock/VERSION and the PR.
- **Improve an existing workflow** — continue below. If the reading is genuinely unclear
  ("get event-sum-map ready" — improve or publish?), ask.

Then gather what the request leaves open. Ask the questions in one batch, with a proposed
default for each so the user can just say "yes":

| Requirement | What to settle |
|---|---|
| Outcome | the question the dashboard answers; who reads it |
| Data | connection / data source, time range, what is fetched (patrols, events, subjects …), filters |
| **Config form** | the cards the user sees and their order; the fields in each, their titles and defaults; what is fixed and hidden (`partial:`); dropdowns fed from the connection; conditional fields |
| **Dashboard** | widgets (map / chart / table / text) and what each shows; groupers → how many views and keyed how; `layout.json` placement and sizes |
| Tests | mock cases to add or change (`base`, per-grouper, toggles, empty fixture); a live case only if asked |
| Tasks | which registered tasks carry it — `${CLAUDE_PLUGIN_ROOT}/reference/task-discovery.md` quick path (find, read the signature, confirm in the registry the spec pins). None suitable → `/ecoscope:task` |

Read the current `spec.yaml`, `test-cases.yaml`, `layout.json` and the compiled `rjsf.json`
first so the proposal names real cards, fields and ids. Then propose, concretely: the
`spec.yaml` edits (tasks, `partial:` bindings, groups, overrides), the test cases, the
`layout.json` changes, the branch (`develop/<topic>` off the base branch —
`${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md`), and how you will verify it (§ 4).

**Stop and wait for approval.** After approval, §§ 2–4 run without further check-ins, per the
user's global workflow; come back only for the human verification in § 4 or a halt in § 3.

## 2. Implement

**Environment: the editor; no compile yet.** Name the reference file you are working from.

- **Spec** — syntax, validation rules, `requirements:`, `skipif`:
  `${CLAUDE_PLUGIN_ROOT}/reference/spec.md`. Shapes to copy — pipeline skeleton, grouping and
  the spatial-grouper resolver chain, widget chains, dashboard assembly, `groupbykey`:
  `${CLAUDE_PLUGIN_ROOT}/reference/patterns.md`. The idiom: `partial:` fixes and hides; card
  order = task order; widget tasks carry `skipif: {conditions: [never]}`; glue tasks live
  outside groups; group titles are unique. Task-specific traps:
  `${CLAUDE_PLUGIN_ROOT}/reference/task-pitfalls.md`.
- **Form** — top-level `rjsf-overrides`, flat dotted paths from the exact card title, title
  hiding, field rendering rules, connection-fed dropdowns:
  `${CLAUDE_PLUGIN_ROOT}/reference/rjsf.md`. Reveal-on-check fields have exactly one working
  shape: `${CLAUDE_PLUGIN_ROOT}/reference/rjsf-conditionals.md`.
- **Dashboard** — widget styling defaults and `layout.json` sizing/placement:
  `${CLAUDE_PLUGIN_ROOT}/reference/output-style.md`; the "Edit Layout" predicate and grouped
  views: `${CLAUDE_PLUGIN_ROOT}/reference/patterns.md` § Dashboard assembly.
- **Tests** — the recommended case set and the gotchas (naive datetimes, `TimezoneInfo`,
  `SpatialGrouperTest` for spatial mock cases, a `partial:`-bound param must leave the cases):
  `${CLAUDE_PLUGIN_ROOT}/reference/testing.md`. Fixtures are synthetic
  (`${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md`).

## 3. Compile→test loop

**Compile — environment: the global `wt-compiler`, from the repo root.** This is the dev
compile; the CI-matching publish compile belongs to `/ecoscope:publish`. Command and flags are
copied from `${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § Canonical commands (that file wins
if they ever differ):

```bash
wt-compiler compile \
    --spec spec.yaml \
    --pkg-name-prefix=ecoscope-workflows \
    --results-env-var=ECOSCOPE_WORKFLOWS_RESULTS \
    --clobber --no-progress [--install | --update]
```

Compile only when `spec.yaml` changed; a `test-cases.yaml` / `layout.json` / fixture edit goes
straight to the test step. The trailing flag, because the test harness runs `pixi run --locked`
and a plain `--clobber` deletes the inner `pixi.lock`:

| Situation | Flag | Then |
|---|---|---|
| first compile (no inner lock) | `--install` | commit the lock with the tree |
| spec edit, `requirements:` untouched | none | `git checkout HEAD -- <WF>/pixi.lock` puts the committed lock back |
| `requirements:` changed, or no lock in git | `--update` | carries the lock and re-solves it; churn is expected |

A dev compile also resets `VERSION.yaml` to 0.0.0 — expected; `/ecoscope:publish` restores
VERSION and lock from base. Never `--variant=gcp` here. Editable/`path:` requirements need
`./dev/postcompile-editable.sh` after every compile (spec.md § Editable). Before running
`--clobber` know the restore path: `git checkout <base> -- <WF>/` (compile.md § Restore
playbook). Run the compile bare or `> compile.log 2>&1` and read the whole file; on failure
match compile.md § Common compile errors, fix, recompile.

**Test — environment: the inner pixi env, only through the harness.**

```bash
./dev/run-test-cases.sh --case <name>     # while iterating on one path
./dev/run-test-cases.sh --all             # before every commit
```

`--frozen` when git-tag requirements are present. Pass = `result.json` present, `.error ==
null`, exit 0 — then open the outputs (a green run with empty widgets is the silent-empty-run
trap). Failure classes: `${CLAUDE_PLUGIN_ROOT}/reference/testing.md`.

**Loop** edit → compile → test until green; **commit on green**, one commit per green cycle
(`feat:` / `fix:` / `test:`), `spec.yaml` + cases + `layout.json` + the regenerated `<WF>/`
tree together. An unrun case or a red compile is not a step's end.

**Halt** and report when the same error survives three consecutive fixes, when the error is
inside a task (offer `/ecoscope:task`), or when a `--clobber` failure gutted the tree and the
restore path does not apply cleanly.

## 4. Verify — yours, then the user's

**Yours, before asking anyone** (environment: the repo; results under the harness's temp dir):

- Every case produced its widgets — files exist and are non-trivial; chart traces / map layers
  carry data; the view keys match the groupers designed in § 1.
- The compiled `rjsf.json` shows the agreed cards, in order, with the agreed field titles and
  defaults, and the `partial:`-bound params are gone (`yq -p json '.properties | keys'`).
- `layout.json` references the widget ids the run produced.

**Then ask for human verification** — the form and the dashboard are the deliverable and only
a person can judge them. Give the user a ready prompt, filled in:

> Please check `<workflow>` in Ecoscope Desktop. Preview from the `<case>` run per
> `${CLAUDE_PLUGIN_ROOT}/reference/preview-dashboard.md` (copy the run dir into the app data
> dir, relaunch), or import the template and run it against `<connection>`.
> **Form:** cards `<list>` in this order; `<field>` defaults to `<value>`; `<hidden param>`
> is no longer shown; `<dropdown>` lists your `<event types / feature groups>`.
> **Dashboard:** `<widget>` shows `<what>`; grouping by `<grouper>` gives one view per
> `<key>`; tiles sit at `<layout summary>`.
> Tell me what looks wrong or missing and I'll fix it.

Fix what comes back through § 3, re-verify, re-ask. Only a "looks good" closes the job.

## 5. Hard rules

Each has its mechanism in the linked file; here they are prohibitions because they get broken
under pressure ("just a quick recompile", "the top is only pixi noise").

- Never pipe `wt-compiler`, `pixi`, or `dev/run-test-cases.sh` output through `tail`, `head`,
  or `grep -v` — it masks the exit code (`environments.md`). Redirect to a file, read the file.
- Never `--clobber` without knowing the restore path (`compile.md` § Restore playbook).
- Never merge, tag, or push a default branch, and never `gh secret set`, without an explicit
  go-ahead — "can we merge?" is a question (`process-rules.md`).
- Never commit real organisational data; fixtures are synthetic, from a committed script
  (`process-rules.md`, `testing.md`).
- Never `conda activate`, never bare `python` for a workflow run; every command names its
  environment (`environments.md`).

## 6. Handoffs

Offer each when it becomes relevant, and wait for a yes; never start one unasked.

| When | Offer |
|---|---|
| New workflow, before designing | `/ecoscope:plan` — the PRD |
| A needed task doesn't exist or is broken | `/ecoscope:task` — then back here with the new pin |
| A new workflow, or a user-visible option changed | `/ecoscope:guide` — the README for non-technical users |
| Desktop behaviour must be proven end to end | `/ecoscope:e2e` |
| Human verification passed and the change is complete | `/ecoscope:review` — verified passes plus the human checklist, **before** publish |
| The user wants it released | `/ecoscope:publish` |

Close every session by naming what comes next. Do not start it.
