# Task discovery — how tasks become visible, and how they silently vanish

The compiler never imports task code itself. It resolves the spec's `requirements:` into an
ephemeral rattler env and shells out to `wt-registry` inside it. (This is deliberate: importing
task code would force the compiler to install every library's deps — GDAL, plotting stacks — and
hit version conflicts.) Every "task not found" symptom traces back to one link of this chain.

## Contents
- The discovery chain
- The silent-ImportError failure (whole package vanishes)
- What makes a single task vanish
- Name collisions (bare vs qualified references)
- Finding tasks: ask the tooling, not the filesystem
- Registered but failing: signature validation

## The discovery chain

1. **`@register()`** at import time does no validation and no schema generation — it stores a
   registry entry in a process-global dict keyed by fully-qualified name. Duplicate FQN raises
   `DuplicateRegistrationError`.
2. **The entry point triggers the imports.** Each task library declares
   ```toml
   [project.entry-points."wt_registry"]
   tasks = "package_name.tasks"
   ```
   The entry-point *key* is arbitrary; the *value* is the module `wt-registry` imports. Without
   this entry point the compiler cannot find the package's functions at all.
3. **`__init__.py` re-exports determine the importable path.** `wt-registry` walks imported
   packages for the *shortest public* module re-exporting each function and records it as
   `public_module_path` (falling back to the private defining module if not re-exported). The
   compiler builds `importable_reference = public_module_path + "." + function_name`, and that
   string becomes the generated `from X import Y`.
4. The compiler parses `wt-registry --format json` output into its known-tasks table, keyed by
   function name then module.
5. **Name resolution in the spec:** a bare name is looked up; if more than one module provides it,
   compile fails with `Multiple tasks named '<x>' found … must be fully qualified`. A dotted name
   resolves as anchor-module + name. Unknown → `Task '<x>' not found in known tasks`.

## The silent-ImportError failure

`wt-registry`'s auto-discovery wraps each entry-point import:

```python
try: importlib.import_module(ep.value)
except ImportError as e: print(f"Warning: Could not import {ep.value} ...", file=sys.stderr)
```

**An ImportError is only a stderr warning** — every task in that package silently disappears, and
the compiler discards the warning on exit-0. So: **if EVERY task from one package fails as "not
found in known tasks" while other packages validate, the cause is a swallowed ImportError in the
discovery env, not a spec problem.**

Reproduce it directly: build a scratch pixi env with the spec's conda requirements plus python and
uv, `uv pip install -e <package>`, then run `<env>/bin/wt-registry --format json 2>err` and read
stderr. The usual root cause is a version skew — the pinned `ecoscope-platform` doesn't provide
something the task library's imports need; fix by aligning the pin with what the library branch
actually imports.

## What makes a single task vanish

Checklist, in order of likelihood:

1. Function not imported in the parent `tasks/<category>/__init__.py` (a subpackage with no
   `__init__.py` is dead even if its modules have `@register` functions).
2. Function not re-exported → it's still registered, but only reachable at its **private**
   defining-module path (`…tasks.results._pydeck.create_geoarrow_scatterplot_layer`-style), which
   no spec should reference.
3. Subpackage omitted from the package's build config (`setuptools.packages` enumerates each one
   explicitly in the ecoscope task library).
4. Package absent from the spec's `requirements:`.
5. The installed version in the discovery env predates the task — recompile after bumping the pin
   or use an editable path requirement.

## Name collisions

**13 names collide** between `ecoscope-platform` and `ecoscope-workflows-ext-custom`; a spec that
lists both libraries must fully qualify these (bare reference = hard compile error):

`drop_null_geometry`, `generate_etd_raster`, `get_bounding_box`, `get_filter_point_coords`,
`get_gps_point_filename_prefix`, `get_gps_point_filetypes`, `get_segment_filter`,
`get_skip_relocation_persist`, `get_track_filename_prefix`, `get_track_filetypes`,
`invert_bool`, `set_download_params`, `set_traj_filters`.

(Re-verify with `wt-registry` when pins move — the list grows as config tasks get upstreamed;
e.g. platform 2.17 upstreamed several ext-custom config tasks, which is what created most of
these.)

Qualified references use the **public re-export path**, e.g.
`ecoscope.platform.tasks.config.set_traj_filters` or
`ecoscope_workflows_ext_custom.tasks.spatial_ops.calculate_encounter_rate_grid`. Everywhere else,
prefer the bare name — it's immune to internal module moves (in editable checkouts the registry
can record a task under its private module after a refactor, breaking dotted references that
worked yesterday).

## Finding tasks: ask the tooling, not the filesystem

The inventory is large (roughly 240 tasks in `ecoscope-platform` + 65 in ext-custom — far beyond
the "~80" older docs claim) and moves with every release. Resolve it from what *this repo* pins,
never from a source checkout:

- **`wt-registry --format pretty`** in an env with the libraries installed (the compiled
  workflow's inner env qualifies) — the authoritative list, with public paths. Filters:
  `--function NAME` (repeatable), `--package PACKAGE` (repeatable).
- **The compiled `params.json` / `rjsf.json`** — what this workflow actually exposes.
- A source-tree grep or helper script is at best an accelerator. Known traps if one is used: an
  AST scan prints *file-derived* module paths that are **not valid spec references** (the real
  reference is the `__init__.py` re-export path), cannot see re-exports at all, misses
  per-workflow ext packages, and shows colliding names side by side without flagging them.

To turn a candidate hit into a reference the compiler will resolve: prefer the bare name; on
collision, take the `public_module_path` from `wt-registry` output and append the function name.

## Registered but failing: signature validation

Validation and schema generation are lazy (on schema access). The validator rejects async
functions, classes, any untyped parameter, and a missing return annotation — so a task can appear
in the registry listing yet fail at compile when its schema is first built. Every parameter and
the return must be annotated ([tasks.md](tasks.md)).
