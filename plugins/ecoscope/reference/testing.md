# Testing workflows

`test-cases.yaml`, the mock-io machinery, and the test harness. Environment rules in
[environments.md](environments.md).

## Contents
- The two test layers
- test-cases.yaml idiom
- test-cases gotchas
- How mock-io works
- `mock_io_overrides` — per-case fixture overrides
- `dev/run-test-cases.sh`
- Template paths and raw URLs
- Live cases

## The two test layers

1. **Generated pytest suite** (`tests/` in the generated package) — conftest reads
   `../test-cases.yaml` into `wt_runner.testing.Case`
   (`name, description, params, raises=False, expected_status_code=200`); requires `--case NAME`
   (repeatable); asserts JSON snapshots, Playwright PNG snapshots of widget iframes, and OTel
   span trees. **`mock_io` and `mock_io_overrides` are NOT `Case` fields** — only the shell
   harness reads them.
2. **`dev/run-test-cases.sh`** — the fleet harness; bypasses pytest and drives the generated CLI
   directly. This is the day-to-day loop.

The generated CLI:
`python -m <pkg>.cli run --config-file F|--config-json J --execution-mode sequential
[--mock-io|--no-mock-io]` — `sequential` is the only valid execution mode (docs advertising
`async` are stale); also `get rjsf|params|data-connection-property-names` and
`convert --from … --to …`. It reads `ECOSCOPE_WORKFLOWS_RESULTS` (errors if unset) and writes
`result.json` = `{"result": …, "error": …, "trace": …}` there.

## test-cases.yaml idiom

Top-level map `case-id → {name, description, mock_io, mock_io_overrides, params}`; **`params`
keys are flat task ids** (task-group titles never appear — the compiled model is flat).

```yaml
base:
  name: Base case
  mock_io: true
  params:
    workflow_details: {name: "Patrol Effort", description: "…"}
    er_client_name: {data_source: {name: "er_asia"}}
    time_range:
      since: "2015-01-10T00:00:00"
      until: "2015-02-28T23:59:59"
      timezone: {label: "UTC (UTC+00:00)", tzCode: "UTC", name: "(UTC+00:00) UTC", utc: "+00:00"}
    groupers: {groupers: []}          # [] = single view; set a grouper to split
mep_dev:
  mock_io: false
  params:
    er_client_name: {data_source: {name: "mep_dev"}}
```

Make case `description`s name the code path exercised ("hits the resolver tasks and
add_spatial_index"). Ship an **empty-fixture regression case** alongside rich ones where skip
chains matter.

## test-cases gotchas

- **`since`/`until` must be naive datetimes** (no `Z`/offset) — `Z` with a non-UTC timezone
  shifts across month boundaries on conversion ("Jan 2026 - Feb 2026" instead of "Jan 2026").
- **`timezone` is a TimezoneInfo object** (label/tzCode/name/utc), not a bare zone string.
- **Only user-configurable params belong in a case** — anything bound via `partial` is
  `extra_forbidden`.
- **rjsf `default:` is form-only** — an omitted param uses the pydantic model default
  ([rjsf.md](rjsf.md)); set toggles explicitly.
- **Absolute paths for files** — the CLI runs from the compiled workflow dir.
- **`SkipJsonSchema` fields silently drop** — they're absent from the Params schema, so pydantic
  discards them as extras and union matching may pick a different branch. Check the compiled
  `params.json` for the real field set when in doubt.
- **Spatial-grouper mock cases** must use the display name the mock fixture carries —
  `spatial_index_name: "SpatialGrouperTest"` for the stock fixture ([patterns.md](patterns.md)
  for the mechanism).
- **Aggregation over event details in mock cases** must use a key the canned
  `process_events_details` fixture contains ([patterns.md](patterns.md), side-branch pattern).

## How mock-io works

`--mock-io` selects the `run_sequential_mock_io` DAG, which replaces each `tags=["io"]` task with
a magicmock returning a **fixed packaged fixture** — the task's inputs are discarded, so params
that would drive the query (`event_types`, `time_range`, …) are **ignored**; the fixture's own
values drive the widgets. Resolution order: the per-task env override (below), else the packaged
`{func-name-dashed}.example-return.{json|parquet}` resource in the task's module.

- Fixtures are **shared across all workflows** that mock a task — never edit one for a one-off;
  override per-case instead.
- Find a workflow's mocked tasks in `IO_TASKS_IMPORTABLE_REFERENCES` in the generated
  `tests/conftest.py`.
- Inspect a canned fixture from the inner env:
  `wt_task.testing.create_func_magicmock(anchor, func_name)()`.
- `.json` fixtures load via a built-in loader; only `.parquet` goes through the ecoscope
  `mock_loaders` entry point — so schema/choices overrides are plain JSON, data is parquet.

## `mock_io_overrides` — per-case fixture overrides

```yaml
rich_events:
  mock_io: true
  mock_io_overrides:
    ecoscope.platform.tasks.io.process_events_details: dev/fixtures/rich.example-return.parquet
  params: { … }
```

Key shape: `<task_anchor>.<func_name>` (the anchor is the public dotted module path). The harness
uppercases the dotted path, swaps dots for underscores, and exports
`WT_TASK_MOCK_IO__<UPPERCASED>=<path>` for the duration of the case (unset between cases). At
runtime the mock loader checks the env var before package resources. Repo-relative paths are
absolutized by the harness (the loader needs absolute paths); URLs pass through. The env var also
works standalone — export it yourself for ad-hoc runs on synthetic or real external data (the
runner executes the DAG in a subprocess that inherits the shell environment, so `PYTHONPATH`
shims propagate too).

Reach for overrides to test multiple data shapes per task or reproduce a bug from a downloaded
parquet; if you're overriding the same task in most cases, improve the packaged fixture instead
(as its own deliberate change — it's shared).

## `dev/run-test-cases.sh`

```
./dev/run-test-cases.sh <--all | --case NAME> [--update | --frozen] [--local] [--quiet|-q]
```

- Requires go-yq, and pixi unless `--local`. Auto-discovers exactly one
  `<prefix>-*-workflow/` dir (errors otherwise) — reuse this discovery, don't reconstruct the
  package name from the spec id.
- Per case: reads `.mock_io` (default true), creates a fresh results dir under the system temp
  path, exports `ECOSCOPE_WORKFLOWS_RESULTS`, translates `mock_io_overrides` to env vars, extracts
  the case's `params` with yq, and runs the CLI wrapped in
  `pixi run --manifest-path <inner>/pixi.toml --locked|--frozen -e default`.
- Pass = `result.json` exists **and** `.error == null` **and** exit 0. A "successful" run with
  zero outputs is the silently-empty-run trap — check the expected outputs, not just the status.
- **`--local` runs bare `python` with no pixi wrap** → `ModuleNotFoundError: click` unless you are
  already inside the inner env. Default (no `--local`) is correct; use `--frozen` when git-tag
  deps are present ([environments.md](environments.md)).
- Debugging a run's opaque failure: run
  `pixi run python -c "from <pkg>.dags import run_sequential_mock_io; …"` in the **default** env
  (it has the task libraries; the `test` env does not) to get the real traceback.
- One upstream task error can skip the whole dashboard (`gather_dashboard` skips on
  `any_dependency_skipped`) — surfacing as "result.json not found".

## Template paths and raw URLs

`mock_io_overrides` values resolve repo-root-relative, but **`template_path` params resolve from
the inner package dir** — use GitHub raw URLs for templates. When a template changes on a publish
branch, a `main`-ref raw URL serves the **stale** copy during PR CI: SHA-pin the raw URLs in
`test-cases.yaml`, and keep the rjsf-overrides `template_path.default` pointing at `main` (it only
matters post-merge).

## Live cases

Live (`mock_io: false`) cases use connection names that CI injects as secrets
([connections.md](connections.md)). Live-only failure classes: server-side config drift (a pruned
patrol type raises `ValueError: Failed to find IDs for values: {...}` — re-list types and update
defaults), data gaps in the seeded window (the empty-run trap), and VPN routing (402/502 → switch
VPN server before debugging).
