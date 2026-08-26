---
name: task
description: Use when an ecoscope workflow needs a task the task libraries lack or an existing task needs to be updated — a task contract handed over by develop (name, library, typed inputs, output, io or not), "write / add a task that …", "add X to ext-custom / the task library / ecoscope-platform", a task that raises inside a run or returns the wrong shape, a task the compiler cannot find although its source exists, or a library change that needs a PR and a release. Covers both libraries — ecoscope (conda ecoscope-platform) and ecoscope-workflows-ext-custom — and returns the editable pin develop wires. Does not fire for wiring a task that already exists into spec.yaml (develop), for "which task does X" questions (reference), or for releasing a workflow (publish).
---

# Add or fix a task in an ecoscope task library

Build to the contract `develop` handed over, prove the discovery chain with the registry —
never by reading source — and hand back the pin that puts the task in a spec. Every fact lives
in `${CLAUDE_PLUGIN_ROOT}/reference/` and is linked at the point of use; nothing is restated
here.

## Contents

0. The contract and the checkout
1. Design — then approval
2. Author
3. Register — proven by the registry
4. Test in the library env
5. Commit, PR — and stop
6. Return to develop
7. Hard rules
8. Handoffs

## 0. The contract and the checkout

**Environment: any shell; nothing is edited yet.**

**The contract** is the seam this skill builds to: *name, library, inputs with their types,
output, io or not* — from `develop`'s approved design, or from the user directly. If a piece is
missing, ask for the missing pieces in one batch with a proposed default for each, and ask
nothing else yet. When no library is named, propose it: `ecoscope-workflows-ext-custom` for
anything org- or workflow-specific (a release is a tag on that repo); `ecoscope` — the platform
SDK, conda name `ecoscope-platform` — only when the task needs platform internals or belongs to
every workflow (`${CLAUDE_PLUGIN_ROOT}/reference/task-discovery.md` § The discovery chain for
how the two register). "Fix a broken task" is the same contract with the current signature
filled in and the failing behaviour as the output line.

**The checkout is a sibling repo whose location only the user knows.** Resolve it in this
order and never assume a layout:

1. The workflow repo's `spec.yaml` already carries a `path:` requirement for that library —
   use that path.
2. Otherwise ask once: "Where is your checkout of `<library>`? (or: clone
   `https://github.com/wildlife-dynamics/<repo>.git` next to the workflow repo and I'll use
   that)". Record the answer for this session only. The path reaches the workflow repo in
   exactly one place — the dev-mode `path:` requirement `develop` wires in § 6 — and never a
   fixture, a script, a test or this skill.

**Read the library before touching it.** Its `pyproject.toml` is the authority:
`[project.entry-points."wt_registry"]` names the module the registry imports (`tasks =
"ecoscope_workflows_ext_custom.tasks"`; `ecoscope = "ecoscope.platform.tasks"`), the build
config lists the packages that ship, and the pixi section — when it has one — is the test env
(§ 4). A `CLAUDE.md` in the library may still describe the legacy `@task` decorator and an
`ecoscope_workflows` entry point; the pyproject on the branch you are on wins. **Base the work
on the branch the fleet's pins are released from, not necessarily the default branch:** find
it from the release tag a workflow pins (`git branch -r --contains v<version>`) and confirm
that branch's `pyproject.toml` declares the `wt_registry` entry point. Cut a topic branch from
it.

## 1. Design — then approval

**Environment: the library checkout, read-only, plus the plugin's search script.**

**Research before proposing.** Find the nearest existing task and copy its shape:
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/search-tasks.py --lib <tasks-dir> <keyword>` over both
libraries, then `-s <name>` for the signature (`task-discovery.md` § Finding an existing
task). Read that task's module and its test. Check the contract's name against both
libraries: the scan flags a name defined twice, and a bare reference to a colliding name is a
hard compile error (`task-discovery.md` § Turn the hit into a spec reference). If an existing
task plus spec wiring already covers the contract (`summarize_df`, `apply_arithmetic_operation`,
a `filter_df`…), say so and hand back to `develop` instead of adding a task.

Then propose, concretely:

| Item | Proposal |
|---|---|
| Location | `<tasks-dir>/<category>/_<module>.py` — the category the nearest task lives in (`analysis`, `transformation`, `io`, `results`, `config`, …); a new module, private (`_` prefix), one concern |
| Signature | the function as it will be written: every parameter `Annotated[T, Field(description=…)]`, DataFrame parameters typed with the platform aliases, the return type; which inputs are wire-only (`Field(exclude=True)`), which are advanced (`AdvancedField`, needs a default), which are optional without a null option (`SkipJsonSchema[None]`) — `${CLAUDE_PLUGIN_ROOT}/reference/tasks.md` § Annotations that drive the form |
| io or not | `tags=["io"]` only for a task that fetches from a connection or the network; then also the packaged fixture it returns under mock-io (§ 2) |
| Behaviour | the computation in a sentence, the output columns and units, what happens on an empty input and on a missing column |
| Tests | the unit-test cases: a small synthetic frame with hand-computed expected numbers, the empty frame, the error path |
| Spec reference | the line `develop` will write: `task: <name>` bare — or the public path if the name collides |
| Branch | `<topic>` off the release branch from § 0 |

**Stop and wait for approval.** After approval §§ 2–5 run without check-ins, per the user's
global workflow; come back for a failing registry proof you cannot explain, a test that needs
data you do not have, or the PR.

## 2. Author

**Environment: the editor.** Write the module to `tasks.md` § Task anatomy: `@register()` from
`wt_registry`, every parameter and the return annotated (the validator rejects an untyped
parameter, a missing return annotation, async functions and classes — and it runs lazily, so
the failure surfaces at schema build, not at import), a docstring that says what the task does
and what it returns, `cast()` on the return. A DataFrame in and out means `AnyDataFrame` /
`AnyGeoDataFrame` from `ecoscope.platform.annotations`.

- **Imports.** The package's `tasks/__init__.py` imports every category at package load, so one
  module-level import that fails takes every task in the library with it, silently
  (`task-discovery.md` § A task is missing — the swallowed ImportError). Import heavy or
  optional libraries inside the function, and add a runtime dependency to the library's
  `pyproject.toml` (and its release recipe, where the repo keeps one) rather than assuming it is
  installed transitively.
- **io tasks.** `@register(tags=["io"])`, and the fixture the mock runner returns in its place:
  `<function-name-dashed>.example-return.parquet` (or `.json`) beside the module, **synthetic**,
  shaped like the real return (`${CLAUDE_PLUGIN_ROOT}/reference/testing.md` § How mock-io
  works, § Generating mock data). The fixture is shared by every workflow that mocks the task,
  so its shape is part of the contract. Where the library enumerates package data per module
  (`ecoscope` does), add the new module's pattern; ext-custom ships the package directory whole.
- **Modifying a task.** Keep the signature compatible unless the contract changes it — a
  renamed or retyped parameter changes every workflow's `params_sha256` and forces a MAJ bump at
  their next publish (`${CLAUDE_PLUGIN_ROOT}/reference/compile.md` § `--update` semantics).
  Say so in the PR.

## 3. Register — proven by the registry

**Environment: the library's own pixi env** — ext-custom's manifest is
`src/ecoscope-workflows-ext-custom/pyproject.toml` (the package is installed editable there,
next to a released `ecoscope-platform`); `ecoscope` has no manifest of its own and uses the
shared editable dev workspace the user has configured (`${CLAUDE_PLUGIN_ROOT}/reference/environments.md`
§ The five environments — ask its name once if you do not have it). Never `conda activate`.

Wire the chain (`task-discovery.md` § The discovery chain): the entry point already exists per
library, so a new task needs no pyproject change; the **category `__init__.py`** re-exports the
function (`from ._module import name` and `__all__`), and a *new* category is also imported by
`tasks/__init__.py` and listed in the build config where packages are enumerated.

Then prove it — this is the only proof; a re-export you can read is not one:

```bash
pixi run --manifest-path <manifest> --frozen wt-registry --function <name> --format json \
  > registry.json 2> registry.err; echo exit=$?
jq '.entries[] | {function_name, public_module_path, import_statement}' registry.json
cat registry.err
```

Pass = exit 0, **exactly one** entry whose `public_module_path` is the category package
(`ecoscope_workflows_ext_custom.tasks.analysis`, not `…analysis._module` — a private path
means the re-export is missing), and `registry.err` empty. `--format json` also builds the
entry's `json_schema`, so an entry that appears here has passed signature validation. A
`Warning: Could not import …` in `registry.err` means the whole package vanished — fix the
import before anything else. The env holds both libraries, so **two entries is the collision
case**: the spec must then use the public path, and § 6 says so. Do not use `--format
pretty` for this check — its header and `Import:` line print the private defining module —
and never dump the unfiltered registry and grep it: a count is not a public path, and the
dump is hundreds of kilobytes (`task-discovery.md` § Ask the registry).

## 4. Test in the library env

**Environment: the library's own pixi env, through its test task.** Tests are flat functions
in the library's `tests/` tree next to the existing ones, with the synthetic frame built in the
test and the expected numbers computed by hand in the test body, not by calling the code under
test. Run the file, then the suite, with the exit code recorded:

```bash
pixi run --manifest-path <manifest> --frozen pytest <tests-dir>/test_<name>.py > test.log 2>&1; echo exit=$?
pixi run mypy > mypy.log 2>&1; echo exit=$?          # the root task, where the repo has one
```

(ext-custom's root `pixi run pytest` runs the whole suite after a Playwright install; the
manifest-level invocation above runs one file without it. The `/pr` skill runs the mypy gate
again before pushing.) Read the whole log. An io task's fixture is loaded the way the mock
runner loads it — `wt_task.testing.create_func_magicmock(anchor, func_name)()` — and its
columns compared with the real return's.

The compile that proves `task: <name>` resolves from a spec belongs to `develop` on return
(§ 6), in the workflow repo, with the compiler as shipped; this skill does not edit a workflow
repo and does not build one inside the library. If no workflow exists yet, § 3's registry
entry is the proof. A compiler that cannot run here (no disk for its ephemeral env, a solve
that fails) is a halt to report, not a reason to drive `wt_compiler` internals by hand.

## 5. Commit, PR — and stop

**Environment: git and `gh`.** One commit per green cycle on the topic branch (`feat(tasks):
<name> — <what it computes>` / `fix(tasks): …`): module, re-export, fixture, tests, dependency
lines — together. Then hand to the user's `/pr` skill when it is available (it runs the mypy
gate, pushes, opens or updates the PR and watches CI); without it, `git push -u origin
<branch>` and `gh pr create --base <release branch>`. The PR body carries the contract, the
registry proof (`public_module_path`), the tests, the workflow it serves, and the release ask:
"needs a tag `v<next>` and a channel build before that workflow can publish" — a release on
these repos is a tag plus the maintainer's build-and-push, and it is theirs, not yours.

Stop at the open PR. Merging, tagging, `rattler-build` and the channel upload wait for an
explicit go-ahead (`${CLAUDE_PLUGIN_ROOT}/reference/process-rules.md`).

## 6. Return to develop

Report back in the shape `develop` § 2 consumes:

- **Requirement to wire**, replacing the library's released pin in `spec.yaml` until the
  release lands (`${CLAUDE_PLUGIN_ROOT}/reference/spec.md` § Editable / path requirements):

  ```yaml
  - name: ecoscope-workflows-ext-custom
    path: <checkout>/src/ecoscope-workflows-ext-custom     # absolute; the user's path from § 0
    editable: true
  ```

  For `ecoscope` itself the requirement is `{name: ecoscope, path: <checkout>, editable: true,
  extras: [platform, …]}` **plus the full conda pin stack** in that section — copy it, do not
  reconstruct it. Either way the first compile is `--clobber --install` and
  `./dev/postcompile-editable.sh` follows every compile; CI rejects `path:`, so the pin reverts
  at `publish`.
- **Spec reference**: `task: <name>`, or `task: <public_module_path>.<name>` when § 3 showed two
  entries.
- **What the task returns** (columns, units, empty-input behaviour) — the widget chain is
  designed against it.
- **Release condition**: the PR URL, and that `publish` § 2's channel gate needs a released
  version carrying this task before the workflow can ship.
- If the workflow repo's `.scratch/progress.yaml` lists this task as a milestone, mark it
  reached (`${CLAUDE_PLUGIN_ROOT}/reference/repo-layout.md` § `.scratch/`).

## 7. Hard rules

Each has its mechanism in the linked file; here they are prohibitions because they get broken
under pressure ("the re-export is right there", "it's just a local path", "the PR is green
anyway").

- Never claim a task is registered because its source, entry point or `__init__.py` look right
  — only § 3's `wt-registry` entry, in the library env, with an empty stderr, is proof
  (`task-discovery.md`: an ImportError is a stderr warning and the package vanishes).
- Never hand back a bare name that the registry lists twice — qualify with
  `public_module_path` (`task-discovery.md`).
- Never assume where a library checkout lives, and never write that path anywhere but the
  spec's dev-mode `path:` requirement (§ 0).
- Never prove "usable from a spec" with a scratch workflow inside the library or a compile
  that bypasses the compiler's own discovery env — the proof is `develop`'s compile in the
  workflow repo (§ 4, `task-discovery.md` § The discovery chain).
- Never merge, tag, `rattler-build`, or upload to a conda channel without an explicit
  go-ahead; opening the PR is fine (`process-rules.md`).
- Never put real organisational data in a fixture or a test — synthetic frames only
  (`process-rules.md`, `testing.md`).
- Never pipe `pixi`, `pytest` or `wt-registry` output through `tail`, `head` or `grep -v`;
  redirect to a file, record the exit code, read the file. Never `conda activate`
  (`environments.md`).

## 8. Handoffs

Offer each when it becomes relevant, and wait for a yes; never start one unasked.

| When | Offer |
|---|---|
| The task is registered, tested and its PR is open | back to `/ecoscope:develop` with § 6's report — it wires the editable pin and compiles |
| The branch is committed and ready | `/pr` — or the manual push and `gh pr create` in § 5 |
| The workflow is ready to release but the library is not | the maintainer's tag + channel build (not a skill); `/ecoscope:publish` § 2 checks the channel |
| An existing task turns out to be the answer | `/ecoscope:develop` — no library change |

Close every session by naming what comes next. Do not start it.
