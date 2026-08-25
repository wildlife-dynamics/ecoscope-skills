# Reference sources — what exists, and which one wins

Three tiers, in order of authority. When they disagree, the higher tier is right.

1. **Code** — the source of truth, always.
2. **Upstream docs** — wt framework docs and Platform SDK docs; good for vocabulary and mental
   model, not for syntax.
3. **Workflow examples** — real repos to copy shapes from when the docs don't show how.

Citations in this suite name **symbols** (`TaskInstance` in `wt_compiler.spec`), not line numbers;
locate any module with `python -c "import <module> as m; print(m.__file__)"`.

## Contents
- Source of truth: the code
- Upstream docs (local paths + URLs)
- Workflow examples

## Source of truth: the code


#todo: replace local absolute path with UserConfig in the plugin metadata
Docs drift; code doesn't. Read the code before trusting a tutorial, and cite the code when a doc
and the code disagree.

| Repo (local checkout) | GitHub | What it is authoritative for |
|---|---|---|
| `~/MEP/infra/wt` | `wildlife-dynamics/wt` | The wt framework monorepo: `wt-compiler` (spec schema — the pydantic models in `wt_compiler.spec`: `Spec`, `TaskInstance`, `TaskGroup`), `wt-contracts`, `wt-registry`, `wt-task`, `wt-runner`, `wt-invokers`, plus the `-gcp` variants |
| `~/MEP/wt-tasks/ecoscope` | `wildlife-dynamics/ecoscope` | The `ecoscope` library and the **Platform SDK** tasks (`ecoscope/platform/`) — what every built-in task actually accepts and returns; also the source the SDK reference pages are generated from |
| `~/MEP/wt-tasks/ecoscope-workflow-task-library` | `wildlife-dynamics/ecoscope-workflow-task-library` | Custom/extension tasks (`ecoscope_workflows_ext_custom/tasks/`) |
| `~/MEP/infra/ecoscope-server` | `wildlife-dynamics/ecoscope-server` | The backend: workflow templates, runs, results, layout, rjsf handling, named connections (`ecoscope_server/services/`, `ecoscope_server/utils/rjsf.py`, `utils/er_enum_resolver.py`) |
| `~/MEP/infra/ecoscope-web` | `wildlife-dynamics/ecoscope-web` | The UI: rjsf form rendering, results grid, desktop server contract (`src/utils/actions/workflow-*`) |
| `~/MEP/infra/compose` | `wildlife-dynamics/compose` | Deployment: `docker-compose.yaml`, per-environment build-deploy pipelines, and the submodule pins under `ecoscope-platform-workflows-releases/<template>` that decide which catalog workflow version reaches dev/stage/prod ([web-deployment.md](web-deployment.md)) |

Practical rule: for spec syntax read `wt_compiler.spec`; for a task's parameters read the task's
signature in the task library; for how a form or dashboard renders read ecoscope-web; for what
the server does with a run read ecoscope-server; for what is deployed where read compose.

## Upstream docs

Two doc trees. Both are mkdocs-material; read the markdown directly from the local checkout (no
build needed) or browse the hosted site.

### wt framework docs

- Local: `~/MEP/infra/wt/docs/content/` (serve with `cd ~/MEP/infra/wt/docs && uv run mkdocs serve`)
- Hosted: not published as a site — the local tree is the copy to read
- Pages: `concepts.md`, `getting-started.md`, `tutorials.md`, `architecture.md`, `changelog.md`,
  and `reference/{spec-yaml,wt-contracts,wt-registry,wt-task,wt-compiler,wt-invokers,wt-runner}.md`

Best for: the key-terms vocabulary (registered function / task / task instance / registry /
compiled workflow / invoker / runner / metapackage), and the architecture *whys* (subprocess
discovery, compile-don't-interpret, fingerprinting, GCP metapackages, `map` argname semantics).

### Platform SDK docs

- Local: `~/MEP/wt-tasks/ecoscope/doc/platform-sdk/content/` (serve with `mkdocs serve` from
  `doc/platform-sdk/`)
- Hosted: <https://ecoscope.io/en/latest/platform-sdk/>
- Pages: `concepts.md`, `getting-started.md`, `understanding-spec.md`, `built-in-tasks.md`,
  `examples.md`, `troubleshooting.md`, `tutorials/{first-custom-task,data-sources,widgets,groupers,form-customization}.md`,
  and `reference/` (per-category task pages under `reference/tasks/`, plus `schemas`,
  `connections`, `indexes`, `annotations`, `jsonschema`, `mock_loaders`)

Best for: the groupers tutorial's `map` vs `mapvalues` explanation, the form-customization
tutorial's `partial` section (bound parameters are fixed; unbound become form fields) and the
`Field` → `AdvancedField` → `json_schema_extra` ladder, and the Desktop dev loop in
getting-started (import the repo root; refresh = delete + re-import).

Caveat that applies to both trees: syntax examples in tutorials are not reliable — several are
outdated or invented. Use them to learn *what* a feature is for, then confirm the *shape* against
the compiler models and a real spec before writing it. The suite's topic files
([spec.md](spec.md), [rjsf.md](rjsf.md), [patterns.md](patterns.md), [testing.md](testing.md))
already carry the verified shapes.

## Workflow examples

When the docs don't show how to do something, find a repo that already does it and copy the
shape. Prefer the most recently published wt-framework repos; treat legacy-framework repos as
history, not as templates.

**Published wt-framework repos** (`~/MEP/wt-workflows/`, all under `github.com/wildlife-dynamics/`):

| Repo | Why look at it |
|---|---|
| `wt-download-events`, `wt-download-patrols`, `wt-download-subjects` | Published, tagged, full CI/staging lifecycle; EarthRanger download + filtering patterns |
| `wt-ndvi` | Published; GEE connection and raster pattern |
| `patrol-effort-table`, `patrol-chart`, `patrol-encounter-rate-map` | Tagged patrol analyses — groupers, tables, charts, maps |

**Production catalog workflows** (`~/MEP/wt-workflows/{patrols,events,event-details,subject-tracking}`,
under `github.com/ecoscope-platform-workflows-releases/`): the templates shipped in the ecoscope
web/desktop catalog, tagged on `main` (`v9.x` / `v3.x`), vendored into compose for deployment
([web-deployment.md](web-deployment.md)). Richest examples of complete dashboards — groupers,
time-density maps, event/patrol tables and charts, `layout.json`. They are on the legacy
`ecoscope-workflows` framework and layout (no `dev/`, no outer `pixi.toml`, committed
`__results_snapshots__/`), so copy their task chains and output shapes, not their repo scaffold.
