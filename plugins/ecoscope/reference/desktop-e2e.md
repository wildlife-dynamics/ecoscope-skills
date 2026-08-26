# Desktop E2E tests (Playwright)

Authoring Playwright tests that drive Ecoscope Desktop through open template → configure → run →
assert. Tests live in the org's e2e test repo (`ecoscope-ui-e2e-tests`: Playwright + TypeScript,
page objects); the desktop suite attaches to a **running** Electron app over CDP
(`http://localhost:9222`) — it never launches the app. The repo is a sibling checkout: ask the
user where it is, never assume. Facts below were verified against that repo's `main` and the
installed app's bundles (2026-08-26).

## Contents
- The suite
- Setup footguns
- App data dir
- Import strategies and template tiles
- Scaffold-then-fill loop
- Field-driving rules (the numbered gotchas)
- Submit, run, assert
- Debugging a failed run

## The suite

- `playwright.desktop.config.ts`: `testDir ./tests/desktop-tests`, `testMatch **/*.pw.test.ts`,
  headless, 120 s per test (workflow tests raise it with `test.setTimeout(900000)`), `retries: 3`
  — pass `--retries=0` locally so a hang fails once, not four times.
- `tests/desktop-tests/fixtures.ts` exports `test`/`expect`: a worker-scoped page from
  `chromium.connectOverCDP('http://localhost:9222')`, first context, first page; it completes
  onboarding if the "Get Started" flow appears, then waits for the **"My Workflows"** or
  **"Data Sources"** heading. Every test imports `{ test, expect } from '../fixtures'`.
- Page objects under `tests/desktop-tests/pom/`: `my-workflows/my-workflows-page`
  (`verifyWorkflowCreated`, `getTableRowByText`, `clickRunWorkflow` — retries once on "Failed to
  start the workflow", `waitForWorkflowToSucceed(page, name, attempts = 30)` ≈ 10 s per
  attempt, `verifyWorkflowDeleted`); `workflow-templates/workflow-templates-page`
  (`navigateToWorkflowTemplates`, `clickAddWorkflowTemplate`, `addWorkflowFromURL` →
  `add-github-template-link-input` + `import-template-submit-btn`, `isTemplateInTheLibrary(page,
  '<name>-container')`, `verifyTemplateImported`, catalog helpers);
  `data-sources/data-sources-page` (`navigateToDataSources`,
  `createEarthRangerConnectionIfNotExists` — reads `ER_PASSWORD`); `workflow-config/
  workflow-config-page` (`fillWorkflowForm` for the four catalog templates only). Reuse them;
  changing a shared page object is its own reviewed change, not a side effect of a new test.
- Commands: `yarn` (postinstall points `core.hooksPath` at `.githooks`), `yarn playwright install
  --with-deps chromium` once; `yarn test:desktop` for the suite; one test:
  `yarn playwright test --config=playwright.desktop.config.ts <path> --reporter=list --retries=0`.
  Pre-commit runs `yarn lint && yarn format` (prettier check; `yarn format:fix` repairs) and
  refuses `^` ranges in `package.json`. ESLint bans `console.log` — `import { log } from
  'node:console'` as the existing tests do.
- Environment: `ER_PASSWORD` / `SMART_PASSWORD` for the data-source page objects; TestRail
  variables are CI-only. Passwords never appear in a test file.
- CI runs the desktop suite against the Linux build from the compose repo's pipelines; a
  committed test must therefore not depend on macOS paths, an open app window, or a tile that
  only your machine has without saying so in its header comment.

## Setup footguns

1. **`ELECTRON_RUN_AS_NODE`** set in the shell (common inside another Electron app) boots the
   binary as plain Node and the CDP port never opens. macOS: launch with it unset —
   `env -u ELECTRON_RUN_AS_NODE open -na Ecoscope --args --remote-debugging-port=9222` — and verify
   with `lsof -nP -i :9222`. Other platforms: the same `--remote-debugging-port=9222` argument on
   the app binary, verified with the platform's port listing.
2. **Local proxy** — `ALL_PROXY`/`HTTP(S)_PROXY` make Playwright reach CDP through the proxy
   (`Unexpected status 400 / not a DevTools server`). Run with `NO_PROXY="localhost,127.0.0.1"`.
   The app's own GitHub import ignores proxy variables entirely (a TUN-mode tunnel is the
   workaround behind a VPN).
3. **Landing page** — the fixture waits for "My Workflows"/"Data Sources", but the app restores
   its last route. Between runs reset it over CDP rather than clicking (a tab click on a stale
   route can hang, and can race the route change and silently no-op — retry until the target
   tile is visible):

   ```js
   // reset.mjs — run from the e2e repo so @playwright/test resolves
   import { chromium } from '@playwright/test'
   const b = await chromium.connectOverCDP('http://localhost:9222')
   const p = b.contexts()[0].pages()[0]
   await p.goto(new URL(p.url()).origin + '/my-workflows', { waitUntil: 'domcontentloaded' })
   await b.close()
   ```

## App data dir

The app keeps everything under Electron's `userData` for the app name `ecoscope-desktop`:
`data/workflows/<template-id>/<workflow-uuid>/metadata.json` plus a uuid run subdir holding
`result.json` and the widget files; templates under `data/templates/` ([preview-dashboard.md](preview-dashboard.md)
§ On-disk contract). There is **no supported way to point the installed app at a scratch data
dir** — a run always lands in the real one, which is why tests use unique names and never delete
what they did not create. Resolve the dir at runtime, never as a literal (several older tests in
the repo hardcode `Library/Application Support/…` and break on the Linux CI runner — do not copy
them):

```ts
import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

// Electron userData candidates per platform; the one that holds data/workflows is the app's.
export function ecoscopeAppDataDir(): string {
  const home = homedir()
  const candidates =
    process.platform === 'darwin'
      ? [join(home, 'Library', 'Application Support')]
      : process.platform === 'win32'
        ? [process.env.APPDATA, process.env.LOCALAPPDATA].filter(Boolean) as string[]
        : [process.env.XDG_CONFIG_HOME ?? join(home, '.config')]
  for (const base of candidates) {
    const dir = join(base, 'ecoscope-desktop')
    if (existsSync(join(dir, 'data', 'workflows'))) return dir
  }
  throw new Error(`Ecoscope Desktop data dir not found under ${candidates.join(', ')}`)
}
```

Find *your* run by scanning `metadata.json` files for `config.workflow_details.name ===
workflowName` (the per-run unique name), never by "the newest directory". Template dir ids:
`wildlife-dynamics-<repo>` for a GitHub import, `<name>-local-<hash>` for a local-folder import.

## Import strategies and template tiles

- **GitHub-URL import** clones the repo's **default branch** (shallow, single branch) and parses
  only `org/repo` — it cannot target a feature branch, so the GitHub tile always exercises the
  *published* artifact. It **can** be driven from a test: `clickAddWorkflowTemplate` →
  `addWorkflowFromURL(page, url)` → `verifyTemplateImported`, guarded by `isTemplateInTheLibrary`
  (the `event-details` test is the pattern). A first import builds the pixi env — minutes; allow
  for it in the timeout and wait for "Initializing" to leave the tile.
- **Local-folder import** (the working copy, pre-publish) cannot be automated: the native folder
  picker is unreachable (`window.electron.selectFolder` is frozen by contextBridge). The user
  imports once by hand; the test starts from the tile.
- A changed environment (task-library pin, lock, new deps) is **not** picked up by an existing
  tile — ask the user to delete it and re-import, or the run uses the stale env.
- Tile test-id is `<template-name>-container` — the template's display name slugified, which
  for a GitHub import is the repo name (`patrol-chart-container`, `event-details-container`) —
  shared by catalog, local and GitHub copies of the same workflow. Disambiguate by subtitle: `.filter({ hasText: 'Locally imported from' })` vs
  `.filter({ hasText: 'Source code: <url>' })`. Only CI can assume a single tile.

## Scaffold-then-fill loop

Every workflow shares the skeleton; **only the config-form fill differs** — inspect the live
form, never guess test-ids. Write a throwaway test that opens the form and dumps every
`[data-testid]` (plus a full-page screenshot), then author the fill from real data:

```ts
const testIds = await page.locator('[data-testid]').evaluateAll((els) =>
  els.map((el) => ({ testId: el.getAttribute('data-testid'), tag: el.tagName.toLowerCase(),
                     type: el.getAttribute('type'), role: el.getAttribute('role') })))
log(JSON.stringify(testIds, null, 2))
await page.screenshot({ path: 'test-results/form-scaffold.png', fullPage: true })
```

Anchor "form is open" on the always-present `input-root_workflow_details_name`, not a section
title. Use the workflow's `test-cases.yaml` `base` case as the source of known-good values.
Without a running app there is no scaffold: a test written blind is a draft and its report says
so.

## Field-driving rules

- **Text**: `input-root_<section_id>_<field>` — a task-group section embeds its title *with
  spaces* (`input-root_Refine Data_sql_query_query`).
- **Datetime**: `date-time-time-zone-picker-input-root_time_range_since` / `_until`, format
  `YYYY-MM-DDThh:mm`.
- **Timezone picker** (`timezone-picker-input`, required, blank by default): type to filter,
  **never "pick the first option"** — the picker renders a match only once filtered, so a
  visible-else-first fallback always takes the fallback and silently commits an unrelated zone;
  the run then succeeds against a shifted window. Fill, click the visible match, assert
  `toHaveValue`.
- **rjsf selects** (`select-widget-show-dropdown-button` / `select-widget-input`): non-unique —
  scope to a section root (`page.getByTestId('title-<Section>').locator('..').locator('..')`).
  The **Data Source** picker is the one select every form has; forms with `Literal` / `oneOf`
  params add more (interval, mode, chart type, metric-row pickers), and an enum select may
  render as a shadcn `select-trigger` instead of a `select-widget-*` depending on the render
  pass — try `select-trigger` first for those, fall back to the select-widget ids, find the one
  you want by its displayed value, never by position.
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

  If nothing in an accordion needs setting, leave them collapsed — expanding is not free (next
  rule).
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

Submit (`submit-btn`) shows the toast "Your configuration has been submitted successfully." and
lands on a paginated table — filter with the "Search workflow names..." box rather than assuming
page 1; use a unique per-run workflow name (`AUT <wf> [${Date.now()}]`). Run with
`clickRunWorkflow`, wait with `waitForWorkflowToSucceed` (`workflow-col_status-label` reads
`Success`); heavily-grouped runs exceed the default ~5 minutes — raise `attempts` rather than
treating the timeout as failure, and check the run's `metadata.json` status directly if unsure.

`Success` is not the assertion — a run with zero outputs reports it too. Assert at least one of:

- **On disk**: this run's `result.json` (uuid subdir under the workflow dir, § App data dir) has
  `error == null` and non-empty `result.views`; the widget HTML files (`<hash>_<suffix>.html`,
  e.g. `3c8fe29_trend_chart.html`) sit beside it ([preview-dashboard.md](preview-dashboard.md)
  § On-disk contract). Skip with a log line on a runner that cannot see the app's data dir.
- **In the UI** (portable): click the run's row (`getTableRowByText(...).click()`); the results
  page renders `workflow-results-navbar` (and `workflow-results-sidebar-view-select` when the
  run is grouped); each widget is a wrapper `iframe-widget-<slug>` — the title lower-cased,
  spaces to hyphens, punctuation kept (`iframe-widget-trajectories-&-patrol-events-map`) —
  containing `iframe-widget-content-<widget_type>` (`graph` / `map` / `table`) once loaded; the
  "Loading content..." placeholder is gone and no `iframe-widget-retry-button` is shown. Read
  the exact slug off the live page with the test-id dump; the "Edit Layout" button is also on
  that page. The web suite's `workflow-results-page` id may not exist on Desktop — anchor on the
  navbar.

## Debugging a failed run

A failed *workflow* writes `latest_run.error` + `latest_run.trace` into
`<app-data>/data/workflows/<template-id>/<workflow-uuid>/metadata.json` (§ App data dir). Verify
what the form actually committed via that file's `config` (flat task-id keys, never nested under
group titles) — silently-dropped fills show up as missing keys. A silent hang is a collapsed
accordion or a hidden widget (screenshot to confirm); a fast Success with no outputs is the wrong
data source. Data-backed workflows can fail on default form dates (e.g. satellite products lag) —
use historical dates from `test-cases.yaml`.
