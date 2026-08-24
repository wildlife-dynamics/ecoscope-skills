# rjsf overrides and form rendering

Per-workflow form customization via the spec's top-level `rjsf-overrides` key, plus the
renderer behaviors that determine what actually works. Conditional (reveal-on-check) fields have
their own file: [rjsf-conditionals.md](rjsf-conditionals.md). Task-level (all-workflow) schema
control lives in [tasks.md](tasks.md).

The renderer source of truth is the rjsf component set in the ecoscope-web repo
(`CheckboxWidget`, `FieldTemplate`, `ObjectFieldTemplate`, `ArrayFieldTemplate`,
`CustomObjectFieldTemplate`, `ConfigureWorkflowForm`). Verify against the compiled `rjsf.json`
and a live form; the config-form playground may render some fields differently from Desktop.

## Contents
- Override structure and path syntax
- What `$defs` overrides reach (compiler ≥0.7.0)
- `ui:order` — don't
- Silent path-mismatch failure
- The same-title task-group schema clobber
- `ecoscope:task_group` and the submit-flatten trap
- "Advanced Configurations" accordions
- Hiding titles and labels — depends on field kind
- Field rendering rules
- Dynamic dropdowns (`ecoscope:transform` / EarthRangerEnumResolver)

## Override structure and path syntax

`rjsf-overrides` is a **top-level spec key** (never per-task-instance —
[upstream-docs.md](upstream-docs.md)) with three sections, all flat dotted-key dicts:

```yaml
rjsf-overrides:
  properties:
    # direct task path
    task_id.properties.param.default: "value"
    # task inside a group — path starts with the EXACT group title (quote if it contains dots)
    "Group Title.properties.task_id.properties.param.title": "Display Title"
  $defs:            # alias: definitions
    ValueGrouper:
      title: "Category"
  uiSchema:
    task_id.param.items.ui:options.label: false
    "Group Title.task_id.field.ui:help": "Helper copy below the field."
```

Property path shape: `<Card title or task id>.properties.<task id>.properties.<field>.<key>`.
uiSchema paths omit the `properties.` segments. To **hide a param entirely**, don't override —
move it to `partial:` in the spec (removes it from rjsf and from the user-facing model; also
remove it from `test-cases.yaml` or it becomes `extra_forbidden`).

## What `$defs` overrides reach

Since compiler 0.7.0, `$defs` overrides apply **only to `rjsf.json`, not `params.json`**. Use them
for display (titles, labeled oneOf on `$ref`'d types); don't expect them to change the validation
model.

## `ui:order` — don't

**Never use `ui:order` in rjsf-overrides.** It requires listing every property and breaks whenever
tasks change; and **inside task-group cards it is ignored anyway** — the custom template iterates
schema property entries, so in-card order = task order in the spec. To move field A above field B
when B's task consumes A's return, split A into its own tiny task declared first
([spec.md](spec.md)). The compiler auto-emits group-level `ui:order` from spec task order;
scrambled card order is a symptom of the same-title clobber below, not something to fix manually.

## Silent path-mismatch failure

The compiler **silently ignores** override paths that don't match — a group-title typo means the
override doesn't apply and the property looks "missing". The error
`order list does not contain properties` is very likely a group-title path not exactly matching
the spec's `title:` (spaces and capitalization included).

## The same-title task-group schema clobber

Two task-groups sharing a `title:` merge into one rendered card, **but the merge does not union
the params models — the LAST field-bearing group's schema clobbers the earlier one's.** Symptom:
rjsf-overrides on the clobbered tasks create phantom objects with no `type`; the renderer shows
"Unsupported field schema … Unknown field type undefined" and raw-id card headers.

Rule: put ALL field-bearing tasks in the FIRST group with a given title; a later same-title group
may contain only fully-partialed tasks. Verify by grepping the compiled `rjsf.json` for **real
`type` keys** on the fields — not mere member presence. (Observed at compiler 0.8.3; re-verify on
≥0.9.)

## `ecoscope:task_group` and the submit-flatten trap

`ecoscope:task_group` (set by `type: task-group`) is **not render-only**. The Desktop/web form
flattens a group's tasks back to **top-level** params at submit time *only when the flag is true*
(the compiled Params model is flat for task-group tasks — which is why `test-cases.yaml` uses flat
task-id keys, not nesting under group titles). Flip the flag off via an override and the form
submits `{"<Group Title>": {…}}`, which the flat model rejects:

```
<Group Title> — Extra inputs are not permitted [type=extra_forbidden]
```

The run never starts, **and mock-io tests cannot catch it** — they feed flat params straight to
the model, bypassing the form's flatten step. Only a Desktop/web run or a playground submit
exercises it. So: never flip `ecoscope:task_group: false` to restyle a card.

## "Advanced Configurations" accordions

Renderer logic, not compiler logic. The renderer branches on `schema["ecoscope:task_group"]`:

- **Task-group card** → one separate "Advanced Configurations" accordion **per task**, splitting
  that task's own leaf fields by `ecoscope:advanced` (advanced flags on the task objects
  themselves are ignored). A group with 3 advanced-bearing tasks shows 3 accordions — they cannot
  be merged while it stays a task-group, and un-grouping breaks submission (trap above).
- **Non-task-group section** → direct child properties split by `ecoscope:advanced`, exactly one
  accordion.

Within the constraint you can still tidy: `title: ""` drops a task header; `partial` hides fields.
`ecoscope:advanced` is honored only on a card's direct task args — ignored inside nested objects
and array rows.

## Hiding titles and labels — depends on field kind

| Field kind | Remove title via | Why |
|---|---|---|
| Object / task-group header (from spec task `name`) | `…title: ""` | ObjectFieldTemplate renders title only when truthy; `""` removes cleanly |
| **Array field** | `…title: " "` (single space), **not** `""` | array title resolves `uiOptions.title ?? schema.title ?? name`; empty **falls back to the raw property name** |
| **String / textarea field** | `…title: " "` (single space) | FieldTemplate gates the *description* on `displayLabel`; `ui:options.label: false` would hide the description too |

Corollary: `ui:options.label: false` on a string field hides its description as well — use only
when you want neither; it remains correct for array-*item* labels
(`<task>.<field>.items.ui:options.label: false`).

## Field rendering rules

- **Checkbox helper text:** schema `description` renders ABOVE the checkbox; use uiSchema
  `ui:help` for text BELOW. When moving copy to `ui:help`, also blank the schema description or
  the task's native pydantic description re-appears above.
- **Native descriptions bleed back:** removing an override description re-surfaces the task's own
  `Field(description=…)`. Suppress with an explicit `…description: ""` (empty strings persist
  through compile).
- **rjsf `default:` is form-only** — a param omitted from a test case uses the **pydantic model
  default**, not the rjsf default. Set toggles explicitly in test cases.
- **Multi-select arrays** (`uniqueItems: true`) take a large subhead-style label keyed solely on
  `schema.uniqueItems === true` — no uiSchema escape hatch; suppress with `title: " "` or make it
  single-select.
- **Standalone-object union field:** hide the branch heading + duplicate inner discriminator with
  a field-level `anyOf:` list (one entry per branch), each
  `{ui:options: {label: false}, <discriminator>: {ui:widget: hidden}}`, plus a top-level hidden
  discriminator.
- **Discriminated-union array rows:** selector option labels come from `$defs` branch titles
  (don't blank those). `items ui:title: " "` blanks BOTH the item label and the branch heading —
  decouple with a per-branch `items oneOf:` array in union order. Caveats: a selected branch's
  entry REPLACES the base items uiSchema (repeat branch-scoped directives in every entry), and the
  discriminator MUST carry a pydantic `default` or the hidden field never populates on switch.
- **Enum labels:** rjsf prefers `enum` over `oneOf`, so spec-side `oneOf: [{const, title}]` on a
  `Literal` param is silently ignored — fix task-side ([tasks.md](tasks.md)). Plain `str` params
  have no `enum`, so spec-side `oneOf` works there.

## Dynamic dropdowns (`ecoscope:transform`)

`EarthRangerEnumResolver` populates choices from the selected connection:

```yaml
rjsf-overrides:
  properties:
    "Patrol Types.properties.er_patrol_params.properties.patrol_types.ecoscope:transform":
      - transformer: EarthRangerEnumResolver
        transformer_kws:
          type: patrol_type          # patrol_type | event_type | spatial_feature_group
          depends_on: properties.er_client_name.properties.data_source.properties.name
```

`depends_on` points at the connection-name field; options refresh when the data source changes.
On **Desktop** these fields render as an array text input with an "Add" button, not a dropdown —
matters for E2E tests ([desktop-e2e.md](desktop-e2e.md)).
