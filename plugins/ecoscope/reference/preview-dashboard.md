# Previewing a dashboard in Ecoscope Desktop

How to open a dashboard in the real Ecoscope Desktop (or ecoscope-web) UI without EarthRanger, a
backend, or auth. The app renders **purely from on-disk files**, so a preview is just: put a run
directory in the app data dir, relaunch. Where the run directory comes from is up to you:

- **From a test case** (most reliable) — real widgets with whatever data the case feeds the
  workflow: packaged mock fixtures by default, or your own ([testing.md](testing.md): mock-io,
  `mock_io_overrides`, Generating mock data).
- **Hand-stubbed** — fake `result.json` + placeholder widget files, when all you want to see is
  `layout.json` (tile sizes and placement, [output-style.md](output-style.md)).

Contract details below were read from ecoscope-web's `workflows.desktop.server.utils.ts`,
`IframeWidget.tsx`, `my-workflows/models.ts`, and `app/api/workflow-results-iframe-html/route.ts`.

## Contents
- On-disk contract
- Source A: a test-case run
- Source B: hand-stubbed run
- metadata.json
- Per-group view selector
- Cleanup

## On-disk contract

```
<app-data>/data/workflows/<template>/<wf>/
├── metadata.json                       # lists the workflow + marks the run succeeded
└── <run>/ { result.json, layout.json, *_v2.html }
```

`<app-data>` is platform-specific and can be found by "Open Result Folder" from an existing workflow on Ecoscope Desktop. macOS
`~/Library/Application Support/ecoscope-desktop/`, Windows `%APPDATA%\ecoscope-desktop\`, Linux
`$XDG_CONFIG_HOME/ecoscope-desktop/` (default `~/.config/…`). `<template>` is the workflow
template id (e.g. the repo's spec id); `<wf>` and `<run>` are free-form (the real app uses uuids)
but must match the ids inside `metadata.json`.

- **result.json** — `{"error": null, "trace": null, "result": {views, filters, metadata, layout}}`.
  `result["views"]` maps a view key → list of widgets; the loader ignores `result["layout"]`.
- **layout.json** — the loader reads `<run>/layout.json`, else falls back to
  `<app-data>/data/templates/<template>/layout.json`, else fails to load the run. Copy the
  **workflow repo's own `layout.json`**. **Do NOT use `result["layout"]`** — it is `[]` for mock-io
  runs and renders a dashboard with **zero widgets** (opens fine, no tiles). Every layout entry's
  `widget_id` must match a widget `id` in the view.
- **widget HTML** — a `map`/`graph`/`table` widget's `data` is a filename; the app serves it by
  basename from the `<run>` dir. A `*_v2.html` file must post a message to the parent to clear the
  spinner (Source B for the shape). `stat` and `text` widgets render `data` inline — no file.
- **metadata.json** — the one file no run emits; see its own section.

Drop the files in, relaunch the app (it lists from disk at load), open the row under My
Workflows. Display-only — the in-app Run button fails (no data source / template rjsf). Remove
with `rm -rf` on the `<template>` dir.

ecoscope-web alternative: run its dev server with `NEXT_PUBLIC_IS_DESKTOP_APP=true` (reads the
same dir, auth bypassed) plus `data/app-state.json` = `{"onboarding":"completed"}`.

## Source A: a test-case run

```bash
./dev/run-test-cases.sh --case <case>
```

Results land in `/tmp/workflow-test-results/<workflow>/<case>/` (`$RUNNER_TEMP` on CI; the script
prints the path and `rm -rf`s it per run, so nothing stale survives). Find `result.json` under
it — the `*_v2.html` widget files (plotly charts, lonboard maps, ag-grid tables) sit next to it.
Check `result["views"]` is non-empty: a "successful" run with zero outputs is the
silently-empty-run trap ([testing.md](testing.md)). Copy `result.json` and every `*_v2.html`
into `<run>/`, add the repo's `layout.json` and a `metadata.json`.

## Source B: hand-stubbed run

For a layout-only preview, write `result.json` with one view whose widgets carry the `id`s that
`layout.json` references. Ungrouped workflows use the view key `"{}"`; this shape also hides the
view selector so `filters` is never read.

```json
{"error": null, "trace": null, "result": {
  "layout": [],
  "filters": {"schema": {}, "uiSchema": {}},
  "metadata": {"title": "Preview", "description": "", "time_range": "", "time_zone": "UTC"},
  "views": {"{}": [
    {"id": 0, "widget_type": "stat",  "title": "Event Count", "data": "42", "type": "number"},
    {"id": 1, "widget_type": "graph", "title": "Events by Type", "data": "chart_v2.html",
     "is_link": true, "is_image": false, "is_expandable": true, "is_downloadable": true},
    {"id": 2, "widget_type": "map",   "title": "Events Map",     "data": "map_v2.html"},
    {"id": 3, "widget_type": "table", "title": "Events Table",   "data": "table_v2.html"}
  ]}
}}
```

Each `*_v2.html` is a self-contained page; the spinner clears only when it posts
`{type, widgetId}` where `widgetId` **equals the widget's `title`** and `type` matches the
widget type — `PlotLoaded` (graph), `TileLoaded` (map), `TableLoaded` (table):

```html
<body style="margin:0;display:grid;place-items:center;height:100vh;font-family:sans-serif;
             background:#eef">graph placeholder
<script>window.parent.postMessage({type: "PlotLoaded", widgetId: "Events by Type"}, "*")</script>
</body>
```

Real widgets do the same (e.g. `ExportArgs.post_script` in ecoscope's `_ecoplot.py`), which is
why copied output "just works".

## metadata.json

The app validates this file with a zod schema on every listing and **silently skips the workflow
if it fails** — a missing key means the row never appears, with no error. Minimal passing file
(`id`, `workflow_template.id`, `latest_run.id` must equal the `<wf>`, `<template>`, `<run>`
dir names; `latest_run.status` must be `"success"`):

```json
{
  "id": "<wf>",
  "name": "Preview",
  "description": null,
  "image_url": null,
  "config": {},
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-01T00:00:00Z",
  "created_by": null,
  "updated_by": null,
  "service_url_version": {"version": "0.0.0"},
  "is_runnable": false,
  "workflow_template": {
    "id": "<template>", "name": "Preview template", "description": null, "image_url": null,
    "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
    "created_by": null, "updated_by": null, "is_active": true
  },
  "latest_run": {
    "id": "<run>", "description": null, "workflow_id": "<wf>", "status": "success",
    "error": null, "trace": null, "time_elapsed_seconds": 0,
    "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
    "created_by": null, "updated_by": null
  }
}
```

On a real run the app fills `config` with the form data; its keys are **flat task ids** (never
nested under group titles) — looking up `config["<Group Title>"]` falsely suggests a dropped
field; check `config.<task_id>.<field>`.

## Per-group view selector

To preview the "by species"-style dropdown from a test-case run, add a grouper to the case:

```yaml
groupers:
  groupers:
    - index_name: "<column>"
```

The run emits one view per group value, keyed `'{"<col>":"<value>"}'`, plus
`result.filters.schema.properties.<col>.oneOf` as the dropdown options. Two gotchas: grouper
values render **raw** — the fixture must hold display-ready values ("Lion", not "lion"); and
don't set `category_field` to the same column (each view becomes a single-slice chart) — use a
different field for the in-view breakdown.

## Cleanup

Remove a preview with `rm -rf` on the `<template>` dir under `data/workflows`. If you edited
`test-cases.yaml` for the preview, restore it; an older local pixi may also rewrite the inner
`pixi.lock` ("Lock-file version N is newer than supported") — `git checkout` it. Never commit
preview artifacts, and never let real pulled data out of a gitignored scratch dir
([process-rules.md](process-rules.md)).
