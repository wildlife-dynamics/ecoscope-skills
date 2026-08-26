# Workflow repo layout and the development loop

What's hand-authored, what's generated, what's vendored, and the branch/commit conventions the
fleet actually follows. The repo-state signals table is the single source for reading a tree —
used by the publish and review procedures before they act on one.

## Contents
- Repo anatomy
- Vendored files (hub template sync)
- `.scratch/` planning artifacts
- Repo-state signals
- Branch and commit conventions
- The observable dev loop

## Repo anatomy

```
spec.yaml test-cases.yaml layout.json README.md    <- HAND-AUTHORED
pixi.toml                                          <- HAND-AUTHORED (compiler pin, graphviz, go-yq, [tool.wt].published)
pixi.lock                                          <- pixi-generated, TRACKED in publish repos
dev/run-test-cases.sh [recompile.sh postcompile-editable.sh]   <- VENDORED from the hub template
.github/workflows/*.yml                            <- VENDORED
.scratch/                                          <- GITIGNORED: prd.md, progress.yaml, local pulls
<prefix>-<id>-workflow/                            <- 100% GENERATED, committed (compile.md)
```

`.gitattributes` marks the generated tree `linguist-generated=true`. Verify `.gitignore` actually
contains `.scratch` before writing planning artifacts — a third of repos lack the entry.

Legacy catalog repos differ: no `dev/`, no outer `pixi.toml`, committed `__results_snapshots__/`
([ci.md](ci.md) for their CI family).

## Vendored files (hub template sync)

`dev/` scripts and `.github/workflows/` CI files are mirrored into workflow repos from the
**ecoscope-hub repo's `template/`** (a thin rsync against a target list; `run-test-cases.sh` is
byte-identical across synced repos). **Don't edit these files in a workflow repo** — changes get
overwritten on the next sync; edit the canonical copy in the hub template and re-sync. Per-repo
customization belongs in files outside the template tree. The hub also carries branch-protection
rulesets for the staging QA flow and the shared dev-workspace definition.

Not every repo is synced (the target list is maintained by hand), so the repo's checked-in copy is
still what CI runs — read it, don't assume ([ci.md](ci.md)).

## `.scratch/` planning artifacts

`.scratch/progress.yaml` is a **plan artifact for genuinely multi-session work** (a new workflow,
a migration, a publish cycle waiting on an upstream gate) — a plan the skill reads and updates at
milestones, not a state machine serviced on every step. `.scratch/prd.md` holds the PRD when one
was written. Real fleet examples record the phase, the gate being waited on, and the branch the
work was cut from. There is no root-level `progress.yaml` convention — only `.scratch/`.
`.scratch/` also holds local data pulls, which must never move out of it
([process-rules.md](process-rules.md)).

## Repo-state signals

How to read a tree — what the filesystem and git say, independent of what the request says:

| Signal | What it means |
|---|---|
| no `spec.yaml` in the target dir | greenfield — offer planning, then scaffold |
| `spec.yaml` present, no `*-workflow/` sibling | authored but never compiled |
| generated tree differs from a CI-matching recompile | stale — recompile before trusting anything ([compile.md](compile.md) fingerprints) |
| `VERSION.yaml` = `{0,0,0}` and no inner `pixi.lock` | last compile was a dev compile |
| inner `pixi.lock` + VERSION > 0 + `wt-task-gcp` in inner `pixi.toml` | **publish state** — a dev compile resets VERSION and drops the lock (expected while developing); publish restores both from base and recompiles the CI way before committing ([compile.md](compile.md)) |
| `path:` / `editable:` in `requirements:` | dev mode; must revert to released pins before publish |
| branch `develop/*` / `publish/*` / `staging` / base | which lane the work is in |
| `.scratch/progress.yaml` exists | a prior multi-session plan — read it and resume |
| `[tool.wt] published`, guard workflows, tags | publication state ([ci.md](ci.md)) |

## Branch and commit conventions

Three-lane branch naming: `develop/<topic>`, `publish/<repo-name>` (cut off the develop branch),
and long-lived `staging` in published repos; plus occasional `chore/*`, `fix/*`. PRs are
**squash-merged** — main is one commit per PR while the topic branch carries many fine-grained
commits. Conventional-commit prefixes (`feat:`, `fix:`, `chore:`, `docs:`, `test:`) throughout.

## The observable dev loop

The loop every recent repo shows, in order:

1. `feat: scaffold <name>` → `feat: populate spec, test cases, and layout` (often from a PRD).
2. Many small `feat:`/`fix:` commits, each a **spec.yaml edit + recompile**. The single
   most-iterated surface is the spec's rjsf/partial layer — field titles, hiding no-op fields,
   card ordering, defaults. Second: test cases (live cases, empty-fixture regressions).
3. Sometimes a dev/editable phase, reverted before publish
   (`chore: revert dev-mode requirements to released pins`).
4. Renames land as one commit + recompile.
5. Publish: publish-mode recompile (matching the repo's CI) → user-guide update → VERSION bump →
   PR → CI gates → merge auto-tags and cuts a release where `tag.yml` exists.
6. `chore: sync CI` commits when the hub template was re-synced.
