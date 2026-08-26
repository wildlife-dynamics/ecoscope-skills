#!/usr/bin/env bash
# preflight.sh — discover and REPORT the global ecoscope-workflow tooling. Never repairs anything;
# every FAIL line names the repair, built from what was discovered on this machine.
#
# Usage: preflight.sh          Exit: 0 = no FAIL; 1 = at least one FAIL.
#
# Checks: wt-compiler runs and its env imports jsonschema (the classic uv-tool gap); graphviz dot
# actually renders png (plugin cache registered); yq is go-yq (mikefarah); pixi is present.
# Repo-level facts (the CI recompile command, pins, envs) are read from the repo by the skills.

set -u
fails=0
ok()   { printf 'OK    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails+1)); }
warn() { printf 'WARN  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- wt-compiler: runs, interpreter, version, jsonschema
if have wt-compiler; then
  wt_bin="$(command -v wt-compiler)"
  if wt-compiler compile --help >/dev/null 2>&1; then
    ok "wt-compiler runs ($wt_bin)"
  else
    fail "wt-compiler is on PATH but 'wt-compiler compile --help' fails — run it bare and read the error"
  fi
  # A uv-tool / venv launcher carries a python shebang; a pixi-global trampoline does not.
  wt_py="$(sed -n '1s/^#![[:space:]]*//p' "$wt_bin" 2>/dev/null)"
  case "$wt_py" in *python*) ;; *) wt_py="" ;; esac
  if [ -z "$wt_py" ]; then
    for cand in "${PIXI_HOME:-$HOME/.pixi}/envs/wt-compiler/bin/python" "$(dirname "$wt_bin")/python"; do
      [ -x "$cand" ] && { wt_py="$cand"; break; }
    done
  fi
  if [ -n "$wt_py" ] && [ -x "$wt_py" ]; then
    ver="$("$wt_py" -c 'import importlib.metadata as m; print(m.version("wt-compiler"))' 2>/dev/null)"
    src="$("$wt_py" -c 'import wt_compiler, os; print(os.path.dirname(wt_compiler.__file__))' 2>/dev/null)"
    prefix="$("$wt_py" -c 'import sys; print(sys.prefix)' 2>/dev/null)"
    editable_root=""
    case "$src" in
      "$prefix"/*) kind="released install" ;;
      *) kind="editable install"; editable_root="$src"
         while [ "$editable_root" != "/" ] && [ ! -f "$editable_root/pyproject.toml" ]; do editable_root="$(dirname "$editable_root")"; done ;;
    esac
    ok "wt-compiler ${ver:-unknown}, $kind${editable_root:+ from $editable_root} (a repo may pin a different version — publish compiles use the repo's outer pixi env)"
    if "$wt_py" -c 'import jsonschema' >/dev/null 2>&1; then
      ok "wt-compiler env imports jsonschema"
    elif [ -n "$editable_root" ]; then
      fail "wt-compiler env lacks jsonschema (compile dies with ModuleNotFoundError) — repair: uv tool install --editable $editable_root --with jsonschema --reinstall"
    elif have uv && uv tool list 2>/dev/null | grep -q '^wt-compiler '; then
      fail "wt-compiler env lacks jsonschema — repair: uv tool install wt-compiler --with jsonschema --reinstall"
    else
      fail "wt-compiler env lacks jsonschema — reinstall the compiler with jsonschema in its env (interpreter: $wt_py)"
    fi
  else
    warn "could not locate wt-compiler's interpreter; jsonschema/version not checked (binary: $wt_bin)"
  fi
else
  fail "wt-compiler not on PATH — install: pixi global install -c https://prefix.dev/ecoscope-workflows -c conda-forge wt-compiler --run-post-link-scripts"
fi

# ---- graphviz: the plugin-cache failure only shows at -Tpng time
if have dot; then
  if printf 'digraph{a}' | dot -Tpng -o /dev/null 2>/dev/null; then
    ok "graphviz dot renders png ($(command -v dot))"
  else
    fail "graphviz dot cannot render png (plugin cache unregistered) — repair: $(command -v dot) -c"
  fi
else
  fail "graphviz 'dot' not on PATH — compiles need it for graph.png"
fi

# ---- yq: must be go-yq; the Python yq has incompatible syntax and breaks dev/run-test-cases.sh
if have yq; then
  yv="$(yq --version 2>&1)"
  case "$yv" in
    *mikefarah*) ok "yq is go-yq ($yv)" ;;
    *) fail "yq is not go-yq ('$yv') — install mikefarah yq (go-yq) and put it first on PATH" ;;
  esac
else
  fail "yq not on PATH — install go-yq (mikefarah)"
fi

if have pixi; then ok "pixi $(pixi --version 2>/dev/null | awk '{print $2}')"; else fail "pixi not on PATH — https://pixi.sh"; fi

echo "== $fails FAIL =="
[ "$fails" -eq 0 ]
