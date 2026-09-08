---
name: review
description: Use when the user explicitly asks for a review of ecoscope workflow work — "review this workflow / my changes / this branch", "is this ready for CI / for release?" — when /ecoscope:publish reaches its pre-release review gate, or when a review offered by develop is accepted; never fires unasked. Covers publish readiness against this repo's own CI, the fleet's spec/form/dashboard failure modes in a diff, and what a run actually produced. For generic correctness or security, use the built-in /code-review or /security-review.
---

# Review an ecoscope workflow

The gate between building and publishing. A review **reports and never edits** — its findings
are **earned** by running something or inspecting a primary artifact, never by reading intent.

## Contents

0. Method — what makes a finding
1. Scope and tier
2. Pass 1 — publish readiness
3. Pass 2 — the diff, through the fleet's failure modes
4. Pass 3 — what the run actually produced
5. The report
6. Hard rules
7. Handoffs

## 0. Method — what makes a finding

**Environment: any shell, from the workflow repo root; nothing is edited at any point.**

- **Earned, not asserted.** A finding rests on a primary artifact — the compiled `rjsf.json`,
  `result.json` and the files beside it, the repo's own `_recompile.yml` / `dev/recompile.sh`,
  `git show` of the base — or on a run you performed. Never on a commit message, a spec
  comment, a summary, or memory of what a file usually says. The report states, per finding,
  *ran X* or *inspected Y*; what was only reasoned from reading goes under "could not check
  here", not among the findings.
- **Refute before reporting.** A candidate ships only with a concrete failure scenario —
  specific state producing a specific wrong result. What cannot be stated that way is dropped,
  not hedged. Where the built-in `/code-review` machinery and its `ReportFindings` tool are
  available, use them for the ranking/verify pass instead of reinventing it.
- **Probes must not write.** Run `git status --short` before starting and again after **every**
  pixi or compiler invocation; any new diff means stop, `git checkout -- <file>`, and disclose
  it in the report. Probes that write while looking read-only: `pixi lock --check` (rewrites
  the lock), `pixi update`, and any `wt-compiler compile` — on the reviewed tree these are
  edits, not checks. If one already ran, the way back is
  `${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § Restore playbook.
- **Output goes to files.** `<command> > step.log 2>&1; echo exit=$?`, then read the file
  (`${CLAUDE_PLUGIN_ROOT}/reference/environments.md`). Grepping the saved file is fine.

## 1. Scope and tier

`git fetch origin` first — Pass 1 measures against `origin/main`, and a stale ref hides a
merged PR. Read the tree the way `${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md`
§ Repo-state signals reads it, and open the report with one line stating the scope: which
commit and branch are under review, what state the tree is in, and which passes apply —
"before we publish" and the publish pre-release gate run all three; "review my changes" runs
Passes 2–3; "check this run" runs Pass 3.

Two framing rules, before any finding is written:

- **Confirm the candidate.** `git rev-parse HEAD`, the `publish/<repo>` and develop branch
  tips, open PRs. If the tree under review is not the tip the user is about to act on, that is
  the first finding — reviewing the wrong commit invalidates the rest.
- **Dev state is not a defect.** On a develop branch, `VERSION.yaml` 0.0.0, a dropped gcp
  variant, and a re-solved inner lock are the expected residue of a dev compile
  (repo-layout.md § Repo-state signals); `/ecoscope:publish` restores them from base. List
  them as *publish-time items*, not branch defects — escalating them as regressions is noise.

**Name the tier, always.** Everything below is the **fast tier**: no compile, so it proves
staleness and contract violations but **never freshness** — and codegen drift from a different
compiler version is invisible to it (`${CLAUDE_PLUGIN_ROOT}/reference/compile.md`
§ Fingerprints, including why `params_sha256` is never a drift signal). The **authoritative
tier** is the CI-matching recompile — `/ecoscope:publish` § 3's checklist — which rewrites the
tree and therefore never runs inside a review: when the user is about to publish, hand there
(§ 7) and say the fast tier's verdict is provisional until it runs.

## 2. Pass 1 — publish readiness

**Environment: git and a read-only shell.** Everything CI will fail on, predicted before a CI
cycle is spent. The recompile checklist and the VERSION algorithm themselves live in
`/ecoscope:publish` § 3 and § 5 — this pass predicts what they will find, it does not run them.
The gates, one by one, in `${CLAUDE_PLUGIN_ROOT}/reference/ci.md` § The wt-family gates.

| Check | Earned by |
|---|---|
| Requirements CI rejects | `grep -nE 'path:|editable:|file://|version: *"\*"' spec.yaml` — wildcard and `file://` die in validate-spec; `path:`/`editable:` slip past it and die in the recompile job (ci.md § The wt-family gates) |
| Pins actually released | each `requirements:` pin resolves from its prefix.dev channel — the repodata proof in `/ecoscope:publish` § 2 (ci.md § Release tagging) |
| VERSION gate | numeric compare against **both** `git show origin/main:<WF>/VERSION.yaml` and the highest `git tag --list 'v*'` — legacy tags keep `tag.yml` monotonic (ci.md § Release tagging and legacy tags) |
| Variant — two-sided, never inferred | left: the flags this repo's CI passes (`.github/workflows/_recompile.yml`, `dev/recompile.sh`); right: `grep -c wt-task-gcp <WF>/pixi.toml` — a gcp flag demands ≥1, no flag demands 0 (compile.md § `--variant=gcp`). Reading the script is not the check; the comparison is |
| Tree provenance (fast drift) | `git log -1 --format=%h -- spec.yaml` vs `git log -1 --format=%h -- <WF>/` (spec newer than tree = stale); the README fingerprint's `installed_requirements` diffed against the spec's `requirements:` (a requirement missing there — e.g. an editable one — marks a dev compile); `git status` of `<WF>/`; hand-patches such as `dev/postcompile-editable.sh` edits to platforms or pins (compile.md § Fingerprints) |
| What fast drift cannot do | do **not** try to recompute `spec_sha256` — `Spec.model_validate` needs the task-discovery registry, so there is no compile-free recompute; beyond the signals above, drift is proven only by the authoritative recompile |
| Platforms and locks | `test.yml` runs Windows ⇒ outer `pixi.toml` `platforms` has `win-64` and the inner lock is solved for it (`grep -c win-64 <WF>/pixi.lock`); both locks re-solved with CI's pinned pixi (`scripts/preflight.sh` WARNs when the local one differs; ci.md § Pixi locks) |
| Cases and secrets | `test-cases.yaml` ≥1 case; template raw URLs SHA-pinned on a publish branch (`${CLAUDE_PLUGIN_ROOT}/reference/testing.md` § Template paths and raw URLs); the secrets `test.yml`'s `env:` names exist for every live case's connection — named for the user, never set (`${CLAUDE_PLUGIN_ROOT}/reference/connections.md`) |
| User guide | the root `README.md` describes **this** release — every card, field and default in the compiled `rjsf.json`, every widget the Pass 3 run produced. Count the stale mentions (a removed option still documented is a finding with a number on it). Stale ⇒ `/ecoscope:guide` is a gate before any PR (`/ecoscope:publish` § 6) |

## 3. Pass 2 — the diff, through the fleet's failure modes

**Environment: git and the compiled artifacts of this branch.** `git diff <base>...HEAD` plus
the compiled `rjsf.json` / `dags/*.py` on both sides (`git show <base>:<path>` for the base's).
These are the failure modes that look fine in source — each is convicted in an artifact, not in
the diff text:

- **Real data — stop everything.** GPS tracks, ranger names, patrol details anywhere in
  the commit (`resources/`, `dev/fixtures/`, cases). Not ranked with the rest: report it alone,
  immediately, with the remediation path
  (`${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md` § Sensitive data). Synthetic fixtures
  need their committed generator script beside them.
- **Same-title task groups.** Two `title:`s equal ⇒ the last group's schema clobbers the
  first's. Convict in `rjsf.json`: properties with no `type`/`$ref`/`anyOf`/`allOf` (phantom
  objects), fields present on the base side and gone on this side, a top-level `ui:order`
  shorter than the `properties` key count (the renderer hard-errors on that), orphaned override
  paths that manufactured a phantom card
  (`${CLAUDE_PLUGIN_ROOT}/reference/rjsf.md` § No duplicate task-group titles).
- **Widget tasks without `skipif: never`.** Every `create_*_widget_single_view` carries it, or
  an empty window kills the whole dashboard instead of rendering an empty widget. Convict in
  the compiled `dags/run_sequential*.py` skip conditions, and — when Pass 3 has an empty case —
  in its result (`${CLAUDE_PLUGIN_ROOT}/reference/patterns.md` § Widget pipelines).
- **Spatial-grouper resolver chain.** Extract → fetch (`map`) → resolve (`skipif: never`), and
  **every** consumer takes the resolver's return. A consumer wired to the raw groupers is a
  wrong edge that sequential mock runs mask — resolution mutates the grouper objects in
  place — and a serializing executor breaks
  (`${CLAUDE_PLUGIN_ROOT}/reference/patterns.md` § Grouping and splitting).
- **Conditional fields** — convict against the rule set in
  `${CLAUDE_PLUGIN_ROOT}/reference/rjsf-conditionals.md`, in the compiled `rjsf.json` on both
  diff sides, never in the spec text. Greppable there: `"dependencies"` / `"dependentSchemas"`
  present at all (never valid); a `default` on the conditional field; `additionalProperties` /
  `unevaluatedProperties` inside a restated object; a `then` overriding `items.oneOf`. A
  root-level `allOf` in `rjsf-overrides` is dropped on serialization — its symptom is the
  conditional *missing* from `rjsf.json`. Match the JSON key, not the bare word. A shape
  suspect but not grep-convictable goes to "could not check here", with § Headless contract
  testing as the proving path.
- **Details chains that widen the main path** — `normalize_json_column` on JSON strings loses
  data silently; `sanitize: true` re-joins on a non-unique index and inflates every downstream
  sum (`${CLAUDE_PLUGIN_ROOT}/reference/task-pitfalls.md`).
- **Orphan tasks.** Every task's return must feed another task or the dashboard. Sinks
  (`persist*`, `*download*`, `*export*`, `*push*`, `gather_dashboard`) are exempt:

  ```bash
  yq -r '[.workflow[] | select(.type == "task-group") | .tasks[],
          .workflow[] | select(.type != "task-group")] | .[] | .id + " " + .task' spec.yaml \
  | while read -r id task; do
      case "$task" in *persist*|*download*|*export*|*push*|*gather_dashboard*) continue;; esac
      grep -q "workflow\.$id\.return" spec.yaml || echo "ORPHAN: $id ($task)"
    done
  ```

- **Cases** — a `partial:`-bound param left in a case is `extra_forbidden`; naive datetimes,
  `TimezoneInfo`, spatial display names (`testing.md` § test-cases gotchas). A case whose
  description promises a shape the fixture cannot produce (three regions promised, one in the
  data) is a finding even when green — Pass 3 convicts it.
- **Generic correctness** — logic, typing, dead code in `dev/` scripts and fixtures: the
  built-in `/code-review` covers it; offer to run it alongside rather than duplicating it here.

## 4. Pass 3 — what the run actually produced

**Environment: the inner pixi env, only through the harness** (pixi and go-yq must work —
`${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh` if anything fails). Run every mock case:

```bash
./dev/run-test-cases.sh --all > test.log 2>&1; echo exit=$?
```

(`--frozen` when git-tag or editable requirements are present — compile.md § Compile-time
standing rules.) Read the whole log. **Green is necessary, not sufficient** — per case:

- `result.json` exists, `.error == null`, exit 0 (`testing.md` § `dev/run-test-cases.sh`) —
  and then **open the outputs**: widget files exist and are non-trivial, charts carry traces
  and maps carry layers (grep the HTML), tables have rows.
- **The silently-empty run**: a Success whose widgets hold no data, or whose `views` are empty,
  reads as a pass in every status check — it is the trap this pass exists for (`testing.md`).
- **Fan-out**: the `views` keys match what the case's groupers promise. A single view where the
  description promises one per region means the fixture never exercised the split — green, and
  still a finding. Ungrouped runs produce exactly `{"{}": …}` and Desktop hides Edit Layout
  (`patterns.md` § Dashboard assembly and the "Edit Layout" predicate).
- `layout.json` references only widget ids the run produced.
- A red case is a `/ecoscope:develop` job — report it with its trace and route it; never patch
  the case or the generated tree to make it pass.
- Live cases (`mock_io: false`) that cannot run here are reported as CI's to run, with their
  secrets checked by name (Pass 1).

## 5. The report

One fixed structure, every time:

1. **Scope line** — commit, branch, passes run, **tier: fast** (and what that cannot prove).
2. **Findings, ranked most-severe first** — except real patrol data, which is reported alone
   and immediately (§ 3). Each: severity — one-line claim — `file:line` or artifact evidence —
   the concrete failure it causes — *earned by: ran X / inspected Y*.
3. **Checked and clean** — what was covered and passed, so silence isn't ambiguity.
4. **Could not check here** — and why (no credentials, needs the authoritative recompile, no
   form renderer). Reading-based suspicions live here, labelled as such.
5. **Human-validation checklist** — emitted, filled in with this run's values, never checked
   off by you: do the numbers look plausible for `<time range>` in `<area/connection>` (quote
   the numbers the run produced); does the dashboard read well and do the view-selector labels
   make sense (`<keys observed>`); is the form wording right for the people who will use it,
   and does Advanced hold only what belongs there; does the README's prose match how its
   readers speak; live-only checks — connection-fed dropdowns list the real event types /
   feature groups, and spatial display names on the live server match what the spec assumes
   (a mock name coinciding proved nothing).
6. **Offer, don't act** — the fix path (`/ecoscope:develop`), the authoritative gate
   (`/ecoscope:publish`), or `/ecoscope:guide` — and wait.

## 6. Hard rules

Standing prohibitions: `${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md` (a review never
merges, tags, pushes or touches secrets) and `${CLAUDE_PLUGIN_ROOT}/reference/environments.md`
(output to a file + exit code, never through `tail`/`head`/`grep -v`). Restated here because
reviews break them under momentum ("it's just a lock check", "obviously a dev-compile
artifact"):

- Never edit, commit, compile, or "fix" anything during a review — including probes that
  write: `git status --short` after every probe; a diff means restore and disclose (§ 0,
  `compile.md` § Restore playbook).
- Never rank real patrol data with other findings — stop everything and report it alone
  (`process-rules.md` § Sensitive data).
- Never claim freshness from the fast tier, and never use `params_sha256` as a drift signal
  (`compile.md` § Fingerprints).
- Never present a reading-based guess as a finding — earn it, or file it under "could not
  check here" (§ 0).

## 7. Handoffs

Offer each when it becomes relevant, and wait for a yes; never start one unasked.

| When | Offer |
|---|---|
| Any red finding the user wants fixed | `/ecoscope:develop` — then review again |
| Readiness pass clean and the user wants the release | `/ecoscope:publish` — it runs the authoritative recompile this review deliberately did not |
| The README lags the release (Pass 1) | `/ecoscope:guide` |
| A finding lives inside a task implementation | `/ecoscope:task` |
| Desktop rendering claims need proving end to end | `/ecoscope:e2e` |
| Generic code health beyond the fleet's failure modes | the built-in `/code-review` |

When this review ran as `/ecoscope:publish`'s pre-release gate, a clean report hands straight
back to the publish flow that invoked it — no fresh yes needed for that return.

Close by naming what comes next — usually "fix via develop, or hand to publish" — without
starting it.
