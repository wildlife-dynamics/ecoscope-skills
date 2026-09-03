---
name: develop
description: Use when the user asks to build, change, extend, or fix an ecoscope workflow — a new workflow from a description, a spec.yaml / config-form / dashboard-layout / test-case edit, "recompile and re-run the tests" — or whenever the work happens inside a workflow repo (spec.yaml + test-cases.yaml + layout.json + a generated *-workflow/ package). Not for pure syntax or mechanism questions with no edit in play (reference) or for releasing (publish).
---

# Develop an ecoscope workflow

Design it with the user, build it, prove it, hand it over. The config form and the dashboard
are the product — requirements to agree on up front and to have a human sign off at the end.

## Contents

0. Preflight
1. Design — always, then approval
2. Implement (tasks first when needed)
3. Compile→test loop
4. Verify — yours, then the user's
5. Hard rules
6. Handoffs

## 0. Preflight

**Environment: any shell, from the workflow repo.** For a new workflow run it once the
scaffold exists, before the first compile. Run `${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh`
(what it probes: `${CLAUDE_PLUGIN_ROOT}/reference/environments.md` § Preflight) and run the
repair command each `FAIL` carries before compiling. A WARN that the repo's compiler pin
differs from the global compiler is a routing decision, not noise: on that repo, compile
through the outer pixi env — the pixi-prefixed dev form in `compile.md` § Canonical commands,
which also carries the why. Environments and standing rules: `environments.md`.

## 1. Design — always, then approval

Every job gets a design, including "hide that field". Open with one line stating your reading
of the job, and route two of the three:

- **New workflow, no repo** — offer `/ecoscope:plan` to write the PRD (`.scratch/prd.md`), then
  come back here and design the build from it. Check `.scratch` is gitignored first.
  `wt-compiler scaffold init` writes `spec.yaml`, `test-cases.yaml`, CI and a README only: copy
  `dev/run-test-cases.sh` and the outer `pixi.toml` from the hub template or a synced sibling
  repo before the first test, and write `layout.json` yourself — never hand-roll the harness
  (`${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md` § Vendored files).
- **Publish / release** — hand to `/ecoscope:publish`; it owns the CI-matching recompile,
  pins, lock/VERSION and the PR.
- **Improve an existing workflow** — continue. A big improvement (a new widget chain, a new
  data source, a rename, anything that will span sessions) also deserves the offer of
  `/ecoscope:plan` and a `.scratch/progress.yaml`. If the reading is genuinely unclear ("get
  event-sum-map ready" — improve or publish?), ask.

**Research before proposing.** Read `spec.yaml`, `test-cases.yaml`, `layout.json`, the
compiled `rjsf.json`, and run the existing `base` mock case (§ 3 test command — on a fresh tree
this installs the inner env first, and an editable tree needs `--frozen`) so you have the
current form and dashboard in front of you. When the change adds or removes a data source, also
run `python -m <pkg>.cli get data-connection-property-names` in the inner env — Desktop prompts
for exactly the connections that list names, so it is part of the before/after. Any fixture
inspection for the fan-out or the data model runs in the inner pixi env, as in § 4. The proposal then names real cards, fields, widget
ids and what changes. If what was asked for is already in the spec, say so and propose what is
actually missing (a case, an override, a fixture). Ask for the user's opinion up front only
where the request leaves a real choice.

Settle these, in one batch of questions with a proposed default for each. With an approved
PRD from `/ecoscope:plan`, they are already answered — confirm the deltas instead of
re-asking:

| Requirement | What to settle |
|---|---|
| Outcome | the question the dashboard answers; who reads it |
| Reference workflows | which existing workflows to model on — the nearest by data kind (patrols, events, subjects) and output kind; propose them from the user's repos and ask; their `spec.yaml`, cases and `layout.json` are the shapes you copy |
| Data | connection / data source, time range, what is fetched (patrols, events, subjects …), filters |
| **Data model** | does the change need data the packaged mock fixtures don't carry (new event/patrol types, detail keys, geometry, a grouper key)? If yes: the sample `/ecoscope:plan` pulled into `.scratch/`, or pull one now, then a synthetic fixture from that model (`${CLAUDE_PLUGIN_ROOT}/reference/testing.md` § Pulling a sample, § Generating mock data). If no: the packaged mock data. No credentials: model the synthetic fixture on the packaged one and say so. |
| **Config form** | the cards the user sees and their order; the fields in each, titles and defaults; what is fixed and hidden (`partial:`); dropdowns fed from the connection; conditional fields |
| **Dashboard** | widgets (map / chart / table / text) and what each shows; groupers → how many views and keyed how — the fan-out the *mock fixture* will actually produce, not the theoretical set; `layout.json` placement and sizes |
| Tests | mock cases to add or change (`base`, per-grouper, toggles, empty fixture); a live case only if asked |
| **Tasks** | which registered tasks carry it — `${CLAUDE_PLUGIN_ROOT}/reference/task-discovery.md` quick path (find, read the signature, confirm in the registry the spec pins). A task that is missing or needs changing goes into the design as a **task contract**: name, library, inputs and their types, output, whether it is an io task — the seam `/ecoscope:task` builds to (§ 2). |

Then propose, concretely: the `spec.yaml` edits (tasks, `partial:` bindings, groups,
overrides), the test cases and fixtures, the `layout.json` changes, the branch
(`develop/<topic>` off the base branch — `${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md`),
the task contracts if any and that you will wire the local library in editable mode while they
are unreleased, and how you will verify it (§ 4).

**Stop and wait for approval.** After approval, §§ 2–4 run without further check-ins, per the
user's global workflow; come back only for a task hand-off (§ 2), the human verification in
§ 4, or a halt in § 3.

## 2. Implement

**Environment: the editor; no compile yet.** Name the reference file you are working from.

**Tasks first.** If the approved design carries a task contract, hand off to `/ecoscope:task`
with that contract and stop; it authors, registers, re-exports and tests the task in the
library repo, and hands back the editable requirement to wire, with its rules (`/ecoscope:task`
§ 6; `${CLAUDE_PLUGIN_ROOT}/reference/spec.md` § Editable): first compile `--clobber
--install`, `./dev/postcompile-editable.sh` after every compile, test with `--frozen`, commit
the inner lock while the tree is editable. Reverting to released pins when the library ships
is `/ecoscope:publish`'s job; CI rejects `path:`.

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
  shape: `${CLAUDE_PLUGIN_ROOT}/reference/rjsf-conditionals.md`. The words themselves — one
  string per card stack, short titles, descriptions that add something, shared compiler cards
  untouched: `${CLAUDE_PLUGIN_ROOT}/reference/rjsf-style.md`.
- **Dashboard** — widget styling defaults and `layout.json` sizing/placement:
  `${CLAUDE_PLUGIN_ROOT}/reference/output-style.md`; the "Edit Layout" predicate and grouped
  views: `${CLAUDE_PLUGIN_ROOT}/reference/patterns.md` § Dashboard assembly.
- **Tests and fixtures** — the recommended case set and the gotchas (naive datetimes,
  `TimezoneInfo`, `SpatialGrouperTest` for spatial mock cases, a `partial:`-bound param must
  leave the cases); synthetic fixtures from a committed `dev/fixtures/build_*.py`, real data
  never: `${CLAUDE_PLUGIN_ROOT}/reference/testing.md`,
  `${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md`.

## 3. Compile→test loop

**Compile — environment: the global `wt-compiler`, from the repo root.** This is the dev
compile; the CI-matching publish compile belongs to `/ecoscope:publish`. The command, the
append rule for the trailing flag (`--install` / `--update` / none — and which restores the
committed inner lock), and the pinned-compiler prefix are in
`${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § Canonical commands; when preflight WARNed on
the compiler pin (§ 0), the pixi-prefixed form is the one to run. Compile only when
`spec.yaml` changed; a `test-cases.yaml` / `layout.json` / fixture edit goes straight to the
test step. A `requirements:` bump is its own change with its own checklist (`spec.md`
§ Bumping library pins): confirm every task the spec names still exists at the target
version, then after the compile re-check the card list — new task params leak as extra cards
until bound with `partial:`.

A compile without `--update` resets `VERSION.yaml` to 0.0.0 and drops the gcp variant —
expected in the improve loop; `/ecoscope:publish` restores both and recompiles the CI way
(compile.md § `--update` semantics). Never `--variant=gcp` here. Before running `--clobber`
know the restore path: `git checkout <base> -- <WF>/` (compile.md § Restore playbook). Run
the compile bare or `> compile.log 2>&1` and read the whole file; on failure match
compile.md § Common compile errors, fix, recompile.

**Test — environment: the inner pixi env, only through the harness.** Mock cases first; the
full run comes after § 4's checks pass.

```bash
./dev/run-test-cases.sh --case <name>     # the mock case(s) the change touches, while iterating
./dev/run-test-cases.sh --all             # the full set incl. live cases — after § 4, before the commit
```

`--frozen` when git-tag or editable `path:` requirements are present (compile.md
§ Compile-time standing rules). Live cases need the connection env vars in your shell
(`${CLAUDE_PLUGIN_ROOT}/reference/connections.md`); when they are not set, run every mock case
and report the live ones as CI's. Pass = `result.json` present, `.error == null`, exit 0 —
necessary, not sufficient (§ 4). Failure classes:
`${CLAUDE_PLUGIN_ROOT}/reference/testing.md`.

**Loop** edit → compile → mock cases until green → § 4 your checks → `--all` → **commit on
green**, one commit per green cycle (`feat:` / `fix:` / `test:`), `spec.yaml` + cases +
fixtures + `layout.json` + the regenerated `<WF>/` tree together. An unrun case or a red
compile is not a step's end.

**Halt** and report when the same error survives three consecutive fixes, when the error is
inside a task (offer `/ecoscope:task`), or when a `--clobber` failure gutted the tree and the
restore path does not apply cleanly.

## 4. Verify — yours, then the user's

**Yours, on the mock runs, before the full run and before asking anyone** (environment: the
repo for files; the inner pixi env for any recomputation):

- **Shape** — every case produced its widgets: files exist and are non-trivial; chart traces /
  map layers carry data; the view keys match the fan-out designed in § 1; `layout.json`
  references the widget ids the run produced.
- **Form** — the compiled `rjsf.json` shows the agreed cards, in order, with the agreed field
  titles and defaults, and the `partial:`-bound params are gone (`yq -p json '.properties |
  keys'`); `skills/guide/scripts/form-inventory.py rjsf.json` shows no string twice in any
  card's stack and the copy passes the `rjsf-style.md` checklist.
- **Accuracy** — recompute the expected numbers independently from the same fixture the mock
  returns (load it in the inner env with pandas/geopandas: counts per bucket, totals, group
  keys, feature counts and bounds for maps, row counts for tables) and compare with what the
  widget renders — chart traces from the HTML; for maps whose data is embedded as binary
  (lonboard), the view keys, legend titles, feature counts and bounds. A plausible-looking chart
  built on the wrong column is the failure this catches.

Then the full `--all` run and the commit (§ 3). **Then ask for human verification** — the form
and the dashboard are the deliverable and only a person can judge them. Give the user a ready
prompt, filled in:

> Please check `<workflow>` in Ecoscope Desktop. Preview from the `<case>` run per
> `${CLAUDE_PLUGIN_ROOT}/reference/preview-dashboard.md` (copy the run dir into the app data
> dir, relaunch), or import the template and run it against `<connection>` (or the packaged
> mock data, when every case is mock).
> **Form:** cards `<list>` in this order; `<field>` defaults to `<value>`; `<hidden param>`
> is no longer shown; `<dropdown>` lists your `<event types / feature groups>`.
> **Dashboard:** `<widget>` shows `<what>` (`<the numbers I verified>`); grouping by
> `<grouper>` gives one view per `<key>`; tiles sit at `<layout summary>`.
> Tell me what looks wrong or missing and I'll fix it.

Fix what comes back through § 3, re-verify, re-ask. Only a "looks good" closes the job.

## 5. Hard rules

The standing prohibitions live in `${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md` (real
data never committed — a pulled sample stays in `.scratch/`, fixtures are synthetic from a
committed script; merge/tag/push and `gh secret set` need an explicit go-ahead) and
`${CLAUDE_PLUGIN_ROOT}/reference/environments.md` (never `conda activate` or bare `python`;
never pipe `wt-compiler`, `pixi` or the harness through `tail`/`head`/`grep -v` — redirect to
a file, record the exit code, read the file). Specific to this skill:

- Never `--clobber` without knowing the restore path (`compile.md` § Restore playbook).

## 6. Handoffs

Offer each when it becomes relevant, and wait for a yes; never start one unasked.

| When | Offer |
|---|---|
| New workflow, or a big improvement, before designing | `/ecoscope:plan` — the PRD and `.scratch/progress.yaml` |
| The approved design carries a task contract, or a task turns out broken | `/ecoscope:task` — build to the contract; then back here with the editable pin |
| A new workflow, or a user-visible option changed | `/ecoscope:guide` — the README for non-technical users |
| Desktop behaviour must be proven end to end | `/ecoscope:e2e` |
| Human verification passed and the change is complete | `/ecoscope:review` — verified passes plus the human checklist, **before** publish |
| The user wants it released | `/ecoscope:publish` |

Close every session by naming what comes next, without starting it.
