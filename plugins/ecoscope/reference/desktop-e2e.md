# Desktop E2E tests (Playwright)

Authoring Playwright tests that drive Ecoscope Desktop through import → configure → run → assert.
Tests live in the org's e2e test repo (Playwright + TypeScript, Page Object Model); the suite
attaches to a **running** Electron app over CDP (`http://localhost:9222`) — it does not launch
the app.

## Contents
- macOS setup footguns
- Import strategies and template tiles
- Scaffold-then-fill loop
- Field-driving rules (the numbered gotchas)
- Submit, run, assert
- Debugging a failed run

## macOS setup footguns

1. **`ELECTRON_RUN_AS_NODE`** set in the shell (common inside another Electron app) boots the
   binary as plain Node and the CDP port never opens. Launch with it unset:
   `env -u ELECTRON_RUN_AS_NODE open -na Ecoscope --args --remote-debugging-port=9222`, verify
   with `lsof -nP -i :9222`.
2. **Local proxy** — `ALL_PROXY`/`HTTP(S)_PROXY` make Playwright reach CDP through the proxy
   (`Unexpected status 400 / not a DevTools server`). Run with `NO_PROXY="localhost,127.0.0.1"`.
3. **Landing-page fixture** — the fixture waits for "My Workflows"/"Data Sources", but the app
   restores its last route. Between runs, reset over CDP
   (`page.goto(origin + '/my-workflows')`) or relaunch the app; clicking the nav tab can itself
   hang on a stale route, and tab clicks can race the route change and silently no-op — retry
   until the target tile is visible.

## Import strategies and template tiles

- GitHub-URL import is hard-wired to the repo's **default branch** (shallow single-branch clone)
  and parses only `org/repo` — it cannot target a feature branch. For pre-publish/local code, do
  the "Local Folder" import once by hand (the native folder picker cannot be driven — the
  contextBridge freezes `selectFolder`), then start tests from the imported tile.
- Tile test-id pattern is `<template-name>-container`, shared by catalog, local, and GitHub-import
  copies of the same workflow. Disambiguate by subtitle:
  `.filter({ hasText: 'Locally imported from' })` vs `.filter({ hasText: 'Source code: <url>' })`.
  Only the GitHub tile exercises the *published* artifact.
- GitHub import failing intermittently behind a proxy/VPN: the clone goes direct and ignores
  proxy env vars — use a TUN-mode tunnel.

## Scaffold-then-fill loop

Every workflow shares the skeleton; **only the config-form fill differs** — inspect the live
form, never guess test-ids. Write a throwaway test that opens the form and dumps every
`[data-testid]` (plus a full-page screenshot), then author the fill from real data. Anchor "form
is open" on the always-present `input-root_workflow_details_name`, not a section title. Use the
workflow's `test-cases.yaml` `base` case as the source of known-good values.

## Field-driving rules

- **Text**: `input-root_<section_id>_<field>` — note a task-group section embeds its title *with
  spaces* (`input-root_Refine Data_sql_query_query`).
- **Datetime**: `date-time-time-zone-picker-input-root_time_range_since` / `_until`, format
  `YYYY-MM-DDThh:mm`.
- **Timezone picker**: type to filter, **never "pick the first option"** — the picker renders a
  match only once filtered, so a visible-else-first fallback always takes the fallback and
  silently commits an unrelated zone; the run then succeeds against a shifted window. Fill,
  click the visible match, assert `toHaveValue`.
- **rjsf selects** (`select-widget-*`): non-unique — scope to a section root
  (`getByTestId('title-<Section>').locator('..').locator('..')`). The only select-widget on a
  typical form is the **Data Source** picker.
- **EnumResolver array fields** (`patrol_types`, `event_types`): on Desktop these are an **array
  text input with an "Add" button, NOT a dropdown** — click the section's `add-btn`, type the raw
  value, then **press Tab to commit** (without the blur the value silently drops on submit).
  Driving them as dropdowns hangs forever. The playground/web may render them as dropdowns —
  always verify against live Desktop.
- **anyOf/oneOf array fields** (groupers): scope `add-btn` to the section (several exist on the
  form). The new row's first select is the type picker (auto-selects the first branch); the inner
  oneOf select is then the **last** select-widget in the section.
- **Collapsed "Advanced Configurations" accordions**: a collapsed field is in the DOM but
  `display:none`, so `fill()`/`click()` **auto-wait and hang silently** until the whole test times
  out (a 20-minute no-error hang). A plain `.click().catch()` is NOT safe — `.catch()` swallows
  rejections, but an off-screen accordion makes `click()` wait forever (never rejects), hanging
  the loop itself. Expand them all, each click scrolled + forced + time-bounded:

  ```ts
  const accordions = page.getByRole('button', { name: 'Advanced Configurations' })
  const n = await accordions.count()
  for (let i = 0; i < n; i++) {
    await accordions.nth(i).scrollIntoViewIfNeeded({ timeout: 4000 }).catch(() => {})
    await accordions.nth(i).click({ timeout: 4000, force: true }).catch(() => {})
  }
  ```

- **Set Time Range and Data Source LAST, after expanding accordions.** Expanding an accordion
  **re-renders the rjsf form and resets earlier selections** — most damagingly the Data Source
  picker snaps back to a default connection. With a stale-but-valid connection holding no data
  for the window, the run fetches nothing and still reports **Success with zero output files**
  (everything short-circuits via `any_is_empty_df`). Symptom: a suspiciously *fast* "successful"
  run — confirm by grepping the run's `pixi.log` for the submitted data_source and download
  lines. A single display name can map to multiple underlying connection UUIDs, so the reset
  target may differ even when both read the same.
- **Never index a card's selects by position** — oneOf metric rows grow extra selects depending
  on the picked branch; find selects by current displayed value, and filter option clicks to
  visible (stale listbox portals linger as invisible options): bounded
  `getByRole('option', { name, exact }).filter({ visible: true }).first().click({ timeout })`.
- **Dropdown residue**: after picking a metric-row option the dropdown stays open and overlays
  the row — press Escape. Also press Escape after the timezone pick before opening the Data
  Source select, or its option portal starves and the wait hangs.
- **Checkboxes**: clicking the text label does not reliably flip one, nor does a force-click on
  the hidden input — click the checkbox input's **parent wrapper** and assert checked state.
  (Checkbox-gated reveals have separate submit drop-rules —
  [rjsf-conditionals.md](rjsf-conditionals.md).)
- **Portal multiselects** (chips + "Click here to show options…"): no test-id — locate
  structurally via `getByText('<Label>')` + following combobox; option clicks register but
  report a timeout (portal detaches mid-click), so retry on observed *state*
  (`/1 option selected/`), never on click success — a blind retry toggles the option back off.

## Submit, run, assert

Submit lands on a paginated table — filter by name rather than assuming page 1; use a unique
per-run workflow name. The success-wait defaults to ~5 minutes; heavily-grouped runs exceed it —
raise the attempts rather than treating the timeout as failure, and check the run's
`metadata.json` status directly if unsure.

## Debugging a failed run

A failed *workflow* writes `latest_run.error` + `latest_run.trace` into
`<app-data>/data/workflows/<template-id>/<workflow-uuid>/metadata.json`
([preview-desktop.md](preview-desktop.md) for the app-data dir per platform). Verify what the
form actually committed via that file's `config` (flat task-id keys) — silently-dropped fills
show up as missing keys. Data-backed workflows can fail on default form dates (e.g. satellite
products lag) — use historical dates from `test-cases.yaml`.
