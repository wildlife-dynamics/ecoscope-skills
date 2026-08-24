# Conditional form fields — what works, what fails, and at which layer

The densest failure matrix in the whole knowledge set. Two systems must both accept a conditional:
RJSF (which resolves schemas pre-render with `removeAdditional: 'failing'` and its own allOf
merge) and the server's Draft-2020-12 validation (which 422s on submit). Each wrong shape passes
one layer and fails the other, so a form can render perfectly and still be unusable. Renderer
observed at RJSF 5.19.4 — re-verify on major ecoscope-web bumps.

## Contents
- Reveal-on-check: the one working shape
- The four failing alternatives and which layer each breaks
- Arrays: no conditional `items.oneOf`
- Cross-card conditionals
- Desktop submit drop-rules for revealed fields
- Headless contract testing (no browser, no server)

## Reveal-on-check: the one working shape

Restate the WHOLE object at its dotted path (subtree replacement drops the compiled
`additionalProperties: false` — that is load-bearing) with `allOf/if/then` and nothing else:

```yaml
rjsf-overrides:
  properties:
    "Card.properties.task_id":
      type: object
      properties:
        enable_thing: {type: boolean, title: "Enable thing", default: false}
      allOf:
        - if: {properties: {enable_thing: {const: true}}}
          then:
            properties:
              thing_config: {type: array, items: {type: string}, title: "Thing config"}
```

Rules: no `default` on the conditional field (it orphan-seeds formData); keep enum/type
constraints inside the `then` branch; flat `allOf/if/then` for scalar fields within one object
works fine.

## The four failing alternatives

| Shape | What happens | Failing layer |
|---|---|---|
| `dependencies` | removed after draft-07; the server's validator ignores it, so the revealed field trips `additionalProperties: false` → **422 on every submit** (the form looks fine — RJSF resolves it pre-render) | server |
| `dependentSchemas` | RJSF only reads literal `dependencies` (+ if/then/else) → field **never renders** | renderer |
| if/then + `additionalProperties: false` kept | RJSF's allOf merge intersects then-props against aP → **never renders even when checked** | renderer |
| if/then + `unevaluatedProperties: false` | `getDefaultFormState` seeds the hidden field (`[]`) from first render and retains values after toggle-off → **422 on every unchecked submit** | server |

## Arrays: no conditional `items.oneOf`

RJSF cannot swap a nested array's `items.oneOf` based on a sibling field. A root-level
`allOf/if/then` whose `then` overrides `properties.<array>.items.oneOf` is silently ignored by
`retrieveSchema`; rows whose branch is absent get matched to the nearest branch by
`getClosestMatchingOption` and render wrong selector labels. Design around it: keep all branches
visible and degrade gracefully (e.g. a metric falls back to counting when no field is chosen),
with a `ui:help` note.

## Cross-card conditionals

Work **in principle** — the config form is ONE form over the whole root schema — but are not
expressible today. Two blockers: the compiler's override models
(`ReactJSONSchemaFormConfiguration` / `ReactJSONSchemaFormOverrides` in `wt_compiler.jsonschema`)
are closed (properties/$defs/uiSchema/additionalProperties only), so a root `allOf` is dropped on
serialization; and `additionalProperties: false` at any level whose properties are then-declared
kills it twice (RJSF drops the field; server 422s) — those levels would need aP stripped, while a
root aP:false may stay when then-branches only restate existing card names. Until a wt-compiler
change lands, cross-card reveals are off the table.

## Desktop submit drop-rules for revealed fields

Values the user *actively sets* on revealed fields survive submit. Two shapes get dropped from
the payload (missing key → model default reapplies):

- a revealed field showing a **prefilled default the user never touches** (e.g. a branch default
  injected by an override). If the model field is required, the run then fails at params
  validation. E2E workaround: re-pick the already-selected option so rjsf commits it.
- a revealed **checkbox the user UNchecks** — false submits as a missing key, so a `default=True`
  model field silently stays on.

Verify what actually committed via the run's `metadata.json` `config`
([preview-desktop.md](preview-desktop.md)).

## Headless contract testing

Test both layers without a browser or server:

- **Renderer half** — a Node script against an ecoscope-web checkout's `node_modules`:
  `@rjsf/utils` `createSchemaUtils(validator, schema).getDefaultFormState(...)` reproduces the
  form's per-change pipeline; `retrieveSchema(validator, sub, sub, formData)` shows what renders.
  Match the real form exactly with
  `customizeValidator({ajvOptionsOverrides: {allErrors: true, removeAdditional: 'failing'}})`.
- **Server half** — `wt_contracts.formdata` pure functions:
  `params_to_formdata(case_params, rjsf, params_json)` then `formdata_to_params(...)` raises the
  exact 422 (jsonschema-native error entries: message, path, schema_path, validator, input).
- Feed every state `getDefaultFormState` can produce into `formdata_to_params` — that closes the
  loop the four failing shapes slip through. Note RJSF seeds hidden conditional fields into
  formData, so test the unchecked-submit path explicitly.
