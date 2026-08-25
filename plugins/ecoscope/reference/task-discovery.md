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

**List what's available** — run `wt-registry` in an env with the libraries installed; the compiled
workflow's inner env qualifies:

```bash
pixi run --manifest-path <inner>/pixi.toml --frozen -e default wt-registry --format pretty
```

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

A source-tree grep is at best an accelerator. File paths are not valid spec references, re-exports
are invisible to it, and colliding names appear side by side with nothing marking them as
ambiguous.

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
