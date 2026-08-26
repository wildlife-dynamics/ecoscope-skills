#!/usr/bin/env python3
"""Inventory the compiled config form the way a Desktop user sees it, and check a README against it.

  form-inventory.py <rjsf.json>                         cards -> fields: title, default, options, flags,
                                                        and the row types of union arrays with their fields
  form-inventory.py <rjsf.json> --result <result.json>  ...plus the widgets of that run (views, titles)
  form-inventory.py <rjsf.json> [--result ...] --check README.md
                                                        report every visible card / field / widget title
                                                        the README never names as a bold label or heading
                                                        (exit 1 if any), plus advisory REVIEW lines for
                                                        row types and their fields not mentioned verbatim

Titles come from the compiled schema after rjsf-overrides — never from spec.yaml task names.
"""
import argparse
import json
import re
import sys


def load(path):
    with open(path) as f:
        return json.load(f)


class Inventory:
    def __init__(self, rjsf):
        self.defs = rjsf.get("$defs", {})
        self.ui = rjsf.get("uiSchema", {})
        self.props = rjsf["properties"]
        self.order = self.ui.get("ui:order") or list(self.props.keys())
        self.rows = []  # dicts: card, path, title, kind, default, options, advanced, hidden, when, required

    def deref(self, s):
        seen = 0
        while isinstance(s, dict) and "$ref" in s and seen < 10:
            s = self.defs[s["$ref"].rsplit("/", 1)[-1]]
            seen += 1
        return s

    def branch_titles(self, branches):
        return [self.deref(b).get("title") or "?" for b in branches]

    def options(self, s):
        s = self.deref(s)
        if "oneOf" in s and all("const" in o for o in s["oneOf"]):
            return [str(o.get("title", o["const"])) for o in s["oneOf"]]
        if "enum" in s:
            return [str(v) for v in s["enum"]]
        if "anyOf" in s or ("oneOf" in s and "properties" not in s):
            return ["one of: " + ", ".join(self.branch_titles(s.get("anyOf") or s["oneOf"]))]
        items = s.get("items")
        if isinstance(items, dict):
            it = self.deref(items)
            if "anyOf" in it or "oneOf" in it:
                return ["row types: " + ", ".join(self.branch_titles(it.get("anyOf") or it["oneOf"]))]
            return self.options(it)
        return []

    def walk(self, card, schema, ui, path, when=""):
        schema = self.deref(schema)
        required = set(schema.get("required", []))
        for name, sub in schema.get("properties", {}).items():
            sub = self.deref(sub)
            usub = ui.get(name, {}) if isinstance(ui, dict) else {}
            kind = sub.get("type") or ("object" if "properties" in sub else "choice")
            if sub.get("uniqueItems"):
                kind = "multi-select"
            self.rows.append({
                "card": card,
                "path": path + [name],
                "title": str(sub.get("title", name)),
                "kind": kind,
                "default": sub.get("default"),
                "options": self.options(sub),
                "advanced": bool(sub.get("ecoscope:advanced")),
                "hidden": usub.get("ui:widget") == "hidden",
                "when": when,
                "required": name in required and "default" not in sub,
                "description": (sub.get("description") or "").strip(),
            })
            if "properties" in sub:
                self.walk(card, sub, usub, path + [name], when)
            # row types of an array of unions: their own fields are what the user fills per row
            items = self.deref(sub.get("items")) if isinstance(sub.get("items"), dict) else None
            if items and ("anyOf" in items or "oneOf" in items):
                discriminator = (items.get("discriminator") or {}).get("propertyName")
                for branch in items.get("anyOf") or items["oneOf"]:
                    b = self.deref(branch)
                    if "properties" not in b:
                        continue
                    self.rows.append({"card": card, "path": path + [name, b.get("title") or "?"],
                                      "path_titles": [str(sub.get("title") or name).strip() or name, str(b.get("title") or "?")],
                                      "title": str(b.get("title") or "?"), "kind": "row type",
                                      "default": None, "options": [], "advanced": False,
                                      "hidden": False, "when": when, "required": False,
                                      "description": (b.get("description") or "").strip(), "sub": True})
                    for fname, fs in b.get("properties", {}).items():
                        fs = self.deref(fs)
                        if fname == discriminator:
                            continue
                        self.rows.append({"card": card, "path": path + [name, b.get("title") or "?", fname],
                                          "path_titles": [str(sub.get("title") or name).strip() or name, str(b.get("title") or "?"), str(fs.get("title", fname))],
                                          "title": str(fs.get("title", fname)), "kind": fs.get("type", "choice"),
                                          "default": fs.get("default"), "options": self.options(fs),
                                          "advanced": False, "hidden": False, "when": when,
                                          "required": fname in set(b.get("required", [])) and "default" not in fs,
                                          "description": (fs.get("description") or "").strip(), "sub": True})
            for cond in sub.get("allOf", []):
                if_props = cond.get("if", {}).get("properties", {})
                then = cond.get("then", {})
                if not if_props or "properties" not in then:
                    continue
                key, val = next(iter(if_props.items()))
                cond_txt = f"when {key} = {val['const']}" if isinstance(val, dict) and "const" in val else f"when {key} …"
                self.walk(card, then, usub, path + [name], cond_txt)

    def build(self):
        for key in self.order:
            cs = self.props[key]
            title = cs.get("title") or key
            self.walk(title, cs, self.ui.get(key, {}), [key])
        return self

    def card_titles(self):
        return [(self.props[k].get("title") or k) for k in self.order]

    def print(self, out=sys.stdout):
        current = None
        for r in self.rows:
            if r["card"] != current:
                current = r["card"]
                print(f"\n## card: {current}", file=out)
            flags = " ".join(f for f, on in (("ADVANCED", r["advanced"]), ("HIDDEN", r["hidden"]),
                                             ("required", r["required"])) if on)
            dflt = "" if r["default"] is None else f" default={json.dumps(r['default'])}"
            opts = f" options={r['options']}" if r["options"] else ""
            when = f" ({r['when']})" if r["when"] else ""
            indent = "  " * (len(r["path"]) - 1)
            print(f"{indent}- {r['title']!r}{when} [{r['kind']}]{dflt}{opts} {flags}  ({'.'.join(r['path'][1:])})", file=out)


def widgets(result):
    views = result.get("result", {}).get("views", {})
    seen = []
    for key, ws in views.items():
        for w in ws:
            t = (w.get("widget_type"), w.get("title"))
            if t not in seen:
                seen.append(t)
    return views, seen


def check(inv, readme_text, widget_titles):
    """Fleet READMEs name every field as a bold label (**Title**) and every card / widget as a
    heading; a title that only occurs in running prose is reported separately, because
    "patrol statuses" mentioning **Patrol Status** is not documentation of the field."""
    text = readme_text.lower()

    def as_label(t):
        t = t.lower()
        return f"**{t}**" in text or re.search(r"^#{1,6} .*" + re.escape(t), text, re.M) is not None

    missing, prose_only, review = [], [], []
    for t in inv.card_titles():
        if not t.strip():
            continue
        if as_label(t):
            continue
        (prose_only if t.lower() in text else missing).append(("card", t))
    for r in inv.rows:
        t = r["title"].strip()
        if not t or r["hidden"] or r["kind"] == "object":
            continue
        if r.get("sub"):
            # a row type or one of its fields: prose usually compresses these ("per Distance /
            # per Duration"), so an absent mention is advisory, not a gate failure
            if t.lower() not in text:
                review.append(("row field", f"{r['card']} > {' > '.join(r['path_titles'])}"))
            continue
        if as_label(t):
            continue
        (prose_only if t.lower() in text else missing).append(("field", f"{r['card']} > {t}"))
    for kind, t in widget_titles:
        if not t or as_label(t):
            continue
        (prose_only if t.lower() in text else missing).append((f"widget:{kind}", t))
    return missing, prose_only, review


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rjsf")
    ap.add_argument("--result", help="a run's result.json, to inventory its widgets")
    ap.add_argument("--check", help="README.md to check for every visible title")
    a = ap.parse_args()

    inv = Inventory(load(a.rjsf)).build()
    inv.print()

    widget_titles = []
    if a.result:
        views, widget_titles = widgets(load(a.result))
        print(f"\n## widgets ({len(views)} view(s): {list(views.keys())[:5]}{' …' if len(views) > 5 else ''})")
        if not widget_titles:
            print("- NONE — result.views is empty: the silently-empty run, not a workflow without a dashboard")
        for kind, title in widget_titles:
            print(f"- {title!r} [{kind}]")

    if a.check:
        with open(a.check) as f:
            readme = f.read()
        missing, prose_only, review = check(inv, readme, widget_titles)
        print(f"\n## check against {a.check}")
        for kind, t in missing:
            print(f"- MISSING {kind}: {t}")
        for kind, t in prose_only:
            print(f"- NOT A LABEL {kind}: {t}  (mentioned in prose only — the field is documented under another name, or not at all)")
        for kind, t in review:
            print(f"- REVIEW {kind}: {t}  (advisory — a row type or its field is not mentioned verbatim; confirm the prose covers it)")
        if not missing and not prose_only:
            print("- every visible card, field and widget title appears as a bold label or heading")
            return 0
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
