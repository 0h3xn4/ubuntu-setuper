#!/usr/bin/env bash
# manifest-diff.sh — compare two workstation manifests (from './setup.sh --manifest'
# or from Part F of the manual guide), e.g. a work laptop and a fresh VM.
#
#   tools/manifest-diff.sh MANIFEST_A MANIFEST_B
#
# Machine-specific lines (host, user, CPU, kernel, script/config hashes, dates)
# are ignored. APT packages are compared by name and version; every other
# section by its lines. Exit status: 0 = identical, 1 = differences, 2 = usage.
set -euo pipefail

[[ $# -eq 2 && -r $1 && -r $2 ]] || { sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }

python3 -I - "$1" "$2" <<'PY'
import re, sys

VOLATILE = re.compile(r"^(# Generated|Host:|User:|CPU:|Kernel:|Script:|Git:|Config:|Lock:|Profile:)")

def load(path):
    sections, name = {}, "(header)"
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        if line.startswith("## "):
            name = line[3:]
            continue
        if not line.strip() or VOLATILE.match(line):
            continue
        sections.setdefault(name, []).append(line)
    return sections

a, b = load(sys.argv[1]), load(sys.argv[2])
differences = 0
for name in sorted(set(a) | set(b)):
    la, lb = a.get(name, []), b.get(name, [])
    if name.startswith("APT packages"):
        pa = {l.split("\t")[0]: l.split("\t")[1] for l in la if "\t" in l}
        pb = {l.split("\t")[0]: l.split("\t")[1] for l in lb if "\t" in l}
        only_a = sorted(set(pa) - set(pb))
        only_b = sorted(set(pb) - set(pa))
        changed = sorted(p for p in set(pa) & set(pb) if pa[p] != pb[p])
        if only_a or only_b or changed:
            differences += 1
            print(f"== {name}: {len(only_a)} only in A, {len(only_b)} only in B, {len(changed)} different versions")
            for p in only_a[:40]: print(f"  - {p} {pa[p]}")
            for p in only_b[:40]: print(f"  + {p} {pb[p]}")
            for p in changed[:40]: print(f"  ~ {p}: {pa[p]} -> {pb[p]}")
            rest = max(0, len(only_a) - 40) + max(0, len(only_b) - 40) + max(0, len(changed) - 40)
            if rest: print(f"  ... and {rest} more")
        continue
    sa, sb = set(la), set(lb)
    if sa != sb:
        differences += 1
        print(f"== {name}")
        for l in la:
            if l not in sb: print(f"  - {l}")
        for l in lb:
            if l not in sa: print(f"  + {l}")
if differences:
    print(f"\n{differences} section(s) differ.  '-' only in {sys.argv[1]}   '+' only in {sys.argv[2]}")
    sys.exit(1)
print("The manifests are identical (ignoring host, user, CPU, kernel, hashes and dates).")
PY
