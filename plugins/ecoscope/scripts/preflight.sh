#!/usr/bin/env bash
# preflight.sh — discover and REPORT the global ecoscope-workflow tooling. Never repairs anything;
# every FAIL line names the repair, built from what was discovered on this machine.
#
# Usage: preflight.sh [<workflow-repo-dir>]   Exit: 0 = no FAIL; 1 = at least one FAIL.
#
# Checks: wt-compiler runs and its env imports jsonschema (the classic uv-tool gap); graphviz dot
# actually renders png (plugin cache registered); yq is go-yq (mikefarah); pixi is present.
# When run inside a workflow repo it also compares the compiler pin (pixi.toml) and CI's pixi pin
# (setup-pixi pixi-version in .github/workflows) against the global tools, and lists the
# task-library pins from spec.yaml. CI recompile flags and env health are read from the repo by
# the skill that needs them.

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

pixi_ver=""
if have pixi; then pixi_ver="$(pixi --version 2>/dev/null | awk '{print $2}')"; ok "pixi ${pixi_ver:-unknown}"; else fail "pixi not on PATH — https://pixi.sh"; fi

# ---- versions this repo asks for (only when run inside a workflow repo; a new workflow has none)
repo="${1:-.}"
if [ -f "$repo/spec.yaml" ]; then
  echo "== repo pins ($repo) =="
  pin="$(sed -n 's/^wt-compiler[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$repo/pixi.toml" 2>/dev/null | head -1)"
  if [ -n "$pin" ]; then
    case "$pin" in
      *"${ver:-__none__}"*) ok "wt-compiler: pinned $pin in pixi.toml, global ${ver:-unknown} — match" ;;
      *) warn "wt-compiler: pinned $pin in pixi.toml, global ${ver:-unknown} — differ; dev compiles use the global one, publish compiles must run through the outer pixi env (pinned)" ;;
    esac
  else
    warn "no wt-compiler pin found in $repo/pixi.toml"
  fi
  # CI's pixi (setup-pixi pixi-version) must be able to read the inner lock. A newer local pixi
  # writes a lock format the pinned one rejects ("lock file not up-to-date with the workspace"),
  # and a --update compile re-solves the inner lock with the PATH pixi even through the outer env.
  ci_pixi=""
  for wf in "$repo/.github/workflows/_recompile.yml" "$repo/.github/workflows/test.yml"; do
    ci_pixi="$(sed -n 's/^[[:space:]]*pixi-version:[[:space:]]*v\{0,1\}\([0-9][0-9.]*\).*/\1/p' "$wf" 2>/dev/null | head -1)"
    [ -n "$ci_pixi" ] && break
  done
  if [ -n "$ci_pixi" ] && [ -n "$pixi_ver" ]; then
    if [ "$ci_pixi" = "$pixi_ver" ]; then
      ok "pixi: CI pins v$ci_pixi (.github/workflows), local $pixi_ver — match"
    else
      warn "pixi: CI pins v$ci_pixi (.github/workflows), local $pixi_ver — differ; after any --update compile re-solve the inner lock with CI's pixi (download the v$ci_pixi release binary, then '<bin> lock --manifest-path <WF>/pixi.toml' and '<bin> install --locked --manifest-path <WF>/pixi.toml') or CI fails with 'lock file not up-to-date with the workspace'"
    fi
  elif [ -z "$ci_pixi" ]; then
    warn "no setup-pixi pixi-version pin found in $repo/.github/workflows"
  fi
  if have yq; then
    yq '.requirements[] | "  " + .name + "  " + (.version // .tag // .rev // (.path | select(.) | "path: " + .) // "")' "$repo/spec.yaml" 2>/dev/null \
      | sed 's/^/      /' | sed '1s/^      /task libraries (spec.yaml requirements):\n      /'
  fi
fi

echo "== $fails FAIL =="
[ "$fails" -eq 0 ]
