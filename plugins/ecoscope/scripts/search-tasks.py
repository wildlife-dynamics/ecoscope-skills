#!/usr/bin/env python3
"""
Find tasks in ecoscope task-library source trees — no environment needed.

A pure-AST scan for functions decorated with @register. Reads whatever source you point it at
(a checkout or an installed package), so it is fast and cheap but NOT authoritative: confirm the
name with `wt-registry --function <name>` in the compiled env before it goes into a spec.

Usage:
    search-tasks.py --lib <tasks-dir> [--lib <tasks-dir> ...]              # list all tasks
    search-tasks.py --lib <tasks-dir> <keyword>                             # search names
    search-tasks.py --lib <tasks-dir> -s <task_name>                        # signature + docstring

Roots: each --lib is a directory inside a Python package (e.g. a checkout's
`<pkg>/tasks/` dir, or the installed one from
`python -c 'import ecoscope.platform.tasks as m; print(m.__path__[0])'`).
ECOSCOPE_TASK_LIBS (colon-separated) supplies defaults when --lib is omitted.
"""

import ast
import os
import sys
from dataclasses import dataclass
from pathlib import Path

# Colors — only when writing to a terminal; piped output (agents) stays plain.
_TTY = sys.stdout.isatty()
GREEN, BLUE, YELLOW, CYAN, MAGENTA, NC = (
    ("\033[0;32m", "\033[0;34m", "\033[0;33m", "\033[0;36m", "\033[0;35m", "\033[0m")
    if _TTY
    else ("",) * 6
)
_LIB_COLORS = [GREEN, YELLOW, MAGENTA, BLUE]


@dataclass
class TaskInfo:
    name: str
    module: str  # fully-qualified defining module, e.g. ecoscope.platform.tasks.io._persist
    library: str  # top-level package name
    file_path: Path
    lineno: int
    signature: str
    docstring: str


def module_path(file_path: Path) -> str:
    """Fully-qualified module of a file: walk up while parents are packages."""
    parts = [file_path.stem]
    d = file_path.parent
    while (d / "__init__.py").exists():
        parts.append(d.name)
        d = d.parent
    return ".".join(reversed(parts))


def _is_register(decorator: ast.expr) -> bool:
    target = decorator.func if isinstance(decorator, ast.Call) else decorator
    return isinstance(target, ast.Name) and target.id == "register"


def extract_tasks(file_path: Path) -> list[TaskInfo]:
    try:
        source = file_path.read_text()
        tree = ast.parse(source)
    except (OSError, SyntaxError, UnicodeDecodeError):
        return []

    lines = source.splitlines()
    module = module_path(file_path)
    library = module.split(".")[0]
    tasks = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef) or not any(
            _is_register(d) for d in node.decorator_list
        ):
            continue
        # Signature = from `def` up to the first body statement (the docstring, if any).
        sig_end = node.body[0].lineno - 1 if node.body else node.lineno
        signature = "\n".join(lines[node.lineno - 1 : sig_end]).rstrip()
        tasks.append(
            TaskInfo(
                name=node.name,
                module=module,
                library=library,
                file_path=file_path,
                lineno=node.lineno,
                signature=signature,
                docstring=ast.get_docstring(node) or "",
            )
        )
    return tasks


def get_all_tasks(roots: list[Path]) -> list[TaskInfo]:
    tasks: list[TaskInfo] = []
    for root in roots:
        for py in sorted(root.rglob("*.py")):
            if py.name == "__init__.py" or "__pycache__" in py.parts:
                continue
            tasks.extend(extract_tasks(py))
    return sorted(tasks, key=lambda t: (t.library, t.module, t.name))


def _lib_color(library: str, libraries: list[str]) -> str:
    return _LIB_COLORS[libraries.index(library) % len(_LIB_COLORS)]


def _collisions(tasks: list[TaskInfo]) -> set[str]:
    seen: dict[str, set[str]] = {}
    for t in tasks:
        seen.setdefault(t.name, set()).add(t.library)
    return {name for name, libs in seen.items() if len(libs) > 1}


def list_all(tasks: list[TaskInfo]) -> None:
    if not tasks:
        print("No @register functions found under the given roots.")
        return
    libraries = sorted({t.library for t in tasks})
    collisions = _collisions(tasks)
    cur_lib = cur_mod = None
    for t in tasks:
        color = _lib_color(t.library, libraries)
        if t.library != cur_lib:
            if cur_lib is not None:
                print()
            print(f"{color}━━━ [{t.library}] ━━━{NC}")
            cur_lib, cur_mod = t.library, None
        if t.module != cur_mod:
            print(f"  {CYAN}{t.module}{NC}")
            cur_mod = t.module
        flag = "  (collides across libraries)" if t.name in collisions else ""
        print(f"    {color}{t.name}{NC}{flag}")


def search(keyword: str, tasks: list[TaskInfo]) -> None:
    kw = keyword.lower()
    matches = [t for t in tasks if kw in t.name.lower()]
    if not matches:
        print(f"No tasks matching: {keyword}")
        return
    libraries = sorted({t.library for t in tasks})
    collisions = _collisions(tasks)
    print(f"{BLUE}Tasks matching '{keyword}':{NC}\n")
    cur_lib = None
    for t in matches:
        color = _lib_color(t.library, libraries)
        if t.library != cur_lib:
            if cur_lib is not None:
                print()
            print(f"{color}[{t.library}]{NC}")
            cur_lib = t.library
        flag = "  (collides across libraries — fully qualify in the spec)" if t.name in collisions else ""
        print(f"  {color}{t.name}{NC}{flag}")
        print(f"    └─ {CYAN}{t.module}{NC}")


def show_signature(name: str, tasks: list[TaskInfo]) -> None:
    matches = [t for t in tasks if t.name == name]
    if not matches:
        partial = [t.name for t in tasks if name.lower() in t.name.lower()]
        if partial:
            print(f"Task '{name}' not found. Did you mean:\n")
            for n in dict.fromkeys(partial[:5]):
                print(f"  - {n}")
        else:
            print(f"Task not found: {name}")
        return

    if len(matches) > 1:
        libs = ", ".join(t.library for t in matches)
        print(
            f"{YELLOW}Note:{NC} '{name}' is defined in {len(matches)} libraries ({libs}). "
            "A spec listing both must fully qualify it; the compiler's error lists the modules.\n"
        )
    for i, t in enumerate(matches):
        if i:
            print("\n" + "=" * 60 + "\n")
        print(f"{GREEN}Task:{NC}    {t.name}")
        print(f"{GREEN}Library:{NC} {t.library}")
        print(f"{GREEN}Module:{NC}  {t.module}  (defining module — the spec reference is the bare")
        print(f"         name, or the registry's public_module_path if fully qualified)")
        print(f"{GREEN}File:{NC}    {t.file_path}:{t.lineno}")
        print()
        print(f"{CYAN}Signature:{NC}")
        print("─" * 60)
        print(t.signature)
        print("─" * 60)
        if t.docstring:
            print()
            print(f"{CYAN}Docstring:{NC}")
            print("─" * 60)
            print(t.docstring)
            print("─" * 60)


def parse_args(argv: list[str]) -> tuple[list[Path], list[str]]:
    roots: list[Path] = []
    rest: list[str] = []
    i = 0
    while i < len(argv):
        if argv[i] in ("--lib", "-l"):
            if i + 1 >= len(argv):
                sys.exit("Error: --lib requires a path argument")
            roots.append(Path(argv[i + 1]).expanduser().resolve())
            i += 2
        else:
            rest.append(argv[i])
            i += 1
    if not roots:
        env = os.environ.get("ECOSCOPE_TASK_LIBS", "")
        roots = [Path(p).expanduser().resolve() for p in env.split(":") if p]
    missing = [r for r in roots if not r.is_dir()]
    for r in missing:
        print(f"Warning: not a directory, skipped: {r}", file=sys.stderr)
    roots = [r for r in roots if r.is_dir()]
    return roots, rest


def main() -> None:
    roots, args = parse_args(sys.argv[1:])
    if args and args[0] in ("-h", "--help"):
        print(__doc__)
        return
    if not roots:
        sys.exit(
            "Error: no task-library roots. Pass --lib <tasks-dir> (repeatable) or set "
            "ECOSCOPE_TASK_LIBS=<dir>:<dir>. See --help."
        )
    tasks = get_all_tasks(roots)
    if not args:
        list_all(tasks)
    elif args[0] in ("-s", "--signature"):
        if len(args) < 2:
            sys.exit("Usage: search-tasks.py --lib <dir> -s <task_name>")
        show_signature(args[1], tasks)
    else:
        search(args[0], tasks)


if __name__ == "__main__":
    main()
