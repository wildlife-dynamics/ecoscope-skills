# Form copy style — what the user reads on the configuration form

The words on the config form: card titles, task headers, field titles, descriptions, help text.
Mechanics — override paths, which blank string hides which kind of title, where a description
renders — live in [rjsf.md](rjsf.md); this file is only about what to write. Check the result in
the compiled `rjsf.json` (`skills/guide/scripts/form-inventory.py <rjsf.json>` prints each card's
title stack the way Desktop shows it), never in `spec.yaml`.

## Contents
- Give each level of a card its own words
- Titles: short noun phrases, never a lone verb or a repeat
- Descriptions: one sentence that adds something the title can't
- Help text: below the widget, for consequences and where-to-find-values
- Leave the shared compiler cards alone
- Use the fleet's vocabulary
- Reword with dotted paths, not wholesale copies
- Worked example: one card, before and after
- Checklist

## Give each level of a card its own words

A card stacks up to five text slots, read top-down:

| Slot | Comes from | What it says |
|---|---|---|
| Card title | task-group `title:` | the thing being configured (`Filter Data`) |
| Card description | override on the group | one clause on what the card produces, or `""` |
| Task header | task `name:` | `""` in a one-task card; a sub-heading only when the card holds several tasks the user must tell apart |
| Field title | pydantic `title` / override | the specific input, minus the words above it |
| Field description / `ui:help` | override | format, example, empty-means-what, dashboard consequence |

**A string appears once per stack.** Card `Patrol Types` → header `Patrol Types` → field
`Patrol Types` is the fleet's most common defect; the fix is header `""` and, when the card has a
single field, either the field title carries the card's noun and the card is renamed to the
action (`Filter Data`), or the field title goes (`" "` for arrays and strings — rjsf.md) and the
card title does the work. `Summarize by` three deep (header, field, items) → header `""`,
field `Summarize by`, `items.ui:options.label: false`.

## Titles: short noun phrases, never a lone verb or a repeat

- **Card**: 1–3 words, Title Case, a noun phrase for what the card configures — `Group Data`,
  `Trend Chart`, `Styling`, `Encounter Rate Map`. Not an instruction: `Set Groupers for
  Analysis` → `Group Data`; `Configure grouping strategy` → `Group Data`.
- **Field**: 1–4 words, Title Case, dropping only the words the card or parent field already says:
  under `Trajectory Segments`, `Minimum Segment Length (Meters)` → `Minimum Length (m)`. Keep
  the noun when siblings need it — `Patrol Types` / `Event Types` / `Patrol Status` stay
  distinct under `Patrol and Event Types`.
- A title reads as a prompt and stands alone — it is also what the user guide and E2E tests name.
  `Measure Events By` and `Event Field to Sum` are right; `Measure` and `Event Field` are not.
  Abbreviate units (`(km)`, `(m)`, `(km/h)`), not words (`Min`, `Max`, `Config`).
- **Checkbox** titles are sentence-case statements of what checking does: `Include events without
  a location`, `Generate maps in dashboard`.
- **Enum / union branch** titles are the option labels: 1–3 words, parallel in form (`Number of
  Events` / `Sum of an Event Field`; `Auto-scale` / `Customize`).

## Descriptions: one sentence that adds something the title can't

A description exists only to add a format, an example, what "empty" means, or what the setting
changes on the dashboard. One sentence, ≤ 15 words, ends with a period, leads with the scope or
the consequence:

- `Only include patrol observations and events inside this bounding box.`
- `Exclude events recorded at these exact coordinates (e.g. known bad GPS fixes).`
- `Each featured species gets its own map; the rest share one.`

Otherwise blank it with `""` — a restatement (`Filter` → "Filter observations…", `Since` →
"The start time") is noise, and the task's native pydantic description bleeds back unless the
override is an explicit empty string (rjsf.md). Fixed phrases: `Leave empty to include all.`,
examples as `e.g. …`.

Every claim in a description is checked against the task's code before it is written — a
description states what the task does, not what the setting sounds like it does. No
implementation: task names, column names, `df`, method internals, "the workflow will…". A
70-word method comparison belongs in the user guide, not under a dropdown.

## Help text: below the widget, for consequences and where-to-find-values

`ui:help` renders under the widget; a checkbox's `description` renders above it, so checkbox
guidance goes in `ui:help` with the description blanked (rjsf.md). Use it for two things: what
each choice does (`Auto-scale picks a grid cell size from the workflow data; Customize sets
one.`) and where the user finds the values (`"Patrol Type" values are under Activity → Patrol
Types in your EarthRanger admin site.`). ≤ 25 words; naming an option is fine, repeating the
labels without saying what they do is not.

## Leave the shared compiler cards alone

If the override path starts with `workflow_details`, `er_client_name`, `time_range` or
`base_map_defs`, don't write it. These cards — **Workflow Details** (`Workflow Name`, `Workflow
Description`), **Data Source**, **Time Range** (`Since`, `Until`, `Timezone`) — are built by the
compiler and identical in every workflow; user guides, E2E page objects and support answers name
them verbatim. `Workflow Name` → `Name` reads fine on one form and breaks the fleet. Changing
their copy is a compiler change, not a spec override.

## Use the fleet's vocabulary

| Use | Not |
|---|---|
| `Data Source` | connection, client, server, `Connect to EarthRanger`, `Select EarthRanger Data Source` |
| `Time Range`, `Since`, `Until`, `Timezone` | date range, window, period, `Define analysis time range` |
| `Group Data` (card), `Category` (`ValueGrouper` `$defs` title) | `Set Groupers`, grouping strategy |
| `Patrol Types`, `Event Types`, `Patrol Status`, `Subject Group`, `Spatial Feature Group` | EarthRanger's nouns, unchanged and plural where the field is a list |
| `Map Base Layers` | `Base Maps`, `Base Layers` |
| `Workflow Details` | `Set Workflow Details` |
| `color` (matches the task-library params) | `colour` |
| `Filter Data`, `Styling` | `Refine Data`, `Appearance` |

Copy the canonical strings from a sibling workflow (`patrol-chart`, `patrol-effort-table`) rather
than rephrasing — the fleet's copy-pasted typo `based the workflow data` shows that pasting
without reading is the other failure.

## Reword with dotted paths, not wholesale copies

Titles and descriptions reachable by a dotted path are overridden by that path. Union-branch
titles are overridden through `$defs.<Name>.title` / `.properties.<field>.title` (display-only —
rjsf.md). A title that lives only inside an `allOf` / `items.anyOf` entry with no path is fixed in
the task library ([tasks.md](tasks.md)) — not by pasting the whole entry from `rjsf.json` into the
spec to change one word, which silently diverges at the next task-library bump.

## Worked example: one card, before and after

`patrol-effort-table`, card `Patrol Effort Summary`: two tasks named `Summarize by` and
`Summary Metrics`, each with one list field retitled to the same words. Left alone, every string
renders twice — task header, then field:

```
## card: Patrol Effort Summary
  - 'Summarize by' [object]            ← task header (spec `name:`)
    - 'Summarize by' [array]           ← field
  - 'Summary Metrics' [object]
    - 'Summary Metrics' [array]
```

The header is the copy to drop — the field title is what the Advanced accordion, the user guide
and the E2E test name — and the item labels go the same way:

```yaml
rjsf-overrides:
  properties:
    "Patrol Effort Summary.properties.summary_groupers.title": ""
    "Patrol Effort Summary.properties.summary_groupers.properties.groupers.title": "Summarize by"
    "Patrol Effort Summary.properties.summary_metrics.title": ""
    "Patrol Effort Summary.properties.summary_metrics.properties.metrics.title": "Summary Metrics"
  uiSchema:
    "Patrol Effort Summary.summary_groupers.groupers.items.ui:options.label": false
    "Patrol Effort Summary.summary_metrics.metrics.items.ui:options.label": false
```

```
## card: Patrol Effort Summary
  - '' [object]
    - 'Summarize by' [array]
  - '' [object]
    - 'Summary Metrics' [array]
```

## Checklist

- [ ] `form-inventory.py` on the compiled `rjsf.json`: no string twice in any card's stack
- [ ] Card titles 1–3 words, field titles 1–4, Title Case; checkbox titles sentence-case statements
- [ ] Every title stands alone (would make sense in the Advanced accordion and in the user guide)
- [ ] Every description ≤ 15 words, adds something, verified against the task's code; restatements `""`
- [ ] Checkbox guidance in `ui:help`, description blanked
- [ ] No override path under `workflow_details`, `er_client_name`, `time_range`, `base_map_defs`
- [ ] Vocabulary from the table; strings copied from a sibling workflow where one exists
- [ ] No `allOf` / `items.anyOf` / `$defs` entry pasted from `rjsf.json` just to reword it
