---
name: e2e
description: Use when the user asks for a Desktop end-to-end or Playwright test of an ecoscope workflow, or to prove the workflow in the real app — "add an E2E test for X", "does it run in Ecoscope Desktop", "check the form submits and the dashboard renders", "the Desktop run says Success but shows nothing" — and when develop or publish proposes proving Desktop behaviour before a release. Covers the org's Playwright suite for Ecoscope Desktop (a CDP-attached Electron app) and the on-disk run contract it asserts against. Does not fire for the workflow's own mock or live test cases (develop) or for the web-app suite.
---

# Prove an ecoscope workflow in Ecoscope Desktop

A committed Playwright test that opens the template, fills the form from a known case, runs it,
and asserts the run produced a dashboard — in the org's e2e repo, against the real app. The
mechanics live in `${CLAUDE_PLUGIN_ROOT}/reference/desktop-e2e.md`; read it before § 2. This
skill is the procedure and its stops.

## Contents

0. Locate the suite and the app
1. Design — then approval
2. Scaffold, then fill
3. Run and assert
4. Debug a red run
5. Commit and hand back
6. Hard rules
7. Handoffs

## 0. Locate the suite and the app

**Environment: any shell.** Three things are needed, and none is assumed:

1. **The e2e repo** — Playwright + TypeScript, `tests/desktop-tests/`, page objects under
   `pom/`, `playwright.desktop.config.ts` (`desktop-e2e.md` § The suite). It is a sibling
   checkout whose location only the user knows: if the conversation has not named it, ask once —
   "where is your checkout of the ecoscope-ui-e2e-tests repo?" — and offer to record it in the
   user's own config for next time. Never guess a path. There: `git status` clean, a topic
   branch off `main`, `node_modules/` present (`yarn`; `yarn playwright install --with-deps
   chromium` once).
2. **The app** — Ecoscope Desktop installed and launched with the CDP flag, and the port
   listening (`desktop-e2e.md` § Setup footguns).
3. **The template and the connection** — the workflow's tile in Workflow Templates (which one is
   § 1's decision), initialised, and the data source the case needs under Data Sources.

Whatever is missing goes into § 1's proposal as a precondition the user performs by hand. The
test can be written without any of it; it is run only when all three hold (§ 6).

## 1. Design — then approval

**Environment: the workflow repo and the e2e repo, read-only.** Read the workflow's
`test-cases.yaml` (`base` is the form-default submission; a live case names the connection),
the compiled `rjsf.json` (the cards and fields you will drive — array-with-Add, oneOf rows,
checkboxes, accordions all have their own driving rule), `layout.json` and the spec's widget
tasks (the tiles you will assert), and the closest existing test in
`tests/desktop-tests/my-workflows/` (same tile kind, same card kinds). Then propose, opening with
one line stating the job — "E2E for `patrol-chart`: GitHub tile, `base` values, assert Success +
one chart tile":

| Item | Proposal |
|---|---|
| Tile | the GitHub-URL tile (`Source code: <url>`) proves the **published** artifact on the default branch; the local-folder tile proves the working copy — pre-publish work needs the local tile, imported by hand once (`desktop-e2e.md` § Import strategies). Say which and why. |
| Import | the tile is already in the library (default), or the test imports the GitHub URL itself through the page object when it is absent; after a pin or lock change the user deletes the old tile and re-imports before the run. |
| Case | `base` first, always — the form-default submission; further cases are proposed only after the base test is green (§ 3), one test per case. |
| Data source and time range | **the user's decision, asked explicitly**: a mock case's connection and slugs (`er_asia`, `demo_patrol`) are fixture names, not live values, and a real connection may not hold what the case needs (the patrol types, the dates, a feature group). Propose a connection name and window taken from a live case when the repo has one, else from the sibling tests; say what the run needs to find there; put the type filters to the user too (empty = all, or a slug they confirm exists); wait for the answer — never assume. Org connection names are fine to commit; passwords never. |
| Fields | each card you will drive and how, from the compiled form; which stay at their defaults — and are *asserted* at their defaults where the run depends on them. |
| Assertions | submit toast → row → Run → `Success`; the run on disk: `result.json` with `error == null` and non-empty `views`, because a green run with zero widgets is a failure (`${CLAUDE_PLUGIN_ROOT}/reference/preview-dashboard.md` § On-disk contract) — skipped with a log line on a runner that cannot see the app's data dir; the dashboard, always: open the row, the results navbar renders, every expected widget tile is present and its spinner clears (`desktop-e2e.md` § Submit, run, assert). Name the widget titles. |
| App data dir | resolved per platform at runtime by the helper in `desktop-e2e.md` § App data dir — never a literal path. |
| File, name, branch | `tests/desktop-tests/my-workflows/<workflow>[-github]-workflow.pw.test.ts`, the test title, the topic branch (or the caller's), a per-run unique workflow name. |
| Preconditions for the user | the hand steps from § 0 that are not yet true. |

**Stop and wait for approval** — of the design as a whole, and of the data source and time
range in particular. After it, §§ 2–5 run without check-ins; come back for a hang you cannot
explain (§ 4), a red run that is the workflow's fault, a missing precondition, or to propose the
next case once `base` is green.

## 2. Scaffold, then fill

**Environment: the e2e repo, with the app running.** Never guess test-ids: write the throwaway
scaffold from `desktop-e2e.md` § Scaffold-then-fill loop — it opens the form and dumps every
`data-testid` plus a screenshot — then author the fill from that dump, one rule per field kind from § Field-driving rules —
accordions expanded first, **Time Range and Data Source last**, Tab to commit array values,
filter-then-click for the timezone. Reuse the page objects (`my-workflows-page` for run and
verify, `workflow-templates-page` for navigation and import) rather than re-deriving them.
Delete the scaffold before committing.

Without the app (§ 0 not met) there is no scaffold: write the fill from § Field-driving rules
and the page objects, mark every id you could not see in the file's header comment, time-bound
each of those interactions (`{ timeout: 15000 }`) so a wrong id fails in seconds, and call the
test a draft in the report — § 3's run, when the preconditions hold, is its verification.

## 3. Run and assert

**Environment: the e2e repo; `NO_PROXY` set when a local proxy exists.** One test, no retries,
output to a file (the command and its flags: `desktop-e2e.md` § The suite):

```bash
NO_PROXY="localhost,127.0.0.1" yarn playwright test --config=playwright.desktop.config.ts \
    tests/desktop-tests/my-workflows/<file> --reporter=list --retries=0 > e2e-<workflow>.log 2>&1; echo exit=$?
```

Read the log whole. Green means every assertion from § 1's row held — status, on-disk result,
rendered tiles — not that Playwright exited 0 on a status check alone. **Base first**: the base
test is green before any other case is authored; each further case is its own test and its own
approved item, and inherits the base test's proven fill. Between runs reset the
app's route rather than clicking through a stale page (`desktop-e2e.md` § Setup footguns);
heavily grouped runs get a larger success-wait, not a "flaky" label (§ Submit, run, assert).

## 4. Debug a red run

`desktop-e2e.md` § Debugging a failed run. A silent hang is a collapsed accordion or a hidden
widget; a suspiciously fast Success is the wrong data source (reset by an accordion expand); a
value that vanished is a missing key in the run's `metadata.json` `config` (flat task ids). A
failure inside the workflow (`latest_run.error`) belongs to `/ecoscope:develop` — report the
trace; do not patch the test around it.

## 5. Commit and hand back

`yarn lint && yarn format` (the repo's pre-commit hook runs both over the whole suite — allow
minutes, not the default two; `yarn format:fix` repairs), then `test: <workflow> Desktop e2e
(<tile>, <case>)` on the topic branch. Report the file, the
exact command that ran it, what it asserted, the run time, and the preconditions another machine
or CI needs. The PR is the caller's — `/pr` when it is available; never push unasked. Hand back
to whichever skill called you.

## 6. Hard rules

Each has its mechanism in the linked file; they are prohibitions here because they get broken
under pressure ("the other tests do it", "it only needs the path on this Mac").

- Never commit a real credential or real data: passwords come from `ER_PASSWORD` /
  `SMART_PASSWORD` in the environment (`desktop-e2e.md` § The suite); screenshots and fixtures of
  real patrols stay out (`${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md` § Sensitive data).
- Never write a literal app-data path — not `Library/Application Support/…`, not `%APPDATA%` —
  the dir is resolved per platform at runtime (`desktop-e2e.md` § App data dir); the older tests
  in the suite that hardcode the macOS path are not the model.
- Never run the test unless the app is listening on CDP, the tile is imported and initialised,
  and the connection exists; otherwise stop before running and say exactly what is missing.
  Never launch the app, delete a tile or workflow, or edit or delete an existing data source
  (the suite's create-if-missing page object, fed from `ER_PASSWORD`, is the one sanctioned
  way to add one).
- Never assert `Success` alone: a run with zero outputs reads as a pass
  (`preview-dashboard.md`, `${CLAUDE_PLUGIN_ROOT}/reference/testing.md`).
- Never choose the data source or the time range yourself — proposed in § 1, decided by the
  user; real data decides whether a case can run at all.
- Never pick the timezone or a select by "first option", never index selects by position, never
  swallow a hang with `.catch()` — each mechanism is in `desktop-e2e.md` § Field-driving rules.
- Never pipe the Playwright run through `tail` or `head`; file plus exit code
  (`${CLAUDE_PLUGIN_ROOT}/reference/environments.md`).

## 7. Handoffs

Offer each when it becomes relevant, and wait for a yes; never start one unasked.

| When | Offer |
|---|---|
| The run fails inside the workflow, or the form cannot be driven to the case (a value the form drops on submit) | `/ecoscope:develop` |
| Called from a release | back to `/ecoscope:publish` with green or red and the file |
| Called from develop's verification | back to `/ecoscope:develop` |
| The test is committed on its branch | `/pr` in the e2e repo |

Close every session by naming what comes next. Do not start it.
