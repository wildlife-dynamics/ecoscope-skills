#!/usr/bin/env python3
"""PreToolUse(Bash) — stop a `git commit` that would put real patrol data into git history.

Real GPS tracks, ranger names and patrol-information details are operationally sensitive, several
workflow repos are public, and the remediation is a history rewrite plus — on a public repo — a
GitHub support request. That asymmetry is why this is a hard stop rather than a documented
intention.

Decision, by staged path:

    .scratch/**                     ignored (the gitignored working area for real pulls)
    **/*.example-return.parquet     allowed (packaged task fixture, synthetic by construction)
    dev/fixtures/**                 allowed when the repo commits a build_*_fixture.py generator,
    resources/mock-data/**          ASK when it does not
    src/**/tasks/**                 same: data a task library packages and loads through
                                    importlib.resources is deliberate, but "all patrols" is also
                                    the sensitive category, so a human decides
    any other data file             DENY

Data extensions only; .json is excluded because layout.json, rjsf.json and params.json are
generated artefacts that belong in the tree.

Fails open on anything unexpected — unparseable input, no git repo, git not installed.
"""

import json
import os
import re
import subprocess
import sys

DATA_EXT = (".parquet", ".feather", ".geojson", ".gpkg", ".shp", ".kml", ".kmz", ".csv")
FIXTURE_DIRS = ("dev/fixtures/", "resources/mock-data/")
PACKAGED = re.compile(r"(^|/)src/.+/tasks/")  # data a task library ships and loads as a resource
GENERATOR = re.compile(r"(^|/)build_[A-Za-z0-9_]*fixture[A-Za-z0-9_]*\.py$")
# `git … commit` within one shell segment: `git commit`, `git -C x commit`, `a && git commit -m x`.
COMMIT = re.compile(r"(?:^|[;&|\n])[^;&|\n]*\bgit\b[^;&|\n]*\bcommit\b")
COMMIT_ALL = re.compile(r"\bcommit\b[^;&|\n]*(?:--all\b|-[A-Za-z]*a)")


def git(root, *args):
    try:
        done = subprocess.run(
            ["git", "-C", root, *args], capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if done.returncode != 0:
        return []
    return [line for line in done.stdout.splitlines() if line.strip()]


def decide(decision, reason):
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    if payload.get("tool_name") != "Bash":
        return
    command = (payload.get("tool_input") or {}).get("command") or ""
    if not COMMIT.search(command):
        return

    root = git(payload.get("cwd") or os.getcwd(), "rev-parse", "--show-toplevel")
    if not root:
        return
    root = root[0]

    staged = git(root, "diff", "--cached", "--name-only")
    if COMMIT_ALL.search(command):  # `commit -a` / `-am` sweeps tracked modifications in as well
        staged += git(root, "diff", "--name-only")
    if not staged:
        return

    deny, ask = [], []
    for path in dict.fromkeys(staged):
        if not path.lower().endswith(DATA_EXT):
            continue
        if path.startswith(".scratch/") or "/.scratch/" in path:
            continue
        if path.endswith(".example-return.parquet"):
            continue
        if any(d in path for d in FIXTURE_DIRS) or PACKAGED.search(path):
            ask.append(path)
        else:
            deny.append(path)

    if deny:
        decide(
            "deny",
            "ecoscope-guards: staged data file(s) outside the fixture locations — "
            + ", ".join(deny)
            + ".\nReal patrol data (GPS tracks, ranger names, patrol-information details) must "
            "never be committed; several workflow repos are public, and the remediation is a "
            "history rewrite plus a GitHub support request. Local pulls of real data belong under "
            "gitignored .scratch/. If this file is synthetic, put it under dev/fixtures/ or "
            "resources/mock-data/ beside its build_*_fixture.py generator — or run the commit "
            "yourself. Uninstall the ecoscope-guards plugin to remove this guard.",
        )

    if ask:
        tracked = git(root, "ls-files")
        if not any(GENERATOR.search(p) for p in tracked + staged):
            decide(
                "ask",
                "ecoscope-guards: staged fixture or packaged data — "
                + ", ".join(ask)
                + " — but this repo commits no build_*_fixture.py generator, so nothing shows the "
                "data is synthetic. Committed fixtures are meant to be reproducible from a "
                "committed generator. Confirm the data carries no real patrol tracks, ranger "
                "names or patrol-information details before allowing this commit.",
            )


if __name__ == "__main__":
    main()
