# Eval baselines (RED arm) — build steps 2–6, `develop`, `publish`, `guide`, `e2e`, `task`, `plan`

Summary of the without-suite runs recorded on 2026-08-25 (scenarios 1, 2, 4) and 2026-08-26
(scenarios 3, 5, 6, 9, 10); full notes, verbatim commands and rationalizations live in the gitignored
`.scratch/baselines/`. Harness: hand-rolled parallel subagents in detached git worktrees — `claude plugin
eval` is enabled on this install but runs each case in a throwaway workspace with no documented way
to target a specific worktree, and the plugin has no manifest until step 7; port these scenarios to
`evals/` then.

| # | Scenario | Result | Failures observed |
|---|---|---|---|
| 1 | Greenfield: patrol effort by month for MMNR | Built a working 3-chart workflow, 4/4 mock cases green, 4 commits | No planning offer, no design-approval stop (six design questions guessed); every compile/test piped through `tail`/`grep -v`; plain `--clobber` wiped the lock (harness needs `--locked`) and `--update` was rediscovered from compiler source; committed a feat before tests ran (0/4); task discovery by reading library source, never confirmed against the pinned registry |
| 2 | Small change: spatial grouper on patrol-chart + re-run tests | Correctly found the spec already had it; added a mock case; 8/8 green; 2 commits | `_recompile.yml` never opened (only `ls`ed); test runs piped through `tail -60` and `grep -v`; committed the new case before running it; branch `feat/*` not `develop/*`; glob incidentally read the other checkout. Correctly refused to dev-compile the publish-state tree (signal: `wt-task-gcp` in inner `pixi.toml`) |
| 4 | Polish: duplicate heading on event-sum-map's form | Right fix (`ui:options.displayLabel: false`, copied from sibling specs); `base` case green; 1 commit | Hand-assembled the CI compile *without* `--update` on a publish-state tree → lock deleted, VERSION reset to 0.0.0, restored piecemeal; skipped `dot -c` until the compile died at the graph step (inside a `\| tail -30`); deviated from `dev/recompile.sh` "to avoid its `pixi update`"; ran only `--case base`; final commit bundled a 4.4k-line lock re-solve + VERSION 1.0.0→1.1.0 into a `fix:` |
| 3 | Publish: patrol-track-density-map from a develop branch one `fix:` over main | Reached the push boundary: gcp recompile at the pinned compiler, 6/6 mock cases, VERSION 1.2.0, 2 commits; 3 compile attempts | Read `dev/recompile.sh` then hand-assembled the compile "to avoid its `pixi update` churning the root lock" — so skipped `dot -c`, the compile died at the graph step **after `--clobber` emptied the tree**, a lock+VERSION-only restore made `--update` refuse (README missing), whole-tree restore on attempt 3; bumped platform 2.17→2.19 and ext-custom rc18→**0.1.0 final** unasked ("the skill's Publish setup has update-deps steps"), 16k-line lock churn in a `chore:`; every compile through `grep -v \| tail -40`, the test loop through `--quiet \| tail -4` with no exit code; invented a suffixed `publish/<repo>-2026-08-26` branch. Correct: gcp from the script not asserted, pins verified with `pixi search`, VERSION from `--update` kept, secrets read not set, stopped before push |
| 9 | Task: patrol effort per ranger (hours, km) in the custom task library, usable from a spec | Right place and shape (`tasks/analysis/_patrol_effort.py`, `@register`, excluded `AnyDataFrame` input, `AdvancedField`), re-exported, 9 flat synthetic unit tests green, 2 local commits, no push | Contract never designed or approved (ranger column, units, rounding, empty input all silent — only disk questions "would have been asked"); registry proof = unfiltered 695 KB `--format json` dump to `/tmp` + `grep -c`, not `--function` / `public_module_path`; "usable from a spec" proven by a scratch workflow **inside the library worktree** and, after ENOSPC in the compiler's ephemeral env, a hand-rolled driver importing `wt_compiler` internals with discovery replaced by the saved dump (the unmodified CLI compile later exited 0 once disk freed); env binaries called from `.pixi/envs/default/bin/` not `pixi run`; every command through `tail`/`head`; no editable pin, PR text or release ask handed back; branch `feat/*`. Worktree was `wt-release-candidate`, not the legacy default branch |
| 10 | Plan: subject speed distribution for MMNR, empty directory | Wrote a PRD and did not build; research-first (three reference specs, fixture schema and row count, a real `apply_classification`+`draw_chart` bin-ordering trap found in source, a doc-vs-spec conflict resolved for the specs); form card by card, 9 widgets with layout, 6 cases, one optional task contract | 13 questions it "would have asked one at a time" (legacy skill forbids batching); task existence from `search-tasks.py` + source, never a registry; PRD = 1,450 lines with an 830-line `spec.yaml` draft, layout and cases inline, legacy three-phase dev strategy and `/implement-workflow` handoff prompts; `progress.yaml` written unconditionally in the `setup`/`tasks`/`wrapup` state-machine shape; `.scratch` gitignore asserted from legacy text; a validation script written to `/tmp`; `\| head` / `\| tail` habitual |
| 5 | Guide: write the user guide README for patrol-chart (one already committed) | Corrected README, every field from `rjsf.json`, examples from cases, series labels checked against three mock runs and the library source; 4 commits | Rewrote an 8-section README in place (+191/−99) where a dozen targeted fixes were due — "the user said 'write'"; renumbered cards out of form order, added a non-template section and two examples; replaced the `mep_dev` example connection with the mock fixture's `er_asia` (data rule over-applied); resolved a form-text-vs-behaviour discrepancy inside the README; harness piped through `tail -60` / `--quiet \| tail -5` with no exit code; `docs/*` branch; four commits for one docs change |
| 6 | E2E: Desktop test for patrol-chart's base case + dashboard renders | Lint-clean, type-checked test with a real render assertion (widget wrapper, spinner gone, content iframe, no Retry); stopped before running with the command and missing preconditions written down; 2 commits | No live form (no CDP), so timezone / data-source / Add-button ids came from the legacy notes, unverified; automated the GitHub import and picked the tile with `.first()` (local and GitHub copies share the test-id); refactored two shared page objects in an "add a test" job; assertions UI-only (no data-dir path — portable by construction, but no on-disk check) |

## Cross-cutting patterns (4/4 of the step-2/3 runs)

- **Output piping.** Every run filtered compile and test output through `tail`, `head`, or
  `grep -v`, never with a stated reason — treated as cosmetic noise reduction. This is the
  exit-code-masking failure the plan calls out; it needs the prohibition form. Scenario 3 kept
  `PIPESTATUS` for the compiler and dropped it entirely for the test harness.
- **`--clobber` vs the lockfile.** Two of three runs deleted the inner `pixi.lock` with a plain
  `--clobber` and then could not run tests (`dev/run-test-cases.sh` always uses `pixi run
  --locked`). Both rediscovered `--update` semantics by reading `wt_compiler/artifacts.py`. The loop
  must state: first compile `--clobber --install`; iteration `--clobber` then restore the lock from
  HEAD; `--clobber --update` only when `requirements:` changed (it re-solves).
- **Commit timing.** Two runs committed before the tests they had just written were run, reading
  the global "commit at the end of every step" as commit-after-edit. The loop is one step; commit
  on green.
- **CI file as the flag authority.** Only one of the step-2 runs opened
  `_recompile.yml`/`dev/recompile.sh` before compiling, and that run then deviated from it;
  the publish run read both in full and *still* deviated (dropped the script to avoid its
  `pixi update`, losing its `dot -c`). Reading is not the gap — running what was read is. The legacy `ecoscope-ops.md` (loaded via
  the global CLAUDE.md pointer) asserts `--variant=gcp` universally for publish mode; all three runs
  absorbed that framing, and it happened to be right for both target repos.
- **Ceremony.** Small jobs were sized correctly and kept small. The greenfield job was not sized
  at all — it went straight to building.
- **Lane.** Branches were `feat/*` and `fix/*`; nothing supplied `develop/<topic>`.

## Verbatim rationalizations carried into the skill's counters

- "Called the compiler directly rather than `dev/recompile.sh` to avoid its unconditional `pixi update`."
- "Docs table says dev iteration = `--clobber` only, but that wiped `pixi.lock`."
- "Per the global workflow: scaffold → commit; spec+compile → commit; fix+retest → commit."
- "Keep it small: bind month interval + effort metrics + styling in the spec" (greenfield design decided silently).
- "A feature branch buys nothing here." / "assumed a local `fix/…` branch is fine."
- "Proceeded with committing [the lock churn]: it matches what CI's `recompile.sh --update` produces."
- "rather than `dev/recompile.sh` (which also runs `pixi update` on the root manifest and would churn the root `pixi.lock`)." (publish)
- "The skill's Publish setup has 'Update task libraries' / 'Update versions' steps." (publish — pins bumped unasked)
- "`--update` because both `pixi.lock` and `VERSION.yaml` exist on `main`." (publish — README not restored, `--update` refused)

## Step 4 — companion baselines (scenarios 5 and 6, 2026-08-26)

Both agents sourced their facts from the artefacts unprompted — the compiled `rjsf.json` first,
then cases and runs (5), the suite's fixtures, page objects and the app bundle (6) — so the
companion skills bind **process**, not sourcing: mode (gate vs write) decided from the README on
disk and edits confined to what the gate lists; card order and numbering from `ui:order`; org
constants allowed in examples but fixture-only names not; one commit; harness exit codes to a
file. For `e2e`: the three preconditions (CDP, tile, connection) as an explicit stop with the run
command written down; test-ids from a live scaffold or the test is labelled a draft; tile
disambiguation by subtitle; page objects reused, not refactored; the app-data dir resolved per
platform when an on-disk assertion is wanted (the older tests in that repo hardcode the macOS
path and are the wrong model). Two reference corrections came out of run 6: the GitHub-URL
import *is* automatable through the suite's page object (the legacy note said never to try),
and the results page's anchors (`workflow-results-navbar`, `iframe-widget-<slug>`,
`iframe-widget-content-<type>`, "Loading content...") are verifiable in the app bundle.

## Step 6 — task and plan baselines (scenarios 9 and 10, 2026-08-26)

Both runs reached the right artefact — a registered, tested task in the right module; a PRD
without a build — so the two skills bind **the seams around the artefact**, not its shape. For
`task`: the contract (name, library, typed inputs, output, io or not) proposed and approved
before authoring, since the baseline decided every field of the signature silently; the registry
proof as one filtered `wt-registry --function <name> --format json` whose pass condition is
stated (one entry, `public_module_path` is the category package, stderr empty) — the run dumped
the whole registry to `/tmp` and grepped a count; the boundary that the compile proving
`task: <name>` is `develop`'s in the workflow repo — the run built a scratch workflow inside the
library and, when the compiler's ephemeral env hit ENOSPC, hand-rolled a compile driver around
`wt_compiler` internals rather than halting; the return report (editable pin block, spec
reference, release condition) that the run never produced; and the branch fact that the
library's default branch is still the legacy framework. For `plan`: one batch of questions with
a default each (the legacy skill's one-at-a-time HALTs produced 13 sequential questions); the
registry via `pixi exec` when nothing is compiled yet; the PRD as decisions with no `spec.yaml`
draft (the run's PRD was 1,450 lines, 830 of them spec); `progress.yaml` gated on a Size answer
and shaped as milestones, not the `setup`/`tasks`/`wrapup` state machine the run copied; and the
greenfield placement asked once rather than the legacy hardcoded `~/MEP/wt-workflows/` default.
One reference correction: `wt-registry --format pretty` prints the private defining module in
its header and `Import:` line even for a re-exported task — the public path is only in
`--format json` (`task-discovery.md`). A second run of each scenario was needed: the first pair
was killed by the session usage limit before writing anything.

## GREEN micro-test (scenario 2, skill embedded in the prompt — not the step-7 eval)

Same worktree state, same prompt, with the `develop` SKILL.md draft pasted in as the procedure.
Every baseline failure point bound: `_recompile.yml` read first and the variant derived from it;
all compile/registry/test output redirected to files and read whole (no `tail`/`grep -v`); state
stated before acting; job sized with "what is actually missing" named; `develop/<topic>` branch;
registry confirmation in the inner env; one commit after `--all` green; handoffs offered, not
started. Functional outcome identical to the baseline (8/8 green, one new case). Three wording gaps
it exposed (`wt-compiler --version` isn't a flag; detached-HEAD branch read; compile only when a
compiler input changed) were fixed in the same pass. Residual for step 7: scenarios 1 and 4 have not
been re-run with the skill; the greenfield design-approval stop and the publish-state CI-recompile
path are untested GREEN.

## GREEN micro-test 2 — redesigned skill (2026-08-26)

Scenario 2 re-run against the design-first spine (no state derivation, design + approval for every
job, form/dashboard as requirements, human verification prompt). The agent produced a complete
design proposal and stopped for approval before editing; skipped the compile for a test-only edit;
redirected all harness output to files; investigated a single-view result before committing;
committed once after `--all` 8/8; ran its own verification and wrote a filled-in human
verification prompt; offered handoffs without starting them. Four wording gaps fixed. One
reference conflict remains for the owner: `compile.md`'s "never dev-compile a publish-state tree"
vs. the improve-loop model where a dev compile's VERSION/lock reset is expected and `publish`
restores it.

## GREEN micro-test 3 — publish (2026-08-26)

Scenario 3 re-run on the same frozen snapshot with the `publish` SKILL.md as the procedure
(reference files read from the plugin tree; `/ecoscope:*` and `/pr` unavailable). Every RED
failure point bound: `bash dev/recompile.sh --update` run verbatim through the outer pixi env
(exit 0 first try, `dot -c` and the outer-lock churn included), whole-tree restore from base
first, CI's exact four-exclusion diff read (two `dags/*.py` lines from the fix; byte-identical to
develop's compile), variant and `win-64` checked, **pins left as develop proved them with the
available refresh named and not applied**, VERSION 1.2.0 from a single `--update` with the
reason stated and checked against main and tags, every exit code recorded to a file, no
suffixed branch (the canonical one being checked out elsewhere and ahead of develop went into
the proposal as a question), one release commit, stopped before push with the `/pr` commands
and a landing plan. 6/6 mock cases green. Six wording gaps fixed in the same pass, one of them
factual: some repos' CI runs `dev/pytest-cli.sh <id> --all` rather than
`dev/run-test-cases.sh --all` (`ci.md` corrected). Residual for step 7: no run yet on a repo
with `tag.yml` / legacy tags, a `staging` base, or editable pins to revert.

## GREEN micro-test 5 — guide (2026-08-26)

Scenario 5 re-run on the same worktree reset to `main` with the `guide` SKILL.md (pre-feedback
draft) as the procedure. Every RED failure point bound: gate mode chosen from the README on disk,
a missing / stale / extra report written and the approval stop honoured before any edit, the
diff confined to the flagged sections (+57/−38 against RED's +191/−99; the `-U0` hunk list
checked), card numbering kept in `ui:order` with the fleet's Advanced Configuration section
added, `mep_dev` kept as an org constant, the form-text-vs-`required` contradiction reported
rather than resolved, base run and check redirected to files with exit codes, one
`docs(readme):` commit after the check exited 0. Six wording gaps fixed: the required/optional
rule for arrays and defaulted fields, grouper options by label (the style guide had format
codes), untitled arrays, exit-code discipline for the check script, and — the substantive one —
`form-inventory.py` now lists each union row type's own fields (`Unit`, `Event Field to Sum`),
which is where RED and GREEN both found the stale "Aggregate Column" only by reading `$defs`;
those are reported as advisory `REVIEW` lines, since fleet prose compresses row types
("per Distance / per Duration"). Residual for step 7: write mode (a repo with no README) and
a catalog workflow (no Desktop prerequisite, no Installation) have not been run GREEN; the
review-feedback changes (platform derivation, methods named, one example, pruned
troubleshooting) postdate this run.

## GREEN micro-test 6 — e2e (2026-08-26)

Scenario 6 re-run on the same worktree reset to `main` with the `e2e` SKILL.md (pre-feedback
draft) as the procedure, the app declared unavailable. Every RED failure point bound: the design
table written and the approval stop honoured, with the connection, window and patrol-type filter
put to the user as an explicit question; the GitHub tile chosen and filtered by subtitle; page
objects reused untouched (the RED run had refactored two); the app-data dir resolved per platform
through a new shared helper with no literal path; assertions on disk (`result.json` error/views,
an `.html` beside it) *and* in the UI (navbar, widget wrapper, content iframe, spinner gone, no
retry); every id it could not see marked in the file header and time-bounded; stopped before
running with the scaffold and the run command written down; lint, prettier, `tsc` and the
pre-commit hook green; one `test:` commit. Eight wording gaps fixed, one of them factual: widget
files are `<hash>_<suffix>.html`, not `*_v2.html` (`preview-dashboard.md`, `desktop-e2e.md`);
the "only select-widget is the Data Source" rule was wrong for forms with oneOf selects. Residual
for step 7: no GREEN run with the app on CDP (the scaffold-then-fill loop and the run itself are
untested), and the review-feedback changes (data source and window as the user's decision, base
case green before any other) postdate this run.

## Step 7 — with-suite eval (scenarios 1–4, 2026-08-26 / 2026-08-31)

Same four scenarios re-run with the built skills (`develop` for 1, 2, 4; `publish` for 3), same
harness, prompt = the baseline prompt with the skill embedded verbatim (`${CLAUDE_PLUGIN_ROOT}`
resolved to the plugin path). Graded against assertions fixed before the runs
(`.scratch/evals/assertions.md`: C1–C10 common, D1–D8 develop, P1–P8 publish) from each
subagent's own report — commands verbatim, reasoning, final `git status`/`git log` — not from a
re-run. Per-scenario result files with evidence per assertion: `.scratch/evals/results/`.

| # | Scenario | Skill | Assertions | Result | Bound from the baseline | Residual |
|---|---|---|---|---|---|---|
| 1 | Greenfield: patrol effort by month for MMNR | develop | 16/16 PASS (D2, D8 n/a) | 3 tiles + 3 monthly charts + table, 4/4 mock cases, 2 commits on `develop/patrol-effort-by-month`; accuracy check caught a real task bug (`apply_sql_query(sanitize=True)` duplicates rows on a non-unique index, table 3 % high) | six guessed design questions → one batched table at a stop; `tail`/`grep -v` → files + exit codes; lock wipe → `--install` first, lock kept; feat commit before tests → after 4/4; source-scan discovery → registry + signatures; inline README → `/ecoscope:guide` offered | `scaffold init` writes no `dev/` — harness hand-rolled (3 bugs) because the skill assumed it exists; `id: split_groups` copied from patterns.md and rejected by the compiler; both fixed |
| 2 | Small change: spatial grouper on patrol-chart | develop | 15/15 PASS (D3, D7, D8 n/a) | found the spec already had it, added one mock case, 8/8, 1 commit | `_recompile.yml` unopened → n/a (no compile either way, and said why); piping → files; unrun case committed → after `--all`; `feat/*` → `develop/*`; other checkout read → stayed inside | ambiguous "add X to the spec" (form default vs coverage) asked, not guessed |
| 4 | Polish: duplicate heading on event-sum-map | develop | 16/16 PASS (D2, D4 n/a) | `rjsf-overrides` title `" "` per rjsf.md, 4/4 mock cases, minimal 1 commit | hand-assembled CI compile without `--update` → dev compile per the flag table with the lock restored; `dot -c` skipped → n/a; `--case base` only → four cases; lock churn + VERSION bump in a `fix:` → one-line diff | worktree cut at `main` (dev state) not the publish tip the RED run used — not same-state; `--all` skipped (live cases, no credentials) |
| 3 | Publish: patrol-track-density-map | publish | 18/18 PASS | continued `publish/<repo>`, `bash dev/recompile.sh --update` exit 0 first try, 6/6, VERSION 1.2.0, guide gate, 1 commit, stopped before `/pr` | three compile attempts / hand-assembled / `--clobber` emptied the tree → script verbatim, whole-tree restore first; unasked ext-custom rc→final bump → proposed line by line, declined; `tail -40` → files; suffixed branch → existing one continued | first test loop launched in the background and the turn ended (P8 pass after a nudge) |

Aggregate: 65/65 graded assertions PASS across the four scenarios (0 FAIL, 7 n/a). Every
baseline failure class (piped output, lock trap, red commits, invented branches, unasked pin
bumps, hand-assembled CI compiles, guessed designs) was absent in the with-suite arm.

Wording gaps the runs reported were fixed in the same commits as the grades (c2030a8 for 2–4,
this commit for 1): `--frozen` for editable `path:` deps; live cases without credentials → mock
only, report live as CI's; map-widget accuracy via view keys/legend titles/feature counts;
`create_func_magicmock` only for io tasks; publish's "already on the branch" pins, `pytest-cli.sh`
repos re-solving the inner lock, `[tool.wt] published` if present; greenfield's missing `dev/`,
the `id: split_groups` example, the lock-table `--update` row, `{"All": "True"}` view key, and two
task pitfalls (`extra__` trajectory columns — hit by both S1 runs — and `sanitize` row duplication).

Harness notes for the next eval: subagents launch long compiles/tests in the background and end
their turn waiting — write "run compiles and tests synchronously" into the prompt; verify the
worktree's start SHA against the branch tip before launching (S4 started at `main`); the shared
`$TMPDIR` fills with compiler temp envs from parallel jobs (S1 hit ENOSPC twice, `pixi clean` on
the inner manifest recovered it); S1 was cut twice by the API session limit and resumed from its
transcript.

## Review baselines (step 5) — cross-cutting

Full notes and answer keys: `.scratch/baselines/{7,8}-answer-key.md`, `7-review-readiness.md`,
`8-review-diff.md` (gitignored). Both runs were strong finders — the RED failures are method and
frame, not recall: a "read-only" probe that wrote (the never-edit rule needs `git status` before/
after every probe as mechanism, not intention); a two-artifact check (variant vs the repo's own
recompile flags) skipped although both sides had been read — checklist lines beat inference;
dev-state resets (VERSION 0.0.0, gcp dropped) escalated as branch defects instead of routed to
publish; exit codes still masked by `tail` in the long tail of commands; and no run named what it
could not verify in a fixed structure (tier, clean-list, human checklist) — each invented its own.
Harness caveat, recorded honestly: the baseline prompts themselves demanded per-finding
"earned by running or by reading?", so part of the skill's method was already in the prompt; the
skill text must own that instruction, and the GREEN arm must not weaken it. Two reference errors
surfaced and were fixed: `ci.md` claimed validate-spec rejects `path:`/`editable:` (it greps only
wildcards and `file://` — verified in both repos and the hub template; publish § 1/§ 6 tables
adjusted), and the plan's "recompute `Spec.sha256` in milliseconds" is impossible —
`Spec.model_validate` needs the discovery registry, so the fast tier uses git-history staleness
plus the fingerprint's `installed_requirements` instead.
