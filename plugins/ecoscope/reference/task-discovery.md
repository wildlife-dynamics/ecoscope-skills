# Task discovery — finding tasks, and fixing the ones that vanish

The compiler never imports task code itself. It resolves the spec's `requirements:` into an
ephemeral rattler env and shells out to `wt-registry` inside it. (Deliberate: importing task code
would force the compiler to install every library's deps — GDAL, plotting stacks — and hit version
conflicts.) Every "task not found" symptom traces back to one link of that chain.

## Contents
- Finding an existing task
- A task is missing: triage by symptom
- The discovery chain (mechanism)

## Finding an existing task

The inventory is large and moves with every release. Resolve it from what *this repo* pins, never
from a source checkout.

**List what's available** — run `wt-registry` in an env that has the task libraries installed.
Which env depends on whether this workflow has been compiled yet.

*With a compiled workflow*, its inner env already has them:

```bash
pixi run --manifest-path <inner>/pixi.toml --frozen -e default wt-registry --format pretty
```

*Before any compile* — a new workflow, or one that has never been compiled with `--install` —
there is no inner env to borrow, and the **outer** env is no help either: it holds `wt-compiler`,
`graphviz`, and `go-yq`, never task libraries. Build a throwaway env instead. `pixi exec` solves
and caches one on the fly, so this needs no workflow, no manifest, and no checkout:

```bash
pixi exec -c https://prefix.dev/ecoscope-workflows -c conda-forge \
  -s ecoscope-platform -s ecoscope-workflows-ext-custom -s wt-registry \
  wt-registry --format pretty
```

Add a `-s` per task library you intend to put in `requirements:` — the listing shows exactly the
libraries you name and nothing else. The first run pays a solve and download; later ones reuse the
cache (`pixi clean cache --exec` clears it). Because the specs here are unpinned, this answers
"does a task like this exist?" — once the spec pins real versions, re-check against the inner env,
which is the only listing that reflects what the workflow will actually compile against.

Filters, both repeatable: `--function NAME`, `--package PACKAGE`. `--format json` gives the
machine-readable form — `entries` keyed by fully-qualified name, each carrying `function_name`,
`public_module_path`, and a ready-made `import_statement`.

**See what this workflow already exposes**: the compiled `params.json` / `rjsf.json`.

**Turn the hit into a spec reference:**

- Prefer the **bare function name**. It survives internal module moves — in editable checkouts the
  registry can record a task under its private module after a refactor, breaking dotted references
  that worked yesterday.
- Qualify only on a genuine collision, using the **public re-export path** from
  `public_module_path` (e.g. `ecoscope.platform.tasks.config.set_traj_filters`) — never the private
  defining module. You don't need to know the collision set in advance: the compiler fails with
  `Multiple tasks named '<name>' found … Available modules: [...]`, and that list is the answer.

**Grepping the library** is a fair accelerator when you're hunting by concept rather than exact
name — but resolve the path from the environment, never from a checkout. Install locations differ
per machine and per install mode, so any hardcoded `~/...` path is wrong on someone else's box:

```bash
M=<inner>/pixi.toml
TASKS=$(pixi run --manifest-path "$M" --frozen -e default \
  python -c 'import ecoscope.platform.tasks as m; print(m.__path__[0])')
grep -rn --include='*.py' -A2 '@register(' "$TASKS" | grep 'def .*<concept>'
```

This needs an inner env for the same reason the listing above does. With no compiled workflow,
reach for the `pixi exec` listing instead — it answers the same "is there a task for this?"
question without needing a path at all.

`__path__[0]` resolves to site-packages for a conda install and to the source tree for an editable
one — either way it's the version this repo's pins actually select, which is the same principle as
everything else in this section.

Three things grep will not do for you:

- **It only sees the library you resolved.** Repeat the command for every task library in the
  spec's `requirements:` — swap in `ecoscope_workflows_ext_custom.tasks` and any per-workflow ext
  package. Resolving one and stopping hides the rest: `generate_etd_raster` lives in ext-custom, so
  a grep of `ecoscope.platform.tasks` alone reports nothing at all.
- **It gives you a function name, not a spec reference.** The file path it prints is never a valid
  reference — the reference is the public re-export path, which only `wt-registry` knows. Confirm
  the name there before writing it into the spec.
- **It cannot see re-exports or flag collisions.** A name that grep finds in two libraries looks
  identical to one found in a single library.

## A task is missing: triage by symptom

**Every task from one package is missing while other packages resolve** → a swallowed ImportError
in the discovery env, not a spec problem. `wt-registry`'s auto-discovery wraps each entry-point
import:

```python
try: importlib.import_module(ep.value)
except ImportError as e: print(f"Warning: Could not import {ep.value} ...", file=sys.stderr)
```

The ImportError is only a stderr warning, so every task in that package silently disappears and the
compiler discards the warning on exit-0. Reproduce it directly: build a scratch pixi env with the
spec's conda requirements plus python and uv, `uv pip install -e <package>`, then run
`<env>/bin/wt-registry --format json 2>err` and read stderr. The usual root cause is version skew —
the pinned `ecoscope-platform` doesn't provide something the task library's imports need. Fix by
aligning the pin with what the library branch actually imports.

**One task is missing** → work this checklist, in order of likelihood:

1. Not imported in the parent `tasks/<category>/__init__.py` (a subpackage with no `__init__.py` is
   dead even if its modules have `@register` functions).
2. Not re-exported → still registered, but reachable only at its **private** defining-module path,
   which no spec should reference.
3. Subpackage omitted from the package's build config (`setuptools.packages` enumerates each one
   explicitly in the ecoscope task library).
4. Package absent from the spec's `requirements:`.
5. The installed version in the discovery env predates the task — recompile after bumping the pin,
   or use an editable path requirement.

**The task lists in the registry but the compile still fails on it** → signature validation.
Validation and schema generation are lazy (on schema access), so a task can appear in the listing
yet fail when its schema is first built. The validator rejects async functions, classes, any
untyped parameter, and a missing return annotation. Every parameter and the return must be
annotated ([tasks.md](tasks.md)).

## The discovery chain (mechanism)

Read this when the triage above doesn't explain what you're seeing.

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
