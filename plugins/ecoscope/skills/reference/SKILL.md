---
name: reference
description: Use when answering questions about ecoscope workflow development that aren't attached to an active editing task — spec.yaml syntax, wt-compiler flags and errors, task discovery, rjsf overrides and form rendering, test-cases.yaml and mock-io, data connections (EarthRanger, SMART, GEE), publish gates and CI, Desktop preview or E2E testing — or when another skill needs a topic pointer into the knowledge base.
---

# Ecoscope reference index

The knowledge base lives at the plugin root: `${CLAUDE_PLUGIN_ROOT}/reference/`. Read only the
topic file(s) relevant to the question — each is self-contained, and files over 100 lines open
with a table of contents.

| Topic | File |
|---|---|
| The five environments, installing wt-compiler, standing rules (no `conda activate`, no `tail`, go-yq, renamed-repo breakage), preflight | `reference/environments.md` |
| Compile command, flags, compile-time rules (`--clobber`, `dot -c`, `--frozen`, editable post-compile), `--variant` rule, restore playbook, error table, fingerprints | `reference/compile.md` |
| spec.yaml schema, requirements (conda/PyPI/editable pin stacks), map/mapvalues, skipif | `reference/spec.md` |
| Finding an existing task (quick path at the top — stop there if it works); triage when a task is missing; the discovery chain | `reference/task-discovery.md` |
| Task anatomy, annotations, io tag, the tasks every workflow uses | `reference/tasks.md` |
| Pipeline skeleton, groupbykey, spatial-grouper chain, widget pipelines, dashboard | `reference/patterns.md` |
| rjsf override paths, task-group traps, title hiding, field rendering rules | `reference/rjsf.md` |
| Conditional form fields — the one working shape and the four failing ones | `reference/rjsf-conditionals.md` |
| test-cases.yaml, mock-io, overrides, run-test-cases.sh, live cases | `reference/testing.md` |
| Per-task gotchas (apply_sql_query, normalize_json_column, load_df, create_docx, …) | `reference/task-pitfalls.md` |
| Data connections, env-var format, CI secrets, GEE key recipe | `reference/connections.md` |
| Dashboard preview with synthetic data, Desktop on-disk contract, real-data runs | `reference/preview-desktop.md` |
| Desktop Playwright E2E authoring and its footguns | `reference/desktop-e2e.md` |
| CI gates (recompile diff, version gate), publication signals, tagging, deployment | `reference/publish-ci.md` |
| Repo anatomy, vendored files, repo-state signals, branch/commit conventions | `reference/repo-layout.md` |
| Output styling defaults (colormaps, layers, chart/table config) | `reference/output-style.md` |
| Where upstream docs are wrong / incomplete / excellent | `reference/upstream-docs.md` |
| Sensitive data, merge authorization, GitHub conventions | `reference/process-rules.md` |

Ground rules baked into every file: upstream docs are authoritative for concepts, the compiler's
pydantic models and real fleet specs for syntax (`reference/upstream-docs.md`); citations name
symbols, not line numbers; versions and per-repo facts point at where to verify rather than
freezing a value.
