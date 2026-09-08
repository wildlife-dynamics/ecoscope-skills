# ecoscope-skills

A Claude Code plugin marketplace for Ecoscope workflow development — authoring `spec.yaml`,
driving the `wt-compiler` compile→test loop, building the config form and dashboard people
actually use, writing tasks, documenting, reviewing and releasing.

Two plugins:

| Plugin | What it is |
|---|---|
| **`ecoscope`** | Eight skills plus a shared knowledge base. No hooks, nothing that blocks. |
| **`ecoscope-guards`** | Two hooks, and nothing else. One of them can block a commit. Installing it *is* the opt-in — see [Guards](#guards-optional). |

## Install

```
/plugin marketplace add wildlife-dynamics/ecoscope-skills     # this checkout
/plugin install ecoscope@ecoscope-skills
/plugin install ecoscope-guards@ecoscope-skills      # optional, see below
```

Once this repo is pushed, `/plugin marketplace add wildlife-dynamics/ecoscope-skills` replaces the
local path and `/plugin marketplace update ecoscope-skills` picks up changes.

**Prerequisites** (the skills check them, they do not install them): `wt-compiler` on `PATH`,
`pixi`, `graphviz`, and go-`yq` (mikefarah — the Python `yq` breaks `run-test-cases.sh`). Run
`plugins/ecoscope/scripts/preflight.sh` to see what is missing; it reports and names each repair,
and never changes anything itself.

## The skills

Every one is model-invocable — describe the job and the right skill fires; the slash form is
there when you want to force it. Each hands off to the next by name at its seam, so you can enter
the cycle anywhere.

| Skill | Fires on | What it does |
|---|---|---|
| **`/ecoscope:develop`** | "build / add to / fix the X workflow", a `spec.yaml` edit, a form or dashboard change, a failing case | The spine. Designs with you and waits for approval, implements, runs the compile→test loop, commits on green, verifies its own work, then asks you to check the form and dashboard. |
| **`/ecoscope:plan`** | "plan / spec out a workflow that …", a big multi-session change | Opt-in PRD before anything is built: research, sample data into `.scratch/`, one batch of questions, `.scratch/prd.md` for `develop` to build from. |
| **`/ecoscope:task`** | a spec needs a task the libraries lack, or a task is broken | Builds it in the task-library checkout to the contract `develop` handed over, proves discovery with `wt-registry` rather than by reading source, and hands back the editable pin. |
| **`/ecoscope:guide`** | "write / update the README", "does the guide still match?" | The 8-section user guide for the people who run the workflow in Desktop — every sentence derived from the compiled form, a real run and the cases. Also the gate `publish` applies before it opens a PR. |
| **`/ecoscope:e2e`** | "add an E2E test", "does it run in Desktop?" | A committed Playwright test in the org's suite: opens the template, fills the form from a known case, runs it, asserts the run produced a dashboard. |
| **`/ecoscope:review`** | "review this before we publish", or `publish`'s pre-release gate | Three verified passes — publish readiness against this repo's own CI, the fleet's failure modes in the diff, what a run actually produced — plus a human-validation checklist. Reports; never edits. |
| **`/ecoscope:publish`** | "publish / release X", "CI says generated files differ" | The narrow bridge. Reads the repo's own CI as the authority, proposes the dependency refresh line by line, mirrors CI's recompile exactly, walks the release gates, opens the PR. Never merges, never tags. |
| **`/ecoscope:reference`** | a question with no editing task attached | Thin index over the knowledge base, for "how do skipif conditions work?" |

## The knowledge base

`plugins/ecoscope/reference/` — 20 topic files the skills link at the point of use, addressed as
`${CLAUDE_PLUGIN_ROOT}/reference/<file>.md`. It lives at the plugin root rather than inside a
skill because skills cannot read each other's files.

Environments and the standing rules · the compile command, flags and error table · `spec.yaml`
schema · task discovery and task anatomy · pipeline and widget patterns · rjsf overrides and
conditionals · `test-cases.yaml` and mock-io · per-task pitfalls · data connections · dashboard
preview and Desktop E2E · CI gates and release tagging · web deployment · catalog metadata · repo layout · output
styling · which upstream docs to trust · sensitive data and merge authorization.

Three rules run through all of it: **code is the source of truth** — upstream docs are for
vocabulary and mental model, the compiler's pydantic models and real fleet specs for syntax;
**citations name symbols, not line numbers**, which drift between the compiler pins in
concurrent use; and **anything version- or repo-specific points at where to verify it** rather
than freezing a value.

## Guards (optional)

`ecoscope-guards` carries two hooks and no skills. Plugin hooks have no per-hook switch — they
are live whenever the plugin is enabled — so they ship separately, and installing the plugin is
how you opt in. Uninstall it to remove them.

**`sensitive_commit_guard.py`** — `PreToolUse` on Bash. When the command is a `git commit`, it
reads the staged tree and decides by path:

| Staged path | Decision |
|---|---|
| `.scratch/**`, `**/*.example-return.parquet` | silent |
| `dev/fixtures/**`, `resources/mock-data/**`, `src/**/tasks/**` | silent when the repo commits a `build_*_fixture.py` generator; **ask** when it does not |
| any other `.parquet .feather .geojson .gpkg .shp .kml .kmz .csv` | **deny** |

Why a hard stop: the sensitive-data rule in
`plugins/ecoscope/reference/process-rules.md` — remediation after a leak is a history rewrite,
and on a public repo a GitHub support request. Why the fixture exemption: a guard that fires on
the fleet's own synthetic fixtures trains people to switch it off. `.json` is never flagged;
`layout.json`, `rjsf.json` and `params.json` are generated artefacts that belong in the tree. A
denied commit is not a veto — you can still run it yourself.

**`spec_edited_notice.py`** — `PostToolUse` on an edit to any `spec.yaml`. Advisory only: the
generated `*-workflow/` package, its `rjsf.json` and the test results now describe the previous
spec.

Both go through `hooks/hook.sh`, which exits silently when `python3` is absent — a hook that
errors on every tool call is worse than no hook.

## Layout

```
.claude-plugin/marketplace.json
plugins/
├── ecoscope/
│   ├── .claude-plugin/plugin.json
│   ├── reference/<topic>.md ×19        # the knowledge base
│   ├── scripts/preflight.sh            # tool discovery, reports only
│   ├── scripts/search-tasks.py         # optional accelerator for task discovery
│   └── skills/<name>/SKILL.md ×8
└── ecoscope-guards/
    ├── .claude-plugin/plugin.json
    └── hooks/{hooks.json,hook.sh,*.py}
```

Nothing in the plugins carries a machine-specific path: paths resolve from the plugin root
(`${CLAUDE_PLUGIN_ROOT}`), from the repo being worked on (anchored on its `spec.yaml`), or by
asking the installed tooling — so the suite works wherever it lands.

## Working on the suite

`.scratch/` (gitignored) holds the build plan, the baseline transcripts the skills were written
against, and the eval prompts and assertions; `docs/baselines.md` summarises what the
without-suite runs got wrong, which is what most of the skill text exists to counter.

Two checks before shipping a change:

```
grep -rnE '/Users/|/home/|~/MEP|~/Library' plugins/     # must return nothing
python3 -m json.tool <each manifest> >/dev/null         # manifests parse
```
