#!/usr/bin/env bash
# test-hooks.sh — exercise both hooks against a throwaway git repo. No arguments; prints one line
# per case and exits non-zero if any decision differs from the expected one.
#
#   bash plugins/ecoscope-guards/test-hooks.sh

set -u
H="$(cd "$(dirname "$0")/hooks" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
failures=0

cd "$T" || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q .
mkdir -p dev/fixtures resources/mock-data .scratch src/pkg/tasks
echo x > README.md && git add README.md && git commit -qm init

# case <expected: silent|ask|deny> <tool> <command> <label>
case_() {
  local want="$1" tool="$2" cmd="$3" label="$4" got
  got="$(printf '{"tool_name":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$tool" "$T" "$cmd" \
    | bash "$H/hook.sh" sensitive_commit_guard.py \
    | python3 -c 'import json,sys
raw = sys.stdin.read().strip()
print(json.loads(raw)["hookSpecificOutput"]["permissionDecision"] if raw else "silent")')"
  if [ "$got" = "$want" ]; then
    printf 'ok    %-6s %s\n' "$got" "$label"
  else
    printf 'FAIL  %-6s (want %s) %s\n' "$got" "$want" "$label"
    failures=$((failures + 1))
  fi
}

case_ silent Edit 'git commit -m x'   'non-Bash tool'
case_ silent Bash 'git status'        'not a commit'

printf 'p' > patrols.parquet && git add -f patrols.parquet
case_ deny Bash 'git commit -m data'  'real data at repo root'
git reset -q && rm -f patrols.parquet

printf 'p' > dev/fixtures/obs.parquet && printf '#' > dev/fixtures/build_obs_fixture.py
git add -f dev/fixtures >/dev/null && git commit -qm fixtures
printf 'p2' > dev/fixtures/obs2.parquet && git add -f dev/fixtures/obs2.parquet
case_ silent Bash 'git commit -m fixture2' 'fixture, repo has a generator'
git reset -q && rm -f dev/fixtures/obs2.parquet

git rm -q --cached dev/fixtures/build_obs_fixture.py && rm -f dev/fixtures/build_obs_fixture.py
git commit -qm "drop generator"
printf 'p3' > resources/mock-data/mock.geojson && git add -f resources/mock-data/mock.geojson
case_ ask Bash 'git commit -m mockdata' 'mock data, no generator'
git reset -q

printf 'p' > .scratch/real.parquet && git add -f .scratch/real.parquet
case_ silent Bash 'git commit -m scratch' '.scratch data, force-added'
git reset -q

printf 'p' > src/pkg/tasks/t.example-return.parquet
git add -f src/pkg/tasks/t.example-return.parquet
case_ silent Bash 'git commit -m task' 'packaged example-return fixture'
git reset -q

printf 'p' > src/pkg/tasks/all_patrols.parquet && git add -f src/pkg/tasks/all_patrols.parquet
case_ ask Bash 'git commit -m taskdata' 'packaged task data, not example-return'
git reset -q && rm -f src/pkg/tasks/all_patrols.parquet

printf 'p' > tracks.parquet && git add -f tracks.parquet && git commit -qm "tracked data"
printf 'pp' > tracks.parquet
case_ deny Bash 'git commit -am update' 'commit -am over a tracked modified parquet'
case_ silent Bash 'git commit -m \"note -beta\"' 'no -a: an unstaged data file is not swept in'
git checkout -q -- tracks.parquet

echo y > spec.yaml && git add spec.yaml
case_ silent Bash 'git commit -m spec' 'ordinary code commit'
git reset -q

echo '{}' > layout.json && echo '{}' > rjsf.json && git add layout.json rjsf.json
case_ silent Bash 'cd /elsewhere && git commit -m compiled' 'generated json artefacts'
git reset -q

printf 'p' > sneaky.parquet && git add -f sneaky.parquet
case_ silent Bash 'git log --oneline' 'data staged but the command is no commit'
git reset -q && rm -f sneaky.parquet

notice() {  # $1 = file path, $2 = expected: notice|silent
  local got
  got="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" \
    | bash "$H/hook.sh" spec_edited_notice.py)"
  if { [ -n "$got" ] && [ "$2" = notice ]; } || { [ -z "$got" ] && [ "$2" = silent ]; }; then
    printf 'ok    %-6s spec notice on %s\n' "$2" "$1"
  else
    printf 'FAIL  spec notice on %s (want %s)\n' "$1" "$2"
    failures=$((failures + 1))
  fi
}
notice "$T/spec.yaml" notice
notice "$T/README.md" silent

echo
if [ "$failures" -eq 0 ]; then echo "all cases passed"; else echo "$failures case(s) failed"; fi
exit $((failures > 0))
