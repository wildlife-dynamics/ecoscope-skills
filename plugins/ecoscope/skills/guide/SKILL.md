---
name: guide
description: Use when the user asks for a user guide, README, or end-user documentation for an ecoscope workflow, wants its form or dashboard explained for the people who run it, or asks whether the README still matches the workflow. Also fires from publish's guide gate or a develop handoff after a user-visible change. Not for developer documentation (the generated package's README, CLAUDE.md) or for changing the workflow itself.
---

# Write or refresh the user guide of an ecoscope workflow

The root `README.md` is what a non-technical user reads to install, configure and understand a
workflow in Ecoscope Desktop. Every sentence in it is derived from an artefact — the compiled
form, a real run, the cases — never from what the spec looks like it should do. Two modes, one
procedure: **write** (no README, or one without the eight sections) and **gate** (an existing
README checked against this release — the check `/ecoscope:publish` applies before it opens a
PR). Every fact lives in `${CLAUDE_PLUGIN_ROOT}/reference/` or in this skill's own files and is
linked at the point of use.

## Contents

0. Gather the artefacts
1. Inventory — the form and the widgets
2. Mode and proposal — then approval
3. Write, or update only what the gate lists
4. Verify against disk
5. Hard rules
6. Handoffs

## 0. Gather the artefacts

**Environment: the workflow repo; the inner pixi env only through the harness.** The README you
write is the root `README.md` beside `spec.yaml` — not `<WF>/README.md`, which the compiler
writes and overwrites (`${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md` § Repo anatomy). Read:

| Read | Take from it |
|---|---|
| `spec.yaml` | what the workflow does (the task chain: fetch → transform → widgets), which **data-source product** it connects to (the connection task — EarthRanger, SMART, Google Earth Engine …), the **analysis methods** its tasks apply (a home-range task's `bbmm`, a density kernel, a time-weighting — the results section names these), and the `rjsf-overrides` that rename, hide and re-describe fields — so you know the spec's task names are **not** what the user sees |
| `.github/workflows/` + `dev/recompile.sh` | **where the workflow runs**: a catalog workflow (a `staging` branch / `guard-main-prs.yml`, `--variant=gcp`) is used from the workflow catalog in Ecoscope Web and needs no Desktop install; otherwise it is installed into Ecoscope Desktop from its GitHub URL (`${CLAUDE_PLUGIN_ROOT}/reference/ci.md` § Repo-specific variation, `${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § `--variant=gcp`). This decides Prerequisites and Installation |
| the compiled `<WF>/<pkg>/rjsf.json` | the form exactly as rendered: card order (`uiSchema["ui:order"]`), card and field titles, defaults, option labels, descriptions, `ecoscope:advanced` (the "Advanced Configurations" accordion), hidden fields — § 1 inventories it |
| `test-cases.yaml` | every documented option exercised somewhere; `base` is the form-default submission, the other cases are your examples' values (synthetic, safe to quote) |
| a `base` mock run (§ 1) | the widgets the dashboard actually shows — type and title — and the grouped-view fan-out |
| `layout.json` | how many tiles and their order (`${CLAUDE_PLUGIN_ROOT}/reference/output-style.md` § Dashboard layout) |
| `git remote get-url origin` | the Installation URL, as `https://github.com/<org>/<repo>` |
| the existing `README.md`, if any | gate mode's subject; a `## Recompiling` README is developer boilerplate and counts as none |

If `<WF>/` is missing or older than `spec.yaml` (`git log -1 --format=%ci -- spec.yaml` vs
`<WF>/`), the form you would document is not the form the user gets: hand to `/ecoscope:develop`
for a compile first — this skill never compiles.

## 1. Inventory — the form and the widgets

**Environment: any shell for the script; the inner pixi env through `./dev/run-test-cases.sh`.**
Check `.scratch` is gitignored first (`repo-layout.md` § `.scratch/`; otherwise use the system
temp dir), then:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/guide/scripts/form-inventory.py <WF>/<pkg>/rjsf.json > .scratch/form-inventory.txt
./dev/run-test-cases.sh --case base > .scratch/base-run.log 2>&1; echo exit=$?
```

The inventory prints each card in form order with its fields: title, default, option labels,
`ADVANCED` / `HIDDEN` / `required` flags and the condition that reveals a field. Read the run
log whole; the results dir it prints holds `result.json`, whose `result.views` lists every
widget with its `widget_type` and `title`, one entry per view when the case groups
(`${CLAUDE_PLUGIN_ROOT}/reference/testing.md` § `dev/run-test-cases.sh`). Re-run the script
with `--result <that result.json>` to fold the widgets in. Empty `views` is the silently-empty
run, not a workflow without a dashboard — stop and hand to `/ecoscope:develop`.

What the user sees versus what the files say:

- A card is `properties.<key>`: its title is `.title` for a single-task card and the key itself
  for a task group (`ecoscope:task_group: true`); order is `ui:order`.
- An object titled `""` or `" "` is an invisible wrapper — document its children, never it
  (`${CLAUDE_PLUGIN_ROOT}/reference/rjsf.md` § Hide titles). An *array* titled `" "` (a
  groupers list) is documented by its row types directly under the card, never by its spec key.
- Union arrays (metric rows, groupers) are documented by row type; the inventory lists each row
  type's own fields (`Unit`, `Event Field to Sum` …) — those titles are what a row shows once
  picked, and a stale one hides in prose, so check them against the inventory too.
- `ecoscope:advanced` fields sit under their card's "Advanced Configurations" accordion → the
  guide's *Advanced Configuration* subsection; everything else is *Basic* (`rjsf.md` § Expect one
  "Advanced Configurations" accordion per task).
- `ui:widget: hidden` fields and `partial:`-bound params are not on the form — never mention them.
- Options and defaults are quoted by their **labels** (`Grouped`, not `group`).
- Dropdowns fed from the connection (`ecoscope:transform` / `EarthRangerEnumResolver`) list the
  user's own EarthRanger objects — say where those live in EarthRanger, never a fixed list
  (`${CLAUDE_PLUGIN_ROOT}/reference/connections.md` § Connection types and fields).
- Widget titles in `result.json` are the dashboard tile headings; `widget_type` (`map`, `graph`,
  `table`, `stat`, `text`) decides how each is described (`output-style.md`).

## 2. Mode and proposal — then approval

**Environment: none — write the proposal.** Open with one line stating the mode and why:

- **Write** — no README, or one without the eight sections. Propose the outline: the title and
  one-paragraph intro; where it runs (catalog / Web or Desktop) and therefore what Prerequisites
  and Installation will say; the data-source product and the server-side objects the dropdowns
  need; the Configuration Guide cards in form order with the fields you will document under
  each; the widgets, and the critical algorithms that get the *How the Results Are
  Calculated* subsection (from the spec); the one example (the `base` case); and the **troubleshooting list — only issues specific to this workflow, for the user to
  prune** before anything is written.
- **Gate** — an existing 8-section README. Run the check:

  ```bash
  python3 ${CLAUDE_PLUGIN_ROOT}/skills/guide/scripts/form-inventory.py <WF>/<pkg>/rjsf.json \
      --result <results>/result.json --check README.md > .scratch/guide-gate.txt; echo exit=$?
  ```

  It lists every card, field and widget title the README never names as a bold label or
  heading, and separately those it only mentions in prose (a renamed field usually shows up
  there). Then read the Configuration Guide against the inventory for what a grep cannot see: a
  default or option list that changed, a field the README still describes that is no longer on
  the form, a reordered card, an example whose values no longer match a case, an Installation
  URL that is not this repo. Report three lists — **missing**, **stale** (old → new) and
  **extra** — each item naming the README section it touches; then which sections you will
  edit, and that everything else stays byte-identical. Nothing to report = the gate passes: say
  so and hand back.

**Stop and wait for approval** — of the outline in write mode, of the edit list in gate mode.
When a release design the user already approved in `/ecoscope:publish` names this gate, that
approval covers the gate's edits: report, then proceed without a second stop.

## 3. Write, or update only what the gate lists

**Environment: the editor.** Section by section from
`${CLAUDE_PLUGIN_ROOT}/skills/guide/section-templates.md` — the fleet's exact headings and fixed
wording, which readers know from the other workflows — in the voice, formatting and
terminology of `${CLAUDE_PLUGIN_ROOT}/skills/guide/style-guide.md`. What keeps the text honest:

- **Field names are the inventory's titles, verbatim and bold** — `**Patrol Status**`, not
  "Status"; `Default:` and `Options:` by label. `(required)` means the form will not submit
  without a value: a scalar the inventory flags `required`. An array or object in the schema's
  `required` list still submits empty, so it follows its own description ("leave empty to …" is
  `(optional)`); a defaulted field the workflow cannot run without (the metrics, the interval)
  may say `(required)` with its default stated. A description that contradicts what the schema
  enforces is a `/ecoscope:develop` finding — note it, do not resolve it in the README.
- **Prerequisites and Installation follow § 0's platform.** A catalog workflow needs no
  Desktop install and gets no Installation steps; a Desktop workflow gets the four fixed steps.
  The data-source item names the product the spec connects to — EarthRanger is not assumed.
- **One example, and it is a case.** The `base` case, "submitted as-is", with its values from
  `test-cases.yaml`. Never invent a value and never quote a real data pull
  (`${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md` § Sensitive data — connection names and
  patrol-type slugs are org constants and fine).
- **Results describe the run; the algorithms get their own subsection.** One `####` per widget
  the base run produced, in `layout.json` order; then *How the Results Are Calculated* — a
  dedicated subsection with one `####` per critical algorithm the workflow applies (BBMM or
  another home-range estimator, a kernel or time-weighted density, an encounter rate's
  denominator, any aggregation that changes what a number means), each explained in plain
  sentences with the form fields that tune it — from the task and its parameters in
  `spec.yaml`, confirmed in the task's description in the pinned library
  (`${CLAUDE_PLUGIN_ROOT}/reference/task-discovery.md`). Omitted only when every output is a
  plain count, list or table. A *Data Outputs* subsection only when the spec persists files,
  with columns read from the run's output or the fixture. Groupers → the view-selector sentence.
- **Troubleshooting is only what is specific to this workflow** — the form's own constraints (a
  combination the schema forbids, a required field blank by default), a name that must match the
  server, the run that succeeds with nothing to show. No fixed count, no generic connection
  boilerplate; the list is the one the user pruned in § 2.
- **Gate mode edits only the listed sections.** No rewording, reordering or restyling elsewhere;
  the reviewer reads the diff as "what changed in this release".

## 4. Verify against disk

**Environment: any shell.** Before reporting done:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/guide/scripts/form-inventory.py <WF>/<pkg>/rjsf.json \
    --result <results>/result.json --check README.md; echo exit=$?
```

exit 0 — every visible card, field and widget title is a label or heading in the README. Then by
eye, with the style guide's checklist: the eight `##` sections in order; Installation present
only for a Desktop workflow and its URL equals `origin`; the example's values are grep-able in
`test-cases.yaml`; nothing the inventory
marks `HIDDEN`, no spec task name; defaults by label. In gate mode `git diff README.md` shows
only the flagged sections. Commit `docs: user guide README` (write) or `docs(readme): <what
changed>` (gate) — or, inside a publish run, leave it for the release commit
(`/ecoscope:publish` § 6).

## 5. Hard rules

Each has its mechanism in the linked file; they are prohibitions here because they get broken
under pressure ("the spec says what the field is", "the old README was close enough").

- Never document a card, field, default, option or widget the inventory or the run does not show;
  the spec's task names and other workflows' READMEs are not sources — `rjsf-overrides` rename
  and hide things, and widget titles come from the run (`rjsf.md`).
- Never edit `spec.yaml`, `test-cases.yaml`, `layout.json` or anything under `<WF>/` from here —
  a form or dashboard that reads badly is a `/ecoscope:develop` job, and the README follows it.
- Never write real organisational data into an example (`process-rules.md`).
- Never pipe `dev/run-test-cases.sh` or the check script through `tail`, `head`, `sed` or
  `grep -v` when its exit code is what you are recording; redirect to a file, then read it
  (`${CLAUDE_PLUGIN_ROOT}/reference/environments.md`).
- In gate mode, never touch a section the report did not list.

## 6. Handoffs

Offer each when it becomes relevant, and wait for a yes; never start one unasked.

| When | Offer |
|---|---|
| The form or dashboard has to change to be explainable (a duplicate heading, a field with no title, an empty run, a stale compile) | `/ecoscope:develop` |
| Invoked from the publish gate and the README is current | back to `/ecoscope:publish` § 6 — the README rides in the release commit |
| A documented change is ready to ship | `/ecoscope:publish` |

Close every session by naming what comes next. Do not start it.
