# Process and safety rules

Org-level rules that override convenience everywhere in the suite.

## Sensitive data — the highest-priority rule

Real patrol data — GPS tracks, ranger names, patrol-information event details — must **NEVER** be
committed. Several org workflow repos are public; patrol positions and personnel identities are
operationally sensitive conservation data.

- Local pulls of real data go under gitignored `.scratch/`, never `resources/` or `dev/fixtures/`.
- CI and mock fixtures are **synthetic**, produced by a committed generator script (the fleet
  pattern: a `dev/fixtures/build_*_fixture.py` alongside its generated parquets, plus an
  anonymizer where needed).
- Real patrol-type/event-type *slugs* are org configuration and fine to commit.
- If real data lands in a commit: history rewrite (filter-repo) + force-push, and note GitHub may
  retain unreachable objects — on a public repo that means a support request, not just a rewrite.

## Irreversible actions need an explicit go-ahead

Never merge PRs, cut or delete releases/tags, close someone else's PRs, or push to a default
branch without an explicit go-ahead. **"Can we merge?" is a readiness question, not
authorization** — answer it, state the plan AND its side effects ("merging cuts v0.4.0, which
publishes the template to Desktop users"), then wait for an explicit yes. Opening PRs, pushing
feature branches, and re-running CI remain autonomous. This matters doubly in repos where merging
auto-cuts a release ([ci.md](ci.md)).

## GitHub conventions

- **No labels on issues** — title + body only; omit `--label`/`--add-label`.
- **Issue project assignment**: org project "Workflows" (owner `wildlife-dynamics`, project 9);
  the free-text Project field is `WD General` for general workflow repos, or the client name for
  client-specific repos (`mt-*` → `Mara Triangle`).
- **`gh pr edit` fails in org repos** with a GraphQL Projects-classic deprecation error — use
  `gh api -X PATCH repos/<org>/<repo>/pulls/<n> -f title=… -f body=…` instead.
- **Repo secrets are set by the user** — `gh secret set` is permission-blocked for the agent.
  Surface exactly which secrets are needed ([connections.md](connections.md)) and stop.

## Org constants safe to reference

The prefix.dev channels (`https://repo.prefix.dev/ecoscope-workflows/`,
`https://repo.prefix.dev/ecoscope-workflows-custom/`), the `wildlife-dynamics` GitHub org,
connection names like `mep_dev`/`mmnr`, package names, and the branch conventions in
[repo-layout.md](repo-layout.md). 
