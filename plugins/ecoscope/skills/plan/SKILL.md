---
name: plan
description: Use before designing when the user wants a new ecoscope workflow ("plan / spec out / write a PRD for a workflow that …") or a big multi-session improvement — a new data source, a new widget chain, a rename or migration, "rework the X workflow" — or when develop's planning offer is accepted. Produces the PRD (.scratch/prd.md) develop builds from and, for multi-session work only, .scratch/progress.yaml. Not for small changes (develop), for building or compiling anything, or for mechanism questions (reference).
---

# Plan an ecoscope workflow (PRD)

Answer, before anything is built, the questions `develop`'s design will ask — and write the
answers down where `develop` reads them. The PRD is a set of decisions, not a spec draft;
`develop` turns it into `spec.yaml`, cases and `layout.json`.

## Contents

0. Where the PRD lives
1. Research first
2. Ask — one batch, a default per question
3. Write the PRD
4. Approval, then hand to develop
5. `progress.yaml` — only when the work spans sessions
6. Hard rules
7. Handoffs

## 0. Where the PRD lives

**Environment: any shell.** Planning artifacts live in the workflow repo's `.scratch/` and
nowhere else (`${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md` § `.scratch/` planning
artifacts). Before writing there:

- **Improvement** — the repo exists: `git check-ignore -q .scratch || echo MISSING`. When
  missing, add `.scratch` to `.gitignore` first (a third of fleet repos lack the entry) and
  commit that line on its own; then `mkdir -p .scratch`.
- **New workflow** — there is no repo yet. Propose the repo name in § 2 and create only its
  directory with `.scratch/` inside: the directory the user is running from if it is empty
  (whatever it is called — the PRD's **Name** is the repo name; renaming the directory is the
  user's call, noted in the handoff) or already the new repo, otherwise a sibling of their
  existing workflow repos — ask once where those live; never assume a layout. Nothing is under git yet, so nothing can leak; the
  scaffold's `.gitignore` carries `.scratch` (`repo-layout.md` § Repo anatomy) and `develop`
  checks it before its first commit. One trap to write into the PRD's handoff:
  `wt-compiler scaffold init` creates `<output-dir>/<id>/` and its `--clobber` **overwrites**
  an existing directory — the scaffold must run into a temporary parent and its files move
  into the repo directory, never `--clobber` over the PRD.

If `.scratch/prd.md` or `.scratch/progress.yaml` already exists, read it first: this is a
revision, and the PRD's decisions log (§ 3) records what changes.

## 1. Research first

**Environment: read-only; the inner pixi env only to run the existing base case.** Ask the
user nothing until this is done — most questions answer themselves here, and the rest get a
proposed default.

- **Improvement**: read `spec.yaml`, `test-cases.yaml`, `layout.json`, the compiled
  `rjsf.json` and the root `README.md`, and run the existing `base` mock case
  (`${CLAUDE_PLUGIN_ROOT}/reference/testing.md` § `dev/run-test-cases.sh`) so the current
  form and dashboard are in front of you. The PRD then names real cards, fields and widget ids
  and what changes.
- **Reference workflows**: find the nearest fleet workflow(s) — the user's existing repos for
  the same data kind (patrols, events, subjects) and output kind (map, chart, table,
  download) — and read their `spec.yaml`, cases and `layout.json`; they are proposed in § 2
  and the user confirms or adds. The shapes to plan against:
  `${CLAUDE_PLUGIN_ROOT}/reference/patterns.md` (pipeline skeleton, grouping, widget chains,
  dashboard assembly).
- **Tasks**: for each thing the workflow must do, find the task and read its signature
  (`${CLAUDE_PLUGIN_ROOT}/reference/task-discovery.md` § Finding an existing task — quick
  path), and confirm every name in the registry: the inner env of the repo for an improvement; with
  no repo, a compiled sibling's inner env whose pins match the ones the PRD proposes, and the
  `pixi exec` throwaway env only when no sibling has one (same file, § Ask the registry).
  A name the registry lists twice goes into the PRD fully qualified. What no task does becomes
  a **task contract** (§ 3).
- **Data**: what the connection provides and needs (`${CLAUDE_PLUGIN_ROOT}/reference/connections.md`),
  and what the packaged mock fixtures already carry for the io tasks in play (`testing.md`
  § How mock-io works). **Then pull the sample** — planning is where the data model gets
  settled, so the pull happens here, not in `develop`: discovery first (types, detail-schema
  keys, counts per month → the range), then the parquets, all under gitignored `.scratch/`
  and nowhere else (`testing.md` § Pulling a sample; `${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md`).
  The connection name and its credentials are the user's: ask for them once if the
  `ECOSCOPE_WORKFLOWS__CONNECTIONS__…` variables are not in the shell. When they cannot be
  had, or the pull may not run in this session, leave the pull script under `.scratch/`, plan
  on the packaged fixtures and say so in the PRD — `develop` runs the pull first.

## 2. Ask — one batch, a default per question

Ask everything below **in one message**, each question with the default research gave you,
so the user corrects rather than answers from scratch. A second round only where an answer
opens a real choice (a data source you have not read, a widget kind that changes the chain).
Never one question at a time.

| Question | Settle |
|---|---|
| Outcome and reader | the question the dashboard answers; who reads it (ranger, manager, donor) |
| Name | repo name and workflow `id` (a Python identifier, short; no `-report` / `-dashboard` suffixes) |
| Reference workflows | the ones § 1 found, to model on — confirm, add, or replace |
| Data source | connection kind and the connection name to default to; time-range default; what is fetched (subject group / patrol types / event types) and filtered |
| **Data model and fixtures** | what § 1's discovery and sample showed — the event / patrol types, detail keys, geometry and grouper keys in play — against what the packaged mock data carries; which widgets need a synthetic fixture built from the sample's model (`testing.md` § Generating mock data) and which run on the packaged fixtures |
| **Config form, card by card** | for each card: title, the fields the user sees with titles and defaults, what is fixed and hidden (`partial:`), what is advanced, dropdowns fed from the connection, conditional fields (`${CLAUDE_PLUGIN_ROOT}/reference/rjsf.md`, `${CLAUDE_PLUGIN_ROOT}/reference/rjsf-conditionals.md`) |
| **Dashboard** | the widgets (map / chart / table / text / stat) and what each shows; groupers, and the view fan-out the *fixture* will produce, keyed how; placement and sizes (`${CLAUDE_PLUGIN_ROOT}/reference/output-style.md`; `patterns.md` § Dashboard assembly) |
| Test cases | `base` plus per-grouper, toggles and the empty fixture (`testing.md` § Recommended case set); a live case only if asked |
| Task contracts | for each gap: name, library, inputs and types, output, io or not — the seam `/ecoscope:task` builds to |
| Deployment | Ecoscope Desktop only, or Web (decides `--variant=gcp` — `${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § `--variant=gcp`); catalog workflow or not (base branch `staging` vs `main` — `${CLAUDE_PLUGIN_ROOT}/reference/ci.md`) |
| Size | one session (the default for a new workflow whose widgets are all carried by registered tasks, however many), or several — decides § 5 |

## 3. Write the PRD

**Environment: the editor.** Write `.scratch/prd.md` as decisions `develop` can act on, in
this order. No `spec.yaml` draft and no task chains with `partial:` values — they go stale,
duplicate `spec.md`, and `develop` composes the chains from the tasks and reference workflows
named below with the reference files open. No mechanism restated: link the
reference file where a decision depends on one.

```markdown
---
title: <workflow title>
repo: <repo-name>          id: <workflow_id>
status: draft | approved
created: <YYYY-MM-DD>      updated: <YYYY-MM-DD>
data_sources: [<set_er_connection | set_smart_connection | set_gee_connection | file>]
reference_workflows: [<repo>, …]
---
## Outcome            — the question answered, the reader, in/out of scope
## Data               — connection, default connection name, time range, what is fetched, filters
## Data model         — what the sample in .scratch/ showed (types, keys, geometry, grouper keys; the range); per io task: packaged fixture | synthetic from the sample (what it must contain, per case)
## Config form        — one table per card: field · title · default · basic/advanced/hidden(partial) · source (task param / override)
## Dashboard          — widget table: id · kind · shows · grouped by · fan-out on the fixture · layout slot
## Tasks              — per widget, the registered tasks that carry it (names confirmed in the registry, qualified on
                        collision) and the reference workflow whose chain it follows; the wiring is develop's
## Test cases         — name · mock_io · what it proves · params that differ from base · fixture
## Task contracts     — per gap: name · library · inputs (typed) · output · io? · nearest existing task
## Deployment         — Desktop/Web, variant, base branch, secrets the live case needs
## Acceptance         — 3–6 Given/When/Then lines: base run renders every widget; each grouper fans out; form defaults produce a valid run; empty fixture completes
## Decisions          — dated log: what the user chose at approval and in later revisions
```

Before presenting, check the PRD against itself:

- every task name in **Tasks** was confirmed in the registry (§ 1), and a colliding one is
  qualified;
- every widget has a layout slot, a case that renders it, and its tasks end in
  `gather_dashboard` (or `gather_output_files` for a download workflow — `tasks.md` § The
  tasks nearly every workflow uses);
- every card lists its fields with defaults;
- the fan-out is stated against the fixture the mock run will use, not the theoretical set;
- the io tasks' fixtures are named — packaged, or synthetic built from the sample, never a
  real pull; the sample and the discovery output
  are under `.scratch/` and referenced from **Data model** by path (`process-rules.md`);
- each task contract has all five fields.

## 4. Approval, then hand to develop

Present a summary — widgets, cards, cases, task contracts, the assumptions you made where a
default stood in for an answer — and **stop for approval**; iterate until the user is
satisfied. On approval set `status: approved` and the date in the frontmatter, log the
decisions, and hand to `/ecoscope:develop`: it reads the PRD as the input to its design
step, and routes each task contract through `/ecoscope:task` before wiring (tasks first).
For a new workflow, repeat the scaffold trap from § 0 in the handoff. Nothing is scaffolded,
written to `spec.yaml`, or compiled here.

## 5. `progress.yaml` — only when the work spans sessions

Write `.scratch/progress.yaml` when the answer to **Size** was "several": a task contract that
must be built and released before the workflow can finish, a data source swap or migration, or
the user saying so. Skip it otherwise — a new workflow whose widgets are all carried by
registered tasks is one session however many widgets it has, and carries its plan in the PRD;
a sample pull still to run is `develop`'s first step, not a session boundary.

It is a **milestone plan `develop` reads when it starts and updates when a milestone is
reached** — not a state machine serviced per step (`repo-layout.md` § `.scratch/`). Shape:

```yaml
phase: new              # new | develop | publish — the lane the work is in
status: in-progress     # in-progress | blocked | completed
lastUpdated: 'YYYY-MM-DD'
notes: >
  One paragraph: the branch, the gate being waited on (a library release, a secret, a
  review), and decisions that changed since the PRD.
milestones:             # dependency order; one line each; no per-step entries
  - {name: "task <name>: PR open, release pending", status: pending}
  - {name: "<widget chain>: base case green, accuracy checked", status: pending}
  - {name: "form and dashboard verified by a human", status: pending}
  - {name: "publish", status: pending}
```

Older fleet files split the list into `setup:` / `tasks:` / `wrapup:`; read them the same way
— named items with a status — and do not convert them.

## 6. Hard rules

Standing prohibitions: `${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md` (real data pulls go
under gitignored `.scratch/` and nowhere else; fixtures are synthetic). Specific to this skill,
because they get broken under pressure ("I'll just scaffold it while I'm here"):

- Never start building — no scaffold, no `spec.yaml`, no compile, no test case. The PRD ends
  with approval and a handoff (§ 4).
- Never write a planning artifact outside `.scratch/`, and never before `.scratch` is
  gitignored (§ 0, `repo-layout.md`).
- Never put a task name in the PRD that the registry has not confirmed, and never a bare
  name the registry lists twice (`task-discovery.md`).
- Never ask one question at a time, and never ask what § 1's research answers.

## 7. Handoffs

Offer each when it becomes relevant, and wait for a yes; never start one unasked.

| When | Offer |
|---|---|
| The PRD is approved | `/ecoscope:develop` — design and build from `.scratch/prd.md` |
| A task contract is in the PRD | `/ecoscope:task` — reached through `develop`'s tasks-first path, not directly from here |
| The request was really a small change | `/ecoscope:develop` — no PRD needed; say why |

Close every session by naming what comes next, without starting it.
