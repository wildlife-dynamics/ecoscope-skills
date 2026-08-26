# Task discovery — finding tasks, and fixing the ones that vanish

The compiler never imports task code itself. It resolves the spec's `requirements:` into an
ephemeral rattler env and shells out to `wt-registry` inside it. (Deliberate: importing task code
would force the compiler to install every library's deps — GDAL, plotting stacks — and hit version
conflicts.) Every "task not found" symptom traces back to one link of that chain.

## Contents
- Finding an existing task — quick path; source scan, registry, compiled artifacts; the signature
- A task is missing: triage by symptom
- The discovery chain (mechanism)

## Finding an existing task

The inventory is large and moves with every release, so no written list stays true.

### Quick path

1. **Find the name** — `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/search-tasks.py --lib <tasks-dir>
   <keyword>` (no env; scans a checkout or installed package).
2. **Read how to use it** — same script with `-s <name>`: full signature + docstring.
3. **Confirm it resolves** — `wt-registry --function <name>` in the compiled env; this is the only
   source of the public path, and the only view of what the spec's pins actually contain.
4. **Reference it by bare name** in `spec.yaml`; fully qualify only when the compiler reports a
   collision.

**Everything below this line is detail and triage — stop here if the quick path worked.** The
methods follow in the order you use them; authority runs the other way, and the registry has the
last word.

### 1. Scan the source — fastest, not authoritative

Answers "is there something for this, and what is it called?" when you're hunting by concept rather
than by exact name. The plugin ships `scripts/search-tasks.py`, a pure-AST scan for `@register`
functions — no environment, and the full listing of ~300 tasks is ~15 KB:

```bash
S=${CLAUDE_PLUGIN_ROOT}/scripts/search-tasks.py
python3 $S --lib <tasks-dir> [--lib <tasks-dir>] <keyword>   # names + defining module
python3 $S --lib <tasks-dir> -s <name>          # signature + docstring, every definition
python3 $S --lib <tasks-dir>                    # full listing; collisions flagged
```

`--lib` (repeatable, or `ECOSCOPE_TASK_LIBS=<dir>:<dir>`) takes any directory inside a task
package. Two things you can point it at, with different guarantees:

- **A checked-out task library** — instant, and its recall over that tree is complete. But a
  checkout is whatever branch and commit you happen to have, which is routinely ahead of or behind
  what the spec pins; the gap is widest on a feature branch. A task that exists only in the
  checkout fails the compile with `Task '<name>' not found in known tasks` while its source sits
  visibly on disk.
- **The installed package** — matches the pins, at the cost of needing an env. Resolve the path
  instead of hardcoding it, since install location varies per machine and per install mode:

```bash
M=<inner>/pixi.toml
TASKS=$(pixi run --manifest-path "$M" --frozen -e default \
  python -c 'import ecoscope.platform.tasks as m; print(m.__path__[0])')
python3 $S --lib "$TASKS" <keyword>
```

(`--frozen` skips pixi's lock check, so these commands also work when git-tag requirements make
`--locked` report the lock stale; on a plain env `--locked`, which the test harness uses, is
equivalent.) `__path__[0]` resolves to site-packages for a conda install and to the source tree for an editable
one.

**The scan errs in one direction only:** it can show you a task that your pinned registry doesn't
have, but it will never hide one that it does. That makes it safe for exploring and unsafe as the
last word — confirm the name in the registry before it reaches the spec.

**Further limits:** it sees only the roots you pass, so pass one per library in `requirements:`;
the module it prints is the *defining* module, never a spec reference (the spec takes the bare
name, or the registry's public path); and it cannot see re-exports, `io` tags, or deprecation. It
does flag a name defined in more than one library — the compile-blocking collision case.

### 2. Ask the registry — authoritative

Answers exactly which tasks the compiler will resolve, and at which public path — confirm every
scan hit here before it reaches the spec. Which env you run it in depends on whether this workflow
has been compiled yet.

*Compiled workflow* → borrow its inner env. This is the only listing that reflects what the
workflow will actually compile against:

```bash
pixi run --manifest-path <inner>/pixi.toml --frozen -e default wt-registry --format pretty
```

*No compile yet* → build a throwaway env. The outer env is not a substitute: it holds
`wt-compiler`, `graphviz`, and `go-yq`, never task libraries. `pixi exec` solves and caches one on
the fly, needing no workflow, no manifest, and no checkout:

```bash
pixi exec -c https://prefix.dev/ecoscope-workflows -c conda-forge \
  -s ecoscope-platform -s ecoscope-workflows-ext-custom -s wt-registry \
  wt-registry --format pretty
```

One `-s` per library you intend to declare — the listing shows those and nothing else. First run
pays a solve and a download; later ones reuse the cache (`pixi clean cache --exec` clears it).
These specs are unpinned, so treat the result as "does such a task exist?" and re-confirm against
the inner env once the spec pins versions.

Filters, both repeatable: `--function NAME`, `--package PACKAGE`. `--format json` returns `entries`
keyed by fully-qualified name, each with `function_name`, `public_module_path`, a ready-made
`import_statement`, and a `json_schema` — the form-facing parameters with `type`, `default`,
`description`, and `ecoscope:advanced`. That schema is what `partial:` literals are written
against, but it is **not the signature**: parameters with `Field(exclude=True)` (the dataframe /
wire inputs such as `df`) are dropped from `properties` and survive only as a name in `required`,
and the return type is absent. `--format pretty` shows no parameters at all.

**Never dump the unfiltered output into context.** A typical inner env lists ~230 tasks: `--format
json` is ~480 KB (well over 100k tokens), `--format pretty` ~50 KB. Always narrow with
`--function NAME`, or `grep '^=== '` the pretty listing for names only, then fetch the one schema
you need.

**Cost:** needs an environment — a solve, and a download on first use.

### 3. Read the compiled artifacts — what this workflow already uses

The generated `params.json` / `rjsf.json` list the tasks this workflow already exposes, with their
parameters as the form sees them. Narrowest scope of the three, and the quickest way to answer
"what is this workflow already doing?" or to lift a known-good reference from a sibling workflow.

### Read the signature

Neither the registry nor `params.json` says what a task returns or how its wired inputs are typed,
and that is what `${{ }}` wiring depends on. Two routes to the full signature and docstring:
`search-tasks.py -s <name>` reads it from source (no env; shows every definition when the name
collides), and — the ground truth for the pinned version — `@register` returns the bare
function, so the inner env answers directly; take the import line from `import_statement`:

```bash
pixi run --manifest-path <inner>/pixi.toml --frozen -e default python -c '
import inspect
from <public_module_path> import <name> as f
print(inspect.signature(f)); print(f.__doc__)'
```

**Prefer this over the registry schema or `params.json` when deciding how to use a task.** It is
the one source with everything at once — every parameter including the excluded wire inputs, the
full `Annotated`/`Field` metadata, the return type, and the docstring, which often carries usage
patterns the schema can't (template snippets, examples). The `-s` route is the same information
from a checkout, with the checkout-vs-pin caveat above; use the inner-env route when the two may
differ.

### Turn the hit into a spec reference

- Prefer the **bare function name**. It survives internal module moves — in editable checkouts the
  registry can record a task under its private module after a refactor, breaking dotted references
  that worked yesterday.
- Qualify only on a genuine collision, using the **public re-export path** from
  `public_module_path` — never the private defining module. You don't need the collision set in
  advance: the compiler fails with `Multiple tasks named '<name>' found … Available modules: [...]`,
  and that list is the answer.

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
