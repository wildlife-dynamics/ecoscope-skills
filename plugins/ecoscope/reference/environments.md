# Environments

The single most common way ecoscope workflow work goes wrong is running the right command in the
wrong environment. There are **five** environments, they are deliberately isolated (the compiler's
dep stack and the geospatial task stack conflict), and the failure mode is usually not a clean
error — it's a misleading one: a compile that exits 0 having gutted the generated dir, a
`ModuleNotFoundError: click` that looks like a broken workflow, a "task not found in known tasks"
that is actually an ImportError swallowed in a subprocess.

**Every procedure names its environment in its first line.** This file is the single authoritative
table.

## Contents
- The five environments
- Why publish compiles go through pixi
- Installing wt-compiler
- Standing rules (each with its mechanism)
- Preflight

## The five environments

| Job | Environment | Invocation |
|---|---|---|
| Dev compile | the machine-global `wt-compiler` install (uv tool or pixi global — see below) | `wt-compiler compile …` directly, from the workflow repo root |
| Publish compile | the workflow repo's **outer** pixi env, at the repo's **pinned** compiler version | `pixi run --manifest-path pixi.toml wt-compiler compile …`, mirroring that repo's CI exactly — see [compile.md](compile.md) |
| Test | the workflow repo's **inner** pixi env (the generated `*-workflow/` package) | `./dev/run-test-cases.sh` (wraps `pixi run --manifest-path <inner>/pixi.toml --locked -e default`) |
| Task-library dev | the task library repo's own pixi env, or a shared editable dev workspace if one is configured | `pixi run` from inside the library repo |
| wt package dev | uv, per package, inside the wt monorepo checkout | `uv sync && uv run pytest` in the package dir |

The outer pixi env (repo-root `pixi.toml`) is the *compile* env: `wt-compiler`, `graphviz`,
`go-yq`, plus `[tool.wt] published`. The inner pixi env (generated `<prefix>-<id>-workflow/pixi.toml`)
is the *runtime* env: the workflow package and its task-library deps.

## Why publish compiles go through pixi

CI compiles with the repo's *pinned* compiler version, and compiler releases change codegen
(0.8.2→0.8.3 changed `collections.abc` imports and combined `with` statements). Compiling with a
newer global compiler produces output that differs from CI's, and the CI `recompile-workflows` job
then fails on a diff you cannot reproduce locally. Dev compiles don't care; publish compiles must
match byte-for-byte, so they run the pinned compiler through the outer pixi env.

## Installing wt-compiler

Two supported styles — know which one a machine uses, because the graphviz story differs:

1. **Upstream path (released build):**
   ```console
   pixi global install -c https://prefix.dev/ecoscope-workflows -c conda-forge \
       wt-compiler --run-post-link-scripts
   ```
   `--run-post-link-scripts` runs `dot -c` automatically (it permits arbitrary post-link scripts;
   the manual alternative is running `dot -c` from the pixi env's bin dir).

2. **Editable path (developing the compiler itself):** a `uv tool install --editable` build
   pointing at the local wt monorepo checkout. This style does NOT get the automatic `dot -c`,
   which is why the graphviz plugin-cache failure keeps recurring on editable setups — see
   the `dot -c` rule in [compile.md](compile.md).

## Standing rules (each with its mechanism)

- **Never `conda activate` / `source activate`.** Everything is pixi or uv.
- **Never pipe a compile or pixi invocation through `tail`** (or anything else that eats the exit
  code). This has produced two separate silent failures: a graphviz error *after* `--clobber` had
  already emptied the output dir, and a dead entry-point shebang after a directory rename — both
  masked as apparent success.
- **`yq` must be go-yq (mikefarah), not the Python `yq` (kislyuk).** `dev/run-test-cases.sh`
  depends on the go syntax; the two CLIs are incompatible.
- **A renamed workflow-repo directory breaks both pixi envs while they still look installed.**
  Entry-point shebangs keep the old absolute path; `pixi install` reports success without
  relinking; compiled binaries (`dot`) still work but Python entry points die with
  `Error launching 'wt-compiler': No such file or directory (os error 2)`. Fix:
  `pixi clean --manifest-path pixi.toml && pixi install` on outer **and** inner, then `dot -c`.

## Preflight

This plugin ships `scripts/preflight.sh [<workflow-repo-dir>]`, which discovers and *reports*
(never silently repairs) the global tooling: whether `wt-compiler` runs and its env can import
`jsonschema` (printing the repair command built from the discovered install — interpreter from
the launcher, editable root from where `wt_compiler` imports), its version, whether graphviz
`dot` actually renders PNG (the plugin-cache check), whether `yq` is go-yq, and the pixi
version. Run inside a workflow repo it also lists the outer `pixi.toml` compiler pin against the
global version and every `spec.yaml` requirement with its pin. Exit 1 on any `FAIL`. It does not
read CI files or probe the pixi envs — the renamed-dir breakage above shows up as
`Error launching …` on the first `pixi run`, and the CI recompile flags are read from the repo by
the publish procedure. Skills open with "run preflight, fix any FAIL" — a few seconds that avoid
the class of failure that otherwise costs a whole debugging detour.
