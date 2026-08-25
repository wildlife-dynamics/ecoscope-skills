#!/usr/bin/env bash
# preflight.sh — discover and REPORT the local ecoscope-workflow tooling. Never repairs anything;
# every FAIL/WARN line names the repair, built from what was discovered on this machine.
#
# Usage: preflight.sh [<workflow-repo-dir>]     (default: current directory)
# Exit:  0 = no FAIL lines; 1 = at least one FAIL. WARN never fails.
#
# Checks: wt-compiler runs + can import jsonschema; global vs pinned compiler version; graphviz
# plugin cache (global and outer env); yq is go-yq; pixi; outer/inner manifests and whether their
# installed entry points still launch (renamed-dir breakage); repo signals the develop skill needs.

set -u
target="${1:-.}"
fails=0; warns=0
ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warns=$((warns+1)); }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails+1)); }
info() { printf '      %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- global tools
echo "== tools =="

# wt-compiler: locate, find its interpreter, version, jsonschema, editable source
global_ver=""
if have wt-compiler; then
  wt_bin="$(command -v wt-compiler)"
  if wt-compiler compile --help >/dev/null 2>&1; then
    ok "wt-compiler runs ($wt_bin)"
  else
    fail "wt-compiler is on PATH but 'wt-compiler compile --help' fails — run it bare and read the error"
  fi
  # Interpreter: a uv tool / venv script carries a python shebang; a pixi global trampoline does not.
  wt_py="$(sed -n '1s/^#![[:space:]]*//p' "$wt_bin" 2>/dev/null)"
  case "$wt_py" in *python*) ;; *) wt_py="" ;; esac
  if [ -z "$wt_py" ]; then
    for cand in "${PIXI_HOME:-$HOME/.pixi}/envs/wt-compiler/bin/python" "$(dirname "$wt_bin")/python"; do
      [ -x "$cand" ] && { wt_py="$cand"; break; }
    done
  fi
  if [ -n "$wt_py" ] && [ -x "$wt_py" ]; then
    global_ver="$("$wt_py" -c 'import importlib.metadata as m; print(m.version("wt-compiler"))' 2>/dev/null)"
    src="$("$wt_py" -c 'import wt_compiler, os; print(os.path.dirname(wt_compiler.__file__))' 2>/dev/null)"
    py_prefix="$("$wt_py" -c 'import sys; print(sys.prefix)' 2>/dev/null)"
    editable_root=""
    case "$src" in
      "$py_prefix"/*) install_kind="released (site-packages)" ;;
      *) install_kind="editable"; editable_root="$src"
         while [ "$editable_root" != "/" ] && [ ! -f "$editable_root/pyproject.toml" ]; do editable_root="$(dirname "$editable_root")"; done ;;
    esac
    ok "wt-compiler global version ${global_ver:-unknown}, $install_kind${editable_root:+ from $editable_root}"
    if "$wt_py" -c 'import jsonschema' >/dev/null 2>&1; then
      ok "wt-compiler env imports jsonschema"
    else
      if [ -n "$editable_root" ]; then
        fail "wt-compiler env lacks jsonschema (compile dies with ModuleNotFoundError) — repair: uv tool install --editable $editable_root --with jsonschema --reinstall"
      elif have uv && uv tool list 2>/dev/null | grep -q '^wt-compiler '; then
        fail "wt-compiler env lacks jsonschema — repair: uv tool install wt-compiler --with jsonschema --reinstall"
      else
        fail "wt-compiler env lacks jsonschema — reinstall the compiler with jsonschema in its env (interpreter: $wt_py)"
      fi
    fi
  else
    warn "could not locate wt-compiler's interpreter; skipping jsonschema/version checks (binary: $wt_bin)"
  fi
else
  fail "wt-compiler not on PATH — install: pixi global install -c https://prefix.dev/ecoscope-workflows -c conda-forge wt-compiler --run-post-link-scripts"
fi

# graphviz: present, and the plugin cache registered (the failure only shows at -Tpng time)
if have dot; then
  if printf 'digraph{a}' | dot -Tpng -o /dev/null 2>/dev/null; then
    ok "graphviz dot renders png ($(command -v dot))"
  else
    fail "graphviz dot cannot render png (plugin cache unregistered) — repair: $(command -v dot) -c"
  fi
else
  fail "graphviz 'dot' not on PATH — dev compiles need it for graph.png"
fi

# yq: must be go-yq (mikefarah); the Python yq has incompatible syntax and breaks run-test-cases.sh
if have yq; then
  yv="$(yq --version 2>&1)"
  case "$yv" in
    *mikefarah*) ok "yq is go-yq ($yv)" ;;
    *) fail "yq is not go-yq ('$yv') — dev/run-test-cases.sh needs mikefarah yq; install go-yq and put it first on PATH" ;;
  esac
else
  fail "yq not on PATH — install go-yq (mikefarah)"
fi

if have pixi; then ok "pixi $(pixi --version 2>/dev/null | awk '{print $2}')"; else fail "pixi not on PATH"; fi
have uv && ok "uv $(uv --version 2>/dev/null | awk '{print $2}')"

# optional task-library checkouts advertised to search-tasks.py
if [ -n "${ECOSCOPE_TASK_LIBS:-}" ]; then
  IFS=: read -r -a libs <<<"$ECOSCOPE_TASK_LIBS"
  for d in "${libs[@]}"; do
    [ -d "$d" ] && ok "ECOSCOPE_TASK_LIBS entry exists: $d" || warn "ECOSCOPE_TASK_LIBS entry missing: $d"
  done
else
  info "ECOSCOPE_TASK_LIBS unset — search-tasks.py needs --lib <dir> per task library"
fi

# ---------------------------------------------------------------- workflow repo
echo "== repo: $target =="
if [ ! -f "$target/spec.yaml" ]; then
  info "no spec.yaml here — greenfield or not a workflow repo; repo checks skipped"
  echo "== summary: $fails FAIL, $warns WARN =="
  [ "$fails" -eq 0 ]; exit
fi
cd "$target" || exit 1

if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  br="$(git branch --show-current)"
  info "branch: ${br:-<detached HEAD>}   dirty files: $(git status --short | wc -l | tr -d ' ')"
  grep -q '^\.scratch' .gitignore 2>/dev/null && ok ".scratch is gitignored" || warn ".scratch is NOT in .gitignore — add it before writing plans or pulling data there"
fi

# outer manifest: compile env + pin
if [ -f pixi.toml ]; then
  pin="$(sed -n 's/^wt-compiler[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' pixi.toml | head -1)"
  published="$(sed -n 's/^published[[:space:]]*=[[:space:]]*//p' pixi.toml | head -1)"
  ok "outer pixi.toml: wt-compiler pin '${pin:-<none>}'  [tool.wt] published=${published:-<unset>}"
  if [ -n "$pin" ] && [ -n "$global_ver" ]; then
    case "$pin" in
      *"$global_ver"*) ok "pinned compiler matches global ($global_ver)" ;;
      *) warn "pinned compiler ($pin) differs from global ($global_ver) — publish compiles must run through the outer pixi env, dev compiles are fine" ;;
    esac
  fi
  if [ -d .pixi/envs/default ]; then
    if pixi run --manifest-path pixi.toml --frozen wt-compiler compile --help >/dev/null 2>&1; then
      ok "outer env installed; pinned wt-compiler launches"
    else
      fail "outer env exists but 'pixi run --frozen wt-compiler' fails (renamed repo dir?) — repair: pixi clean --manifest-path pixi.toml && pixi install --manifest-path pixi.toml"
    fi
    if printf 'digraph{a}' | pixi run --manifest-path pixi.toml --frozen dot -Tpng -o /dev/null >/dev/null 2>&1; then
      ok "outer env graphviz renders png"
    else
      fail "outer env graphviz cannot render png — repair: pixi run --manifest-path pixi.toml dot -c   (re-run after every outer re-solve)"
    fi
  else
    info "outer env not installed (.pixi/envs/default absent) — publish compiles need: pixi install --manifest-path pixi.toml && pixi run --manifest-path pixi.toml dot -c"
  fi
else
  warn "no outer pixi.toml — legacy catalog layout, or scaffold incomplete"
fi

# CI recompile: the authority for this repo's flags
ci_src=""
[ -f .github/workflows/_recompile.yml ] && ci_src=".github/workflows/_recompile.yml"
[ -f dev/recompile.sh ] && ci_src="$ci_src${ci_src:+ + }dev/recompile.sh"
if [ -n "$ci_src" ]; then
  if cat .github/workflows/_recompile.yml dev/recompile.sh 2>/dev/null | grep -q -- '--variant=gcp'; then variant="passes --variant=gcp"; else variant="no --variant"; fi
  if grep -q 'pixi update' .github/workflows/_recompile.yml dev/recompile.sh 2>/dev/null; then upd="re-solves the outer lock (pixi update)"; else upd="no pixi update"; fi
  ok "CI recompile ($ci_src): $variant; $upd — read it before choosing compile flags"
else
  warn "no _recompile.yml / dev/recompile.sh — no CI recompile gate (legacy catalog family?) — see reference/ci.md"
fi

# spec requirement modes
if grep -Eq '^[[:space:]]*-?[[:space:]]*(path|editable):' spec.yaml; then warn "spec.yaml has path:/editable: requirements — dev mode; revert to released pins before publish, run dev/postcompile-editable.sh after each compile"; fi
if grep -Eq '^[[:space:]]*(- )?git:' spec.yaml; then info "spec.yaml has git: requirements — use --frozen, not --locked, for inner-env commands"; fi

# inner package: state signals
wfs=( *-workflow/ )
if [ ! -d "${wfs[0]}" ]; then
  info "no *-workflow/ package — spec authored but never compiled (first compile: --clobber --install)"
elif [ "${#wfs[@]}" -ne 1 ]; then
  fail "expected exactly one *-workflow/ dir, found ${#wfs[@]}: ${wfs[*]}"
else
  WF="${wfs[0]%/}"
  ver="$(tr -d '{} \n' <"$WF/VERSION.yaml" 2>/dev/null)"
  [ -f "$WF/pixi.lock" ] && lock="lock present" || lock="NO inner pixi.lock"
  grep -q 'wt-task-gcp' "$WF/pixi.toml" 2>/dev/null && gcp="gcp variant" || gcp="plain variant"
  if have git && git ls-files --error-unmatch "$WF/pixi.lock" >/dev/null 2>&1; then lock_git="committed"; else lock_git="not in git"; fi
  info "inner: $WF  VERSION=${ver:-?}  $lock ($lock_git)  $gcp"
  if [ -f "$WF/pixi.lock" ] && [ "$lock_git" = committed ] && [ "$gcp" = "gcp variant" ] && [ -n "$ver" ] && [ "$ver" != "MAJ:0,MIN:0,PATCH:0" ]; then
    ok "state: PUBLISH — never dev-compile this tree; only the CI recompile above, verbatim"
  elif [ "$ver" = "MAJ:0,MIN:0,PATCH:0" ] || [ ! -f "$WF/pixi.lock" ]; then
    ok "state: DEV (last compile was a dev compile) — dev compile with the global wt-compiler"
  else
    ok "state: compiled, not publish-signature — treat as DEV; confirm against reference/repo-layout.md signals"
  fi
  if [ -d "$WF/.pixi/envs/default" ]; then
    pkg="$(printf '%s' "$WF" | tr '-' '_')"
    if (cd "$WF" && pixi run --manifest-path pixi.toml --frozen -e default python -c "import $pkg") >/dev/null 2>&1; then
      ok "inner env installed; python launches and imports $pkg"
    else
      fail "inner env exists but 'pixi run --frozen -e default python' fails (renamed repo dir?) — repair: pixi clean --manifest-path $WF/pixi.toml && pixi install --manifest-path $WF/pixi.toml"
    fi
  else
    info "inner env not installed — dev/run-test-cases.sh will install it from the lock on first run"
  fi
fi
[ -f test-cases.yaml ] || warn "no test-cases.yaml — CI validate-spec requires at least one case"
[ -x dev/run-test-cases.sh ] || warn "dev/run-test-cases.sh missing or not executable — vendor it from the ecoscope-hub template"

echo "== summary: $fails FAIL, $warns WARN =="
[ "$fails" -eq 0 ]
