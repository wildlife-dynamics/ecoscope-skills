# Upstream docs — how to use them, and where they are wrong

Two upstream doc trees exist: the **wt framework docs** (in the wt monorepo) and the
**platform-sdk docs** (in the ecoscope task-library repo). The hierarchy this suite follows:

**Upstream is authoritative for vocabulary and mental model; the compiler's pydantic models and
real fleet specs are authoritative for syntax.** Where they conflict, use the working form below
and know which doc is wrong — don't let a confident tutorial talk you out of the right answer.

Citations in this knowledge base name **symbols** (`TaskInstance` in `wt_compiler.spec`), not
line numbers; locate any module with
`python -c "import <module> as m; print(m.__file__)"`.

## Contents
- Known-wrong upstream claims
- Known-incomplete areas (this suite fills them)
- What upstream explains best — read these

## Known-wrong upstream claims

| Claim (doc) | Reality |
|---|---|
| `rjsf-overrides` as a **task-instance** key with nested `schema:`/`properties:`/`uiSchema:` (platform-sdk form-customization tutorial — the most copy-pasteable error in the corpus) | Hard validation error: `TaskInstance` forbids extra keys. `rjsf-overrides` exists only at the spec **top level** with flat dotted paths ([rjsf.md](rjsf.md)); the tutorial's EnumResolver shape is invented too — the real one uses `ecoscope:transform` + `transformer_kws` |
| Conda channel allowlist ("a channel outside this set raises a validation error" — wt concepts + spec-yaml reference) | Removed in compiler 0.8.2; any URL-schemed channel passes through |
| CLI contract of `params`/`params_file`/`output_dir` + `WORKFLOW_*` env vars (wt-contracts reference) | The generated CLI takes `--config-json`/`--config-file`/`--execution-mode`/`--mock-io` and reads the results env var ([testing.md](testing.md)) |
| `execution_mode: "async"` (wt-runner reference) | Only `sequential` is valid; async templates and pixi tasks are vestigial |
| Generated package contains `params.py`/`formdata.py` (wt-compiler reference) | Removed in 0.6.0 — schema files are `params.json`/`rjsf.json` |
| "The Platform SDK ships ~80 tasks" (concepts, built-in-tasks) | ~240 in platform alone; large areas (config, pydeck) are undocumented |
| Connection picker appears "because the task's return type is a connection protocol type" (concepts, data-sources) | It's the **parameter** type; the return is `str` ([connections.md](connections.md)) |
| `skip_gdf_fallback_to_none` listed under skip conditions | Not a registered task; cannot appear in `skipif.conditions` |
| The legacy catalog repos named as the production examples to study (platform-sdk examples) | They're legacy-framework; study current published wt repos instead |

Also: the spec-yaml reference omits the `metadata:` top-level key (added 0.9.0), and the
getting-started path never mentions `--variant`, `--pkg-name-prefix`, `--results-env-var`,
`test-cases.yaml`, or the publish lifecycle — that entire surface is suite-only knowledge.

## Known-incomplete areas

- The groupers tutorial's SpatialGrouper section omits the three-task resolver chain and the
  mock display-name requirement ([patterns.md](patterns.md)) — following it alone cannot produce
  a working spatial grouper.
- `mapvalues` and `skipif` have no upstream how-to at all (the tutorials cover only `partial`,
  chaining, and `map`).

## What upstream explains best — read these rather than re-deriving

- **groupers tutorial on `map` vs `mapvalues`** — the clearest statement anywhere of the
  keyed-iterable model and the `mapvalues`→`map` transition at the widget step.
- **form-customization on `partial`** (the part that IS right): "bound parameters are fixed;
  unbound parameters become form fields" — why `partial:` is the primary form-control lever; and
  the escalation ladder `Field` → `AdvancedField` → `json_schema_extra`.
- **concepts key-terms table** — registered function vs task vs task instance vs registry vs
  compiled workflow vs invoker vs runner vs metapackage. Use this vocabulary consistently.
- **architecture doc on the whys**: subprocess discovery (avoids importing task deps — the
  mechanism behind the silent-ImportError failure); compile-don't-interpret (why generated code
  is committed); fingerprinting ignoring cosmetic changes (why params_sha256 drives MAJ-vs-MIN);
  GCP metapackages as conda's substitute for extras (the mechanism behind `--variant=gcp`);
  `map` argnames semantics (single vs unpacked).
- **platform getting-started on the Desktop loop**: import the **repo root**, not the compiled
  subdirectory; no update-in-place (refresh = delete + re-import); edit → compile → run →
  observe → iterate.
