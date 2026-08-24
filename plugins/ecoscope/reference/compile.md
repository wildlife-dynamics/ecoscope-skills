# Compiling a workflow

Single source for the compile command, its flags, its compile-time standing rules, and its failure
modes. Which environment to run in — and the standing rules that aren't compile-specific — live in
[environments.md](environments.md).

## Contents
- Canonical commands (dev and publish)
- Compile-time standing rules
- Flag reference
- `--variant=gcp` — deployment target, not convention
- `--update` semantics and VERSION behavior
- Restore playbook (when `--clobber` fails mid-way)
- Common compile errors
- Generated artifact layout
- Fingerprints (drift checking)

## Canonical commands

**Dev compile** — global `wt-compiler`, from the workflow repo root:

```bash
wt-compiler compile \
    --spec spec.yaml \
    --pkg-name-prefix=ecoscope-workflows \
    --results-env-var=ECOSCOPE_WORKFLOWS_RESULTS \
    --clobber --no-progress
```

Append exactly one of: nothing (iteration, no dep changes), `--install` (first compile / fresh
lockfile), or `--update` (dep bump on an existing workflow).

**Publish compile** — the repo's pinned compiler through the outer pixi env, mirroring *this
repo's* CI. Read the repo's `.github/workflows/_recompile.yml` and `dev/recompile.sh` (if present)
first, and run what they run. The common shape:

```bash
pixi update --manifest-path pixi.toml        # only if this repo's CI does it
pixi run --manifest-path pixi.toml dot -c
pixi run --manifest-path pixi.toml wt-compiler compile \
    --spec spec.yaml \
    --pkg-name-prefix=ecoscope-workflows \
    --results-env-var=ECOSCOPE_WORKFLOWS_RESULTS \
    --clobber --update --no-progress \
    [--variant=gcp]                          # only if this repo's CI passes it — see below
```

If CI runs `pixi update` on the outer manifest, commit the re-solved outer `pixi.lock` — a
floating compiler pin plus `pixi update` means CI silently picks a newer compiler, and codegen
drift (e.g. `Optional[X]` → `X | None`) makes CI's output differ from a compile against a stale
outer lock.

`--pkg-name-prefix=ecoscope-workflows` and `--results-env-var=ECOSCOPE_WORKFLOWS_RESULTS` are
fleet-invariant — always pass them, or the generated package defaults to the upstream `wt` /
`WT_RESULTS` names.

## Compile-time standing rules (each with its mechanism)

- **`--clobber` is destructive on failure.** A compile that dies mid-way leaves the generated dir
  gutted, and `--update` then refuses to run because `pixi.lock` / `VERSION.yaml` / `README.md`
  are missing. Know the restore path before running it — see the restore playbook below.
- **After any outer-env re-solve, run `pixi run --manifest-path pixi.toml dot -c` before
  compiling.** conda's graphviz ships an unregistered plugin cache; without this the compile dies
  at the graph.png step with `Format: "png" not recognized` — after `--clobber` already emptied
  the dir. Declaring `graphviz` in `pixi.toml` is not sufficient: the cache file is generated,
  not shipped, and the package delegates generating it to a post-link script that pixi skips
  unless `--run-post-link-scripts` is passed. That is why a re-solve keeps re-breaking it.
- **Use `--frozen`, not `--locked`, when git-tag deps are present.** pixi resolves a git-tag dep
  to a SHA in the lockfile but compares it symbolically, so `--locked` reports the lock stale
  forever, even immediately after `pixi lock`.
- **Editable ecoscope requires the post-compile patch script after every compile**
  (`./dev/postcompile-editable.sh`), and pins must revert to released versions before publish —
  CI rejects `path:`/`editable:`. See [spec.md](spec.md) for the full editable pin stack.

Environment selection and the non-compile standing rules (never `conda activate`, never pipe
through `tail`, renamed-repo-dir breakage, go-yq) stay in [environments.md](environments.md).

## Flag reference

`compile` has exactly these flags (the CLI has exactly two subcommands: `compile` and
`scaffold init` — no `init`, `get`, `run`, `validate`, or `lint`):

| Flag | Default | Effect |
|---|---|---|
| `--spec FILE` | required | resolved absolute; errors if missing |
| `--clobber` | off | overwrite the output dir; without it an existing release dir raises `FileExistsError` |
| `--update` | off | carry lockfile forward, bump version (see semantics below) |
| `--install` | off | run `pixi install -a` on the generated manifest |
| `--pkg-name-prefix` | `wt` | ecoscope uses `ecoscope-workflows` |
| `--results-env-var` | `WT_RESULTS` | ecoscope uses `ECOSCOPE_WORKFLOWS_RESULTS` |
| `--variant VARIANT` | none | e.g. `gcp` — see below |
| `--no-progress` | off | auto-disabled when stderr isn't a TTY |
| `--env-overrides PATH` | none | TOML fragment layered over bundled dep injections; dev only |

One mutual-exclusion rule, asymmetric: `--update` requires `--clobber` and forbids `--install`;
`--clobber --install` together is fine.

Compiling without `--install` on a fresh workflow succeeds but produces no `pixi.lock`, so
`run-test-cases.sh` fails until you compile with `--install`.

## `--variant=gcp` — deployment target, not convention

`--variant=gcp` is determined by **where the workflow deploys**: workflows deployed to Ecoscope
**Web** require it; **Desktop-only** workflows do not. Mechanism: the flag rewrites the
compiler-injected deps `wt-task`→`wt-task-gcp` and `wt-runner`→`wt-runner-gcp` (with
`wt-invokers-gcp` arriving transitively). The GCP metapackages add OpenTelemetry, Cloud Batch,
and Pub/Sub support — Web executes via Cloud Batch with tracing; Desktop runs a local subprocess
and needs none of it. (Metapackages exist because conda has no pip-style extras.) It is not
applied to spec-declared requirements.

The repo's own `_recompile.yml` / `dev/recompile.sh` records the decision for that workflow —
read it before a publish compile, as confirmation of the rule, and never assert the flag
universally. Committing a gcp compile to a non-gcp repo fails CI's "Generated files differ" check
in the opposite direction from the usual gotcha. Do not pass `--variant=gcp` on dev compiles.

## `--update` semantics and VERSION behavior

- `--update` **requires** a pre-existing `pixi.lock`, `VERSION.yaml`, **and `README.md`** in the
  release dir, or it raises `FileNotFoundError`. It copies `pixi.lock` forward verbatim and bumps
  VERSION: **MAJ+1/MIN=0 if `params_sha256` changed, else MIN+1**.
- Without `--update`, a compile **resets `VERSION.yaml` to `{MAJ: 0, MIN: 0, PATCH: 0}`** and
  carries no lockfile (a dev compile also deletes the committed `pixi.lock`).
- Because CI's generated-files diff excludes `VERSION.yaml`/`pixi.lock`/`README.md`/`graph.png`,
  the publish procedure writes the intended VERSION *after* the final compile and restores the
  lockfile if a dev compile clobbered it (`git checkout HEAD -- <WF>/pixi.lock`).

**Never dev-compile a publish-state tree.** Publish state = committed inner `pixi.lock`,
VERSION > 0.0.0, and `wt-task-gcp`/`wt-runner-gcp` in the inner `pixi.toml`. A casual global-dev
compile strips the gcp variant, resets VERSION, deletes the lockfile, and churns
README/graph.png/tests. Recover by restoring env files from HEAD and re-running the pinned
publish compile.

## Restore playbook (when `--clobber` fails mid-way)

A compile that dies after `--clobber` leaves the generated dir gutted. Restore the whole generated
tree from the base branch — not just lock+VERSION, since `--update` also needs `README.md`:

```bash
git checkout <base> -- <prefix>-<id>-workflow/
```

Then fix the cause and re-run. Transient causes seen in practice: prefix.dev fetch flakes
(`failed to fetch <pkg>.conda … connection closed via error`, a different package each attempt) —
just retry, each attempt progresses via the cache; 2–3 attempts usually suffice.

## Common compile errors

| Error | Cause / fix |
|---|---|
| `Task '<name>' not found in known tasks` | Discovery didn't see it — see [task-discovery.md](task-discovery.md). If EVERY task from one package is missing, it's a silent ImportError in the discovery env, not a spec problem. |
| `Multiple tasks named '<name>' found` | Name collision across libraries — fully qualify with the public module path ([task-discovery.md](task-discovery.md)). |
| Task ID conflict | `id:` matches a registered task name; use a different id. |
| `ruff format exit status 2` | Generated Python has syntax errors (historically: single quotes in inline SQL strings; fixed in current compilers — upgrade if seen). |
| `--update` rejection | `--update` needs `--clobber` and no `--install`. |
| `Format: "png" not recognized` | graphviz plugin cache unregistered — run `dot -c` in the compile env (see the compile-time standing rules above). |
| `ModuleNotFoundError: No module named 'jsonschema'` | Broken compiler tool env — repair recipe in [environments.md](environments.md). |
| `Error launching 'wt-compiler': No such file or directory` | Renamed repo dir; `pixi clean && pixi install` both envs ([environments.md](environments.md)). |
| Solve failure hoisting python/conda-forge | An explicit channel-less `python` requirement in a publish spec — remove it ([spec.md](spec.md)). |

## Generated artifact layout

Everything under `<prefix>-<id>-workflow/` is generated (every file carries an
`# AUTOGENERATED` header) and committed:

```
<prefix>-<id>-workflow/
├── pixi.toml pixi.lock VERSION.yaml Dockerfile .dockerignore
├── pyproject.toml hatch_build.py
├── README.md          # fingerprint block — see below
├── graph.png          # best-effort; warns if graphviz dot is missing
├── tests/{conftest,test_metadata,test_results}.py
└── <prefix>_<id>_workflow/
    ├── __init__.py cli.py dispatch.py metadata.py response.py
    ├── params.json rjsf.json
    └── dags/{__init__,run_sequential,run_sequential_mock_io}.py
```

There is **no `params.py` and no `formdata.py`** — older docs listing them are stale. Never
hand-edit anything under the generated tree; change `spec.yaml` and recompile. `dev/` and
`.github/workflows/` are *not* produced by `compile` — they are vendored from the ecoscope-hub
template ([repo-layout.md](repo-layout.md)).

## Fingerprints (drift checking)

The generated `README.md` carries a fingerprint block:
`artifacts_sha256_basic`, `artifacts_sha256_strict`, `params_sha256`, `spec_sha256`, and
`installed_requirements` (name/version/channel per requirement). Facts that matter:

- `spec_sha256` is a hash of the parsed spec alone (`Spec.sha256`), computable in milliseconds
  **without compiling** — an input-side check that proves staleness conclusively but never proves
  freshness. Note it **excludes `requirements` and `metadata`**, so also diff the spec's
  `requirements:` against the recorded `installed_requirements` — a pin bump doesn't move the hash.
- The artifact hashes are computed *from* the artifacts, so a fresh one requires compiling. When
  comparing after a recompile, use **`artifacts_sha256_strict`** (excludes only spec_relpath,
  pydot_graph, readme_md — aligned with CI's exclusions). `basic` additionally drops `dockerfile`
  and `pixi_toml`, so **basic cannot see a variant mismatch** (the variant only changes pixi.toml).
- **Never use `params_sha256` for drift.** It strips functionally-irrelevant keys first — it
  answers "must users reconfigure saved workflows?" (it drives the MAJ-vs-MIN bump), not "did the
  output change?". Titles and defaults are invisible to it, and those are the most-iterated
  surface in the fleet.
- The **compiler version is not in the fingerprint**, so codegen drift at a different compiler
  version is invisible to every cheap check — only a real CI-matching recompile finds it.
