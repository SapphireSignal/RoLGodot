"""Lists classes the original exposes to scripts (ScriptManager.ExposeClass) that nothing uses.

A class counts as used when its name appears in any script (Scripts/**/*.dws|ets|sps) or in any .pas file outside the
lines that declare, implement or expose it (incl. its own fluent setters returning it; string literals and //
comments are ignored). Output: one line per unused class with its unit and declaration line.
Usage: python tools/find_unused_classes.py  (needs reference/, see tools/fetch_reference.ps1)
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "reference", "rise-of-legions")


def read(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8", "replace")


def main():
    if not os.path.isdir(ROOT):
        print("reference/ missing: run tools/fetch_reference.ps1")
        return 1
    pas, scripts = {}, []
    for d, _, files in os.walk(ROOT):
        for n in files:
            low = n.lower()
            p = os.path.join(d, n)
            if low.endswith(".pas"):
                pas[p] = read(p)
            elif low.endswith((".dws", ".ets", ".sps")):
                scripts.append(read(p))
    script_text = "\n".join(scripts)

    exposed = {}
    for p, text in pas.items():
        for m in re.finditer(r"ExposeClass\(\s*(\w+)\s*\)", text):
            exposed.setdefault(m.group(1), p)

    for name in sorted(exposed):
        word = re.compile(r"\b" + re.escape(name) + r"\b", re.I)  # Delphi and DWScript ignore case
        if word.search(script_text):
            continue
        own = re.compile(r"^\s*(" + re.escape(name) + r"\s*=\s*class|\{\s*" + re.escape(name) + r"\s*\}|"
                         r"(constructor|destructor|function|procedure|class\s+function|class\s+procedure)\s+"
                         + re.escape(name) + r"\.|.*ExposeClass\(\s*" + re.escape(name) + r"\s*\)|"
                         # fluent setters in the class body return the class itself: `function Foo(...) : Name;`
                         r"function\s+\w+\s*(\(.*\))?\s*:\s*" + re.escape(name) + r"\s*;)", re.I)
        used = False
        decl = ""
        for p, text in pas.items():
            for i, line in enumerate(text.splitlines(), 1):
                line = re.sub(r"//.*", "", re.sub(r"'[^']*'", "''", line))  # names in strings / comments don't count
                if not word.search(line):
                    continue
                if own.search(line):
                    if not decl and re.search(re.escape(name) + r"\s*=\s*class", line, re.I):
                        decl = "%s:%d" % (os.path.relpath(p, ROOT), i)
                    continue
                used = True
                break
            if used:
                break
        if not used:
            print("%s  %s" % (name, decl or os.path.relpath(exposed[name], ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
