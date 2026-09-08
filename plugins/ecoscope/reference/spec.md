# spec.yaml reference

Single source for spec structure and syntax. The authoritative schema is the pydantic model set in
`wt_compiler.spec` (`Spec`, `TaskInstance`, `TaskGroup`) — when this doc and the model disagree,
the model wins; locate it with `python -c "import wt_compiler.spec as m; print(m.__file__)"`.
Upstream docs are reliable for concepts but not syntax — see [upstream-docs.md](upstream-docs.md).

## Contents
- Top-level structure
- `metadata:` (new in compiler 0.9.0)
- Task instances
- Task groups
- `requirements:` (conda and PyPI forms; channels)
- Editable / path requirements (dev mode) and the pin stacks
- Bumping library pins
- Variable references
- `map` / `mapvalues`
- `skipif`
- Validation rules and wiring constraints
- Authoring idiom from real fleet specs

## Top-level structure

`Spec` forbids unknown top-level keys. The complete set:

| Key | Required |
|---|---|
| `id` | yes — Python identifier, ≤64 chars, not a keyword/builtin, must not collide with any task `id` |
| `requirements` | yes |
| `metadata` | no (compiler ≥0.9.0) |
| `rjsf-overrides` | no — see [rjsf.md](rjsf.md) |
| `task-instance-defaults` | no — only field is `skipif`, applied to any instance whose own `skipif` is unset |
| `workflow` | yes — topologically ordered list of task instances and task groups |

## `metadata:` (compiler ≥0.9.0)

The block is optional; when present, `name`, `description`, `maintainers` (non-empty list of
`{name, email}`) and `license` are required, and `repository` / `documentation` / `readme` /
`keywords` are optional (`Metadata`, `Maintainer` in `wt_compiler.spec`). Both models allow and
retain extra keys. Excluded from `Spec.sha256`, so adding or editing it doesn't change an existing
workflow's hash, and the compiler templates never read it. Fleet convention for the extras —
`role` on each maintainer (`owner` / `reviewer`) and a repo-relative `thumbnail` on the block —
and what the catalogs actually display: [catalog.md](catalog.md).

## Task instances

`TaskInstance` forbids extra keys. Complete field set:

| YAML key | Notes |
|---|---|
| `id` | required — Python identifier, ≤32 chars, unique, must differ from every registered task name |
| `task` | required — bare registered name, or fully-qualified public module path on collision |
| `name` | display name (default `""`); becomes the form header for the task |
| `partial` | static kwargs — literals, `${{ workflow.<id>.return }}`, `${{ env.VAR }}`; nestable inside lists/dicts |
| `map` / `mapvalues` | at most one of the two |
| `skipif` | overrides `task-instance-defaults.skipif` **entirely** when present |


## Task groups

```yaml
- title: Patrol Types            # a card in the config form
  type: task-group
  description: " "               # " " renders an empty description
  tasks: [ ...task instances... ]
```

`title`, `description`, `tasks`, `type` — all required, extras forbidden. Groups are flattened for
execution and cannot nest. Task order inside the card is task order in the spec, and nothing
overrides it. **Never duplicate a group `title`** 


## `requirements:`

The union is **key-based**: an entry containing `git`/`path`/`url` is a PyPI requirement,
otherwise conda.

**Conda** — `name`, `version` (matchspec), `channel` (default `conda-forge`):

```yaml
requirements:
  - {name: ecoscope-platform, version: ">=2.18.3, <2.19.0", channel: https://repo.prefix.dev/ecoscope-workflows/}
  - {name: pydeck, version: 0.9.2, channel: conda-forge}
```

- **Never put an explicit channel-less `python` requirement in a publish spec.** It resolves to
  conda-forge and hoists that channel to top strict priority in the compiler's discovery env,
  shadowing ecoscope-channel-only packages and breaking the solve. (A `python` pin is legitimate
  inside the editable-dev pin stack below, where it prevents the ephemeral env picking a Python
  without wheels for transitive deps.)
- **The pydeck re-statement** (`pydeck 0.9.2` from conda-forge) is a fleet-wide workaround:
  ecoscope-platform already declares pydeck, but the custom channel ships a forked pydeck 0.0.2
  that wins under strict channel priority; restating pins the real one.
- Conda name vs PyPI name: the conda package is **`ecoscope-platform`**; the local/PyPI package is
  **`ecoscope`** with extras (both built from the same task-library repo).

**PyPI** — `name` plus exactly one of `git`/`path`/`url`; `rev`/`branch`/`tag` (git only, at most
one); `editable` (path only); optional `subdirectory`, `extras`, `version`. `path:` must be
**absolute** — no `file://`, no relative paths.

```yaml
  - name: my-tasks
    git: https://github.com/org/my-tasks.git
    tag: v0.3.1
    subdirectory: src/my-tasks
```

CI / publish mode rejects `path:`/`editable:` and wildcard versions — revert to released pins
before publishing.

## Editable / path requirements (dev mode)

Editable installs land in the *generated workflow's* pixi env (via `--install`), not the
compiler's env — which is why they work with the global compiler.

**Ext-custom only** (platform stays released): point the ext-custom requirement at the local
task-library checkout with `path:` + `editable: true`; keep `ecoscope-platform` on its channel.

**Editable ecoscope (the full pin stack).** For
`{name: ecoscope, path: <local ecoscope checkout>, editable: true, extras: [platform, mapping, analysis]}`
these conda pins are required so uv never falls back to PyPI:

- `python 3.12.*`
- `numpy >=2,<2.1` (conda-forge — ecoscope pins numpy strictly)
- `pyarrow >=20,<24` (the git dep ecoscope-earthranger-io-core caps it)
- `pydeck 0.9.2`, `lonboard ==0.0.8` (ecoscope-workflows channel)
- `rasterio >=1.3,<1.5` when needed for GDAL — but **drop it when combining with a remote
  ext-custom build** (libgdal conflict via lonboard→pyogrio)

After **every** compile run `./dev/postcompile-editable.sh` (patches the generated inner
`pixi.toml`: pydantic `<3.0.0`→`<2.9.0` because ≥2.9 breaks discriminated unions in
`apply_classification`, plus a host-platform-only platforms patch, then `pixi install`). Prefer
declaring the pydantic pin in `requirements:` (conda-forge, `>=2.0.0,<2.9.0`) so it survives
solves instead of hand-patching. Test with `--frozen` (git-tag deps make `--locked` report stale
forever). Switching to/from editable: `rm` the inner `pixi.lock` and compile `--clobber --install`
(`--update` keeps the stale lock and the old conda ecoscope).

**Extras:** `platform` (pandera, pydantic, wt-registry, wt-task, … — always required), `mapping`
(lonboard, matplotlib), `analysis` (statsmodels), `plotting` (plotly, scikit-learn). In a
published install `plotting` arrives transitively via ecoscope-platform, but in a dev-editable
setup you must list it if any imported task module needs it — ext-custom's `tasks/__init__.py`
imports **all** task modules at package load, so one ported task's `import plotly` breaks every
workflow touching ext-custom. Do NOT "fix" that by flipping ext-custom to a published build while
ecoscope stays editable — its recipe hard-deps a released ecoscope-platform, which shadows the
editable checkout.

The post-install warning `These conda-packages will be overridden by pypi: …` is benign.

## Bumping library pins

A `requirements:` bump is a change in its own right, verified before and after the compile:

1. **Check the coupling first.** `pixi search -c <channel> "<lib>==<ver>"` prints the recipe's
   run deps; ext-custom hard-pins a platform range, so a lone ext-custom bump can fail the
   discovery solve. Bump both, matching the newest sibling specs' range (`grep -h -A1 "name:
   ecoscope-platform" ~/MEP/wt-workflows/*/spec.yaml`).
2. **Every task the spec names must exist at the target version.** From the library checkout:
   `git grep -l "^def <task>(" <tag> -- '*.py'` for each `task:` in the spec. Tasks migrate
   between libraries and get renamed (`set_base_maps_pydeck` in ext-custom → the platform's
   `set_base_maps` at 2.18; `create_polygon_layer_pydeck` moved to the platform under the same
   name). A bare name that exists in either library still resolves.
3. **Compare signatures with the spec's `partial:` keys** (`git show <tag>:<file>`); a removed
   parameter is a compile error, an added one is a form leak.
4. Carry the fleet's `pydeck 0.9.2` conda-forge re-statement when moving onto 2.18+.
5. Compile with `--clobber --update` and expect inner-lock churn; `--update` keeps `VERSION.yaml`.
6. **Re-check the card list** (`yq -p json '.properties | keys' <WF>/…/rjsf.json`). New
   user-facing params surface as extra cards named after the task id (2.18/2.19 added
   `create_polygon_layer_pydeck.tooltip_columns` and `draw_map.output_type`); bind them in
   `partial:` to the old behaviour. Then the mock cases and the § 4 accuracy check as usual.

## Variable references

| Syntax | Meaning |
|---|---|
| `${{ workflow.<id>.return }}` | a task's return value — **whole return only**; `.return.field` is not supported |
| `${{ env.<VAR> }}` | environment variable; `ECOSCOPE_WORKFLOWS_RESULTS` is the one intended for spec use |

Nestable inside lists and dicts in `partial` (nested resolution works on compiler ≥0.5.2).

## `map` / `mapvalues`

Both take `argnames` + `argvalues` (both-or-neither); one operation per instance.

- `map` iterates a plain sequence. One argname → each element passes directly to that parameter;
  **multiple argnames → each element is itself unpacked across them** — this is the
  `argnames: [view, data]` destructuring in every widget step.
- `mapvalues` iterates `(key, value)` 2-tuples, applying the function to the value and preserving
  the key. After `split_groups`, data is a keyed iterable, so **all per-group processing uses
  `mapvalues`**; the pipeline transitions to `map` at widget creation. `mapvalues` maps only ONE
  argname — use `groupbykey` + multi-argname `mapvalues` when a task needs several per-group
  inputs ([patterns.md](patterns.md)).

## `skipif`

`skipif: {conditions: [...], unpack_depth: 1}` — conditions are registered skip-task names (or
importable references), resolved against the registry at validation time.

| Condition | Use |
|---|---|
| `any_is_empty_df` | default via `task-instance-defaults` |
| `any_dependency_skipped` | default via `task-instance-defaults` |
| `all_geometry_are_none` | layer-creation tasks |
| `all_keyed_iterables_are_skips` / `any_keyed_iterables_are_skips` | keyed-iterable consumers (`groupbykey`) — pair with `unpack_depth: 1` |
| `never` | **widget tasks must use this** so placeholders are always created |

A per-instance `skipif` **replaces** the defaults entirely (no merging). Other registered skip
helpers: `any_dependency_is_none`, `any_dependency_is_empty_string`, `invert_bool`,
`maybe_skip_df`. Note `skip_gdf_fallback_to_none` is NOT a registered task and cannot appear in
`conditions` despite older docs listing it.

## Validation rules and wiring constraints

1. Spec `id`: Python identifier, ≤64 chars, not a keyword/builtin.
2. Task `id`s: Python identifiers, ≤32 chars, unique, **cannot equal any registered task name**
   (`id: temporal_index` for `task: add_temporal_index`, never `id: add_temporal_index`).
3. Dependencies must reference existing task ids, in topological order.
4. `map` and `mapvalues` are mutually exclusive per instance.
5. No field access on returns.

## Authoring idiom from real fleet specs

- **`partial:` is the primary form-control lever**: bound parameters are fixed; unbound parameters
  become form fields. Pin no-op params via `partial` to drop them from the config form. A partialized
  param must also be removed from `test-cases.yaml` — it becomes `extra_forbidden`.
- **Invisible glue tasks** carry no card: `set_string_var`, `default_if_string_is_empty`,
  `concat_string_vars` declared outside any group.
- **Card order = task order; field order inside a card = task order in the group/param order in the task signature.**
- **Prefer bare task names**; fully qualify only on genuine collisions.
- The recurring pipeline skeleton and per-widget chains live in [patterns.md](patterns.md).
