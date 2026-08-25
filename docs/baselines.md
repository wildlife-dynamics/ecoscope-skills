# Eval baselines (RED arm) — build step 2, `develop` spine

Summary of the without-suite runs recorded on 2026-08-25 (full notes, verbatim commands and
rationalizations live in the gitignored `.scratch/baselines/`). Scenario 3 (publish) is deferred to
build step 3. Harness: hand-rolled parallel subagents in detached git worktrees — `claude plugin
eval` is enabled on this install but runs each case in a throwaway workspace with no documented way
to target a specific worktree, and the plugin has no manifest until step 7; port these scenarios to
`evals/` then.

| # | Scenario | Result | Failures observed |
|---|---|---|---|
| 1 | Greenfield: patrol effort by month for MMNR | Built a working 3-chart workflow, 4/4 mock cases green, 4 commits | No planning offer, no design-approval stop (six design questions guessed); every compile/test piped through `tail`/`grep -v`; plain `--clobber` wiped the lock (harness needs `--locked`) and `--update` was rediscovered from compiler source; committed a feat before tests ran (0/4); task discovery by reading library source, never confirmed against the pinned registry |
| 2 | Small change: spatial grouper on patrol-chart + re-run tests | Correctly found the spec already had it; added a mock case; 8/8 green; 2 commits | `_recompile.yml` never opened (only `ls`ed); test runs piped through `tail -60` and `grep -v`; committed the new case before running it; branch `feat/*` not `develop/*`; glob incidentally read the other checkout. Correctly refused to dev-compile the publish-state tree (signal: `wt-task-gcp` in inner `pixi.toml`) |
| 4 | Polish: duplicate heading on event-sum-map's form | Right fix (`ui:options.displayLabel: false`, copied from sibling specs); `base` case green; 1 commit | Hand-assembled the CI compile *without* `--update` on a publish-state tree → lock deleted, VERSION reset to 0.0.0, restored piecemeal; skipped `dot -c` until the compile died at the graph step (inside a `\| tail -30`); deviated from `dev/recompile.sh` "to avoid its `pixi update`"; ran only `--case base`; final commit bundled a 4.4k-line lock re-solve + VERSION 1.0.0→1.1.0 into a `fix:` |

## Cross-cutting patterns (3/3 runs)

- **Output piping.** Every run filtered compile and test output through `tail`, `head`, or
  `grep -v`, never with a stated reason — treated as cosmetic noise reduction. This is the
  exit-code-masking failure the plan calls out; it needs the prohibition form.
- **`--clobber` vs the lockfile.** Two of three runs deleted the inner `pixi.lock` with a plain
  `--clobber` and then could not run tests (`dev/run-test-cases.sh` always uses `pixi run
  --locked`). Both rediscovered `--update` semantics by reading `wt_compiler/artifacts.py`. The loop
  must state: first compile `--clobber --install`; iteration `--clobber` then restore the lock from
  HEAD; `--clobber --update` only when `requirements:` changed (it re-solves).
- **Commit timing.** Two runs committed before the tests they had just written were run, reading
  the global "commit at the end of every step" as commit-after-edit. The loop is one step; commit
  on green.
- **CI file as the flag authority.** Only one run opened `_recompile.yml`/`dev/recompile.sh`
  before compiling, and that run then deviated from it. The legacy `ecoscope-ops.md` (loaded via
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
