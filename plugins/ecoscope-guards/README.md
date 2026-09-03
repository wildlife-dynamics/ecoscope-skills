# ecoscope-guards

Two hooks for Ecoscope workflow repos, and nothing else — no skills, no commands. One of them can
block a commit, which is why it is a separate plugin: plugin hooks have no per-hook switch, so
installing this plugin *is* the opt-in, and uninstalling it removes them.

Companion to the `ecoscope` plugin, but independent of it — the guards work whether or not it is
installed.

## `sensitive_commit_guard.py` — PreToolUse (Bash)

When a Bash command contains a `git commit`, the guard reads the staged tree (plus the
tracked-modified set, for `commit -a` / `-am`) and decides by path:

| Staged path | Decision |
|---|---|
| `.scratch/**` | silent — the gitignored working area where real pulls belong |
| `**/*.example-return.parquet` | silent — a packaged task fixture, synthetic by construction |
| `dev/fixtures/**`, `resources/mock-data/**`, `src/**/tasks/**` | silent when the repo commits a `build_*_fixture.py` generator; **ask** when it does not |
| any other `.parquet .feather .geojson .gpkg .shp .kml .kmz .csv` | **deny** |

`.json` is never flagged: `layout.json`, `rjsf.json` and `params.json` are generated artefacts
that belong in the tree.

**Why a hard stop.** Real patrol data — GPS tracks, ranger names, patrol-information event details
— must never be committed. Several org workflow repos are public, and patrol positions and
personnel identities are operationally sensitive conservation data. Remediation is a history
rewrite plus a force-push, and GitHub may retain unreachable objects, so on a public repo it also
means a support request. That asymmetry is what makes this worth blocking rather than documenting.

**Why the fixture exemption.** CI and mock fixtures are supposed to be synthetic and reproducible
from a committed generator, which is the fleet pattern. A guard that fires on those trains people
to switch it off, so a repo with a generator commits fixtures silently; one without gets asked
once. Data a task library packages and loads through `importlib.resources` is deliberate but sits
in exactly the sensitive category, so it asks too.

**It is not a veto.** A denied tool call is a denied *agent* commit — run it yourself if the file
is fine, or move real data under `.scratch/`.

## `spec_edited_notice.py` — PostToolUse (Edit/Write/MultiEdit)

Advisory, never blocks. After an edit to any `spec.yaml`, it notes that the generated
`*-workflow/` package, its `rjsf.json` and the test results all still describe the previous spec.
Silent for every other file.

## Mechanics

Both hooks are invoked through `hooks/hook.sh`, which execs the Python script and exits silently
when `python3` is absent — failing open, because a hook that errors on every tool call is worse
than no hook. The same is true of anything unexpected: unparseable hook input, a cwd outside a git
repo, or a missing `git` all pass through untouched.

`spec_edited_notice.py` reaches the model through `hookSpecificOutput.additionalContext` and the
human through `systemMessage` — PostToolUse output is not symmetric, and only the former is read
back into the conversation.

To see what the guard would say about your current staging area, without committing anything:

```
printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$PWD" \
  | bash hooks/hook.sh sensitive_commit_guard.py
```

`bash test-hooks.sh` runs both hooks against a throwaway repo — 15 cases covering every row of the
table above, `commit -am`, chained commands and a cwd outside any repo. Run it after any change to
the guards.
