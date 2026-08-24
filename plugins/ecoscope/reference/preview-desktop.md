# Previewing dashboards and running on real data

Render a workflow's dashboard with synthetic data — as PNGs, interactive HTML, or inside the real
Ecoscope Desktop/web UI — without EarthRanger, a backend, or auth. Also: injecting real external
data into a run. Mock-io mechanics live in [testing.md](testing.md).

## Contents
- Synthesizing a fixture
- High-res PNG snapshots
- Interactive widget HTML
- Viewing in the real Desktop / web UI (on-disk run contract)
- Per-group view selector
- Running on real external data
- Keeping the tree clean

## Synthesizing a fixture

Always **inspect the real fixture first** so dtypes and columns match (from the inner workflow
dir, which has geopandas):

```bash
pixi run python -c "import geopandas as gpd; g=gpd.read_parquet('<fixture>'); print(g.dtypes); print(g.head())"
```

Build a GeoDataFrame with the same column order and dtypes (EPSG:4326, tz-aware UTC `time`, dict
columns as real dicts, uuid ids). Read `spec.yaml` to learn which column drives each widget; vary
counts / monthly weights / spatial clusters per category so the preview tells a readable story.
Where several fixtures feed one workflow (data + schema-labels + choices JSONs), they must stay
mutually consistent — labels drive table headers, choices map category slugs to display names
(without them raw slugs render). Note: analysis/category field *labels* come from test-case
params, not the schema fixture.

## High-res PNG snapshots

The single resolution knob is `_take_screenshot` in the generated `tests/conftest.py` (default
viewport 640×360). Bump it, render, then `git checkout` the file back:

```python
page = await browser.new_page(viewport={"width": 1280, "height": 720}, device_scale_factor=3)
```

`device_scale_factor` is the real sharpness lever; raster basemap tiles still upscale softly.
Install the browser once: `pixi run -e test playwright install chromium`. Render:

```bash
WT_TASK_MOCK_IO__<ANCHOR>_<FUNC>=/path/mock.parquet \
pixi run -e test python -m pytest tests/test_results.py::test_iframes \
  -k "app and data and not nodata" --case <case> --snapshot-update -p no:randomly
```

(`-k "data and not nodata"` because "data" substring-matches "nodata".) PNGs land under the
repo's `__results_snapshots__/<case>/`.

**Gotcha — `ValueError: Input images must have the same dimensions`** under `--snapshot-update`:
the SSIM matcher compares before writing and can't compare across resolutions. Either `rm` the
existing PNGs for that case first, or (cleaner) **render under a new throwaway test case** whose
snapshot dir is fresh — this also avoids clobbering committed snapshots and constant-named tiles.

## Interactive widget HTML

Widget HTML (plotly charts, lonboard maps, ag-grid tables) is written to the run's results dir —
by default a throwaway pytest tmp dir; override the `results_dir` fixture in conftest to a fixed
path to keep it. Widgets land per-run under a fresh `<uuid>/` as `*_v2.html` plus a `result.json`
whose `result["views"]` maps widget titles → data files.

**Gotcha — stale HTML across re-runs:** the results dir accumulates a new `<uuid>` per render.
Pick the run by newest `result.json` mtime or `rm -rf` the results dir first. The PNG never shows
this (snapshots always overwrite), so "PNG updated but HTML didn't" = this bug.

## Viewing in the real Desktop / web UI

Both Ecoscope Desktop (Electron) and ecoscope-web in desktop mode render dashboards **purely from
on-disk files**. The app data directory is platform-specific — discover it, never hardcode:
macOS `~/Library/Application Support/ecoscope-desktop/`, Windows `%APPDATA%\ecoscope-desktop\`,
Linux `$XDG_CONFIG_HOME/ecoscope-desktop/` (default `~/.config/…`). On-disk run contract:

```
<app-data>/data/workflows/<template>/<wf>/
├── metadata.json                       # lists the run + marks it succeeded
└── <run>/ { result.json, layout.json, *_v2.html }
```

- **result.json** — a mock-io run already emits the exact shape; copy as-is.
- **layout.json** — copy the **workflow repo's own `layout.json`**. **Do NOT use `result.json`'s
  `result["layout"]`** — it is empty `[]` for mock-io runs, which renders a dashboard with **zero
  widgets** (opens fine, no tiles); the desktop loader overwrites `result.layout` with this file
  and fails if it's absent.
- **widget HTML** — resolved by basename; copy all `*_v2.html` from the run's results dir; must be
  self-contained (they postMessage to clear the spinner).
- **metadata.json** — required fields: `id` == `<wf>` dirname, `latest_run.id` == `<run>` dirname,
  `latest_run.status` == "success", `workflow_template.id` == `<template>` dirname,
  `service_url_version.version` (string), `error`/`trace` null.

Drop the files in, relaunch the app (it lists from disk at load), open the row under My
Workflows. Display-only — the in-app Run button fails (no data source). Remove with `rm -rf` on
the `<template>` dir. **Desktop run `metadata.json` `config` keys are FLAT task ids** (never
nested under group titles) — looking up `config["<Group Title>"]` falsely suggests a dropped
field; check `config.<task_id>.<field>`.

ecoscope-web alternative: run its dev server with `NEXT_PUBLIC_IS_DESKTOP_APP=true` (reads the
same dir, auth bypassed) plus `data/app-state.json` = `{"onboarding":"completed"}`.

## Per-group view selector

Add a grouper to the test case to get the "by species"-style dropdown:

```yaml
groupers:
  groupers:
    - index_name: "<column>"
```

The run emits one view per group value, keyed `'{"<col>":"<value>"}'`, plus
`result.filters.schema.properties.<col>.oneOf` as the dropdown options. Two gotchas: grouper
values render **raw** — store display-ready values ("Lion", not "lion"); and don't set
`category_field` to the same column (each view becomes a single-slice chart) — use a different
field for the in-view breakdown.

## Running on real external data

Build a parquet matching the IO task's example-return schema and point the
`WT_TASK_MOCK_IO__…` env override at it ([testing.md](testing.md)). The runner executes the DAG in
a **subprocess of the default pixi env that inherits the shell environment** — so both the
override and a `PYTHONPATH=<dir with sitecustomize.py>` shim propagate, which is how to inject a
run-local monkeypatch without touching installed packages. For real tracebacks instead of an
opaque 500, call the mock-io DAG's `main(params)` directly under `pixi run python` in the
**default** env (the `test` env lacks the task libraries).

## Keeping the tree clean

Everything above touches tracked files only transiently. Afterwards restore
`test-cases.yaml`, the inner `tests/conftest.py`, and the inner `pixi.lock` (an older local pixi
rewrites it — "Lock-file version N is newer than supported"), and delete any throwaway snapshot
dirs. Never commit synthetic-preview artifacts, and never let real pulled data out of a
gitignored scratch dir ([process-rules.md](process-rules.md)).
