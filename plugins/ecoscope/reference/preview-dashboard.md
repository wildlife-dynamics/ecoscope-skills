# Previewing a dashboard in Ecoscope Desktop

How to open a workflow's rendered dashboard in the real Ecoscope Desktop (or ecoscope-web) UI
without EarthRanger, a backend, or auth: run a test case, copy its output into the app's data
directory, relaunch. This page is about the **viewing** step. The data the dashboard shows comes
from whatever the test case feeds the workflow — packaged mock fixtures by default, or fixtures
you build ([testing.md](testing.md): mock-io, `mock_io_overrides`, Generating mock data).

## Contents
- Run the test case
- Assemble the run directory
- Where the app reads from
- Per-group view selector
- Cleanup

## Run the test case

```bash
./dev/run-test-cases.sh --case <case>
```

Results land in `/tmp/workflow-test-results/<workflow>/<case>/` (`$RUNNER_TEMP` on CI; the script
prints the path and `rm -rf`s it on each run, so there is never a stale copy). Find `result.json`
under it — the widget files (`*_v2.html`: plotly charts, lonboard maps, ag-grid tables) sit next
to it. Check `result["views"]` is non-empty: a "successful" run with zero outputs is the
silently-empty-run trap ([testing.md](testing.md)).

## Assemble the run directory

The app renders dashboards **purely from on-disk files**, in this shape:

```
<app-data>/data/workflows/<template>/<wf>/
├── metadata.json                       # lists the run + marks it succeeded
└── <run>/ { result.json, layout.json, *_v2.html }
```

- **result.json** — copy as-is from the results dir.
- **`*_v2.html`** — copy all of them; the app resolves widgets by basename. They are
  self-contained (they postMessage to clear the spinner).
- **layout.json** — copy the **workflow repo's own `layout.json`**. **Do NOT use `result.json`'s
  `result["layout"]`** — it is `[]` for mock-io runs, which renders a dashboard with **zero
  widgets** (opens fine, no tiles). The loader overwrites `result.layout` with this file and
  fails if it's absent.
- **metadata.json** — the one file nothing emits; write it by hand. Required fields:

  ```json
  {
    "id": "<wf>",
    "workflow_template": { "id": "<template>" },
    "service_url_version": { "version": "0.0.0" },
    "latest_run": { "id": "<run>", "status": "success" },
    "error": null,
    "trace": null
  }
  ```

  `id`, `workflow_template.id` and `latest_run.id` must equal the `<wf>`, `<template>` and
  `<run>` directory names. Other fields the real app writes (`name`, `config`, timestamps) are
  optional for display. Note `config` keys are **flat task ids** (never nested under group
  titles) — looking up `config["<Group Title>"]` falsely suggests a dropped field; check
  `config.<task_id>.<field>`.

Directory names are free-form for a preview; the real app uses uuids.

## Where the app reads from

The app data directory is platform-specific — discover it, never hardcode:
macOS `~/Library/Application Support/ecoscope-desktop/`, Windows `%APPDATA%\ecoscope-desktop\`,
Linux `$XDG_CONFIG_HOME/ecoscope-desktop/` (default `~/.config/…`).

Drop the files in, relaunch the app (it lists from disk at load), open the row under My
Workflows. Display-only — the in-app Run button fails (no data source).

ecoscope-web alternative: run its dev server with `NEXT_PUBLIC_IS_DESKTOP_APP=true` (reads the
same dir, auth bypassed) plus `data/app-state.json` = `{"onboarding":"completed"}`.

## Per-group view selector

To preview the "by species"-style dropdown, add a grouper to the test case:

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

Remove a preview with `rm -rf` on the `<template>` dir. If you edited `test-cases.yaml` for the
preview, restore it; an older local pixi may also rewrite the inner `pixi.lock` ("Lock-file
version N is newer than supported") — `git checkout` it. Never commit preview artifacts, and
never let real pulled data out of a gitignored scratch dir ([process-rules.md](process-rules.md)).
