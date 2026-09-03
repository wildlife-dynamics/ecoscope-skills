# rjsf overrides and form rendering

Per-workflow form customization via the spec's top-level `rjsf-overrides` key, plus the
renderer behaviors that determine what actually works. Conditional (reveal-on-check) fields have
their own file: [rjsf-conditionals.md](rjsf-conditionals.md); what to *write* in titles,
descriptions and help text — short, one string per card stack — is [rjsf-style.md](rjsf-style.md).
Task-level (all-workflow) schema control lives in [tasks.md](tasks.md).

The renderer source of truth is the rjsf component set in the ecoscope-web repo
(`CheckboxWidget`, `FieldTemplate`, `ObjectFieldTemplate`, `ArrayFieldTemplate`,
`CustomObjectFieldTemplate`, `ConfigureWorkflowForm`). Verify against the compiled `rjsf.json`
and a live form; the config-form playground may render some fields differently from Desktop.

## Contents
- Write overrides as top-level flat dotted paths, starting with the exact card title
- Use `$defs` overrides for display only — they never reach `params.json` (compiler ≥0.7.0)
- Use `ui:order` only for card order, never inside a card
- Match group titles exactly in override paths — mismatches are silently ignored
- No duplicate task-group titles
- Never flip `ecoscope:task_group: false` to restyle a card
- Expect one "Advanced Configurations" accordion per task in a card — don't try to merge them
- Hide titles with `""` for objects but `" "` for arrays and strings
- Follow these field rendering rules
- Populate dropdowns from the connection with `ecoscope:transform` (EarthRangerEnumResolver)

## Write overrides as top-level flat dotted paths, starting with the exact card title

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

## Use `$defs` overrides for display only — they never reach `params.json`

Since compiler 0.7.0, `$defs` overrides apply **only to `rjsf.json`, not `params.json`**. Use them
for display (titles, labeled oneOf on `$ref`'d types); don't expect them to change the validation
model.

## Use `ui:order` only for card order, never inside a card

`ui:order` works at **one level only: the top level, to order task-group cards.** The compiler
auto-emits a top-level `ui:order` from spec task order, so you rarely need it; override it only
when card order must differ from spec order, and list every group title (rjsf errors on a partial
list — see the path-mismatch note below). Scrambled card order is usually a symptom of the
duplicate-title clobber below, not something to fix with `ui:order`.

**Inside a task-group card, `ui:order` is ignored** — the custom template iterates schema property
entries, so in-card field order = task order in the spec. Don't add a per-card `ui:order`; it does
nothing and breaks whenever tasks change. To move field A above field B when B's task consumes A's
return, split A into its own tiny task declared first ([spec.md](spec.md)).

## Match group titles exactly in override paths — mismatches are silently ignored

The compiler **silently ignores** override paths that don't match — a group-title typo means the
override doesn't apply and the property looks "missing". The error
`order list does not contain properties` is very likely a group-title path not exactly matching
the spec's `title:` (spaces and capitalization included).

## No duplicate task-group titles

**Never give two task-groups the same `title:`.** Two field-bearing groups sharing a title merge
into one card but the schemas don't union — the LAST group's clobbers the earlier one's. Symptom:
rjsf-overrides on the clobbered tasks create phantom objects with no `type`; the renderer shows
"Unsupported field schema … Unknown field type undefined" and raw-id card headers.

## Never flip `ecoscope:task_group: false` to restyle a card

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

## Expect one "Advanced Configurations" accordion per task in a card — don't try to merge them

Renderer logic, not compiler logic. The renderer branches on `schema["ecoscope:task_group"]`:

- **Task-group card** → one separate "Advanced Configurations" accordion **per task**, splitting
  that task's own leaf fields by `ecoscope:advanced` (advanced flags on the task objects
  themselves are ignored). A group with 3 advanced-bearing tasks shows 3 accordions — they cannot
  be merged while it stays a task-group, and un-grouping breaks submission (trap above).
- **Non-task-group section** (the compiler-built cards with no `ecoscope:task_group` flag —
  `workflow_details`, `er_client_name`, `time_range`, `base_map_defs`) → the section's direct
  child properties are split by `ecoscope:advanced`, and all advanced ones share exactly one
  accordion.

To put params from several tasks into **one** accordion, give them a dedicated task: a single
task that takes all of those params (flagged `ecoscope:advanced`) and returns them for the
consuming tasks — one task's leaf fields = one accordion. Same split-a-task move as for field
order ([spec.md](spec.md)).

Within the constraint you can still tidy: `title: ""` drops a task header; `partial` hides fields.
`ecoscope:advanced` is honored only on a card's direct task args — ignored inside nested objects
and array rows.

## Hide titles with `""` for objects but `" "` for arrays and strings

| Field kind | Remove title via | Why |
|---|---|---|
| Object / task-group header (from spec task `name`) | `…title: ""` | ObjectFieldTemplate renders title only when truthy; `""` removes cleanly |
| **Array field** | `…title: " "` (single space), **not** `""` | array title resolves `uiOptions.title ?? schema.title ?? name`; empty **falls back to the raw property name** |
| **String / textarea field** | `…title: " "` (single space) | FieldTemplate gates the *description* on `displayLabel`; `ui:options.label: false` would hide the description too |

Corollary: `ui:options.label: false` on a string field hides its description as well — use only
when you want neither; it remains correct for array-*item* labels
(`<task>.<field>.items.ui:options.label: false`).

## Follow these field rendering rules

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

## Populate dropdowns from the connection with `ecoscope:transform`

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

The target may be a **scalar string field**, not only a grouper array. In ecoscope-server's
`er_enum_resolver.py`, `_get_insertion_fn` routes `spatial_feature_group` to the grouper-specific
inserter only when the path ends in `groupers`; every other path — and every other type — goes
through `_insert_standard_enum_def`, which sets `items` on `type: array` targets and merges a
`$ref` straight into a scalar. The field becomes a `oneOf` of names per connection inside an
`allOf/if/then` keyed on the connection, defaulted and disabled when exactly one value exists,
and left as free text with a "failed to fetch" description when the fetch fails. No spec-side
difference from the array form.
On **Desktop** these fields render as an array text input with an "Add" button, not a dropdown —
matters for E2E tests ([desktop-e2e.md](desktop-e2e.md)).
