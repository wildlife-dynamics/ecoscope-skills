# Eval baselines (RED arm) — build steps 2–4, `develop`, `publish`, `guide`, `e2e`

Summary of the without-suite runs recorded on 2026-08-25 (scenarios 1, 2, 4) and 2026-08-26
(scenarios 3, 5, 6); full notes, verbatim commands and rationalizations live in the gitignored
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
