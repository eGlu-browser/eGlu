#!/bin/zsh
# Writes LICENSES.md and Sources/Engines/Licenses.txt (the text Settings ›
# Licences shows): every crate compiled into the engines' library, under the
# licence eGlu takes it under, with the copyright notices its licence files
# carry and each licence's full text. Run it after any change to Cargo.lock.
#
# The crates are cargo tree's for the five targets build.sh builds, normal
# dependencies only: build scripts, procedural macros and development
# dependencies run on the build machine and are not in the library, and the
# lock file lists crates for platforms and features never built.

set -euo pipefail
cd "$(dirname "$0")"

TARGETS=(aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)

work=$(mktemp -d)
trap "rm -rf $work" EXIT

for target in $TARGETS; do
    cargo tree --locked -e normal,no-proc-macro --target "$target" \
        --prefix none -p eglu-engines --format '{p}' >> "$work/tree.txt"
done
cargo metadata --locked --format-version 1 \
    $(for target in $TARGETS; do echo --filter-platform $target; done) > "$work/metadata.json"

python3 -I - "$work/tree.txt" "$work/metadata.json" <<'PYEOF'
import json, os, re, sys
from collections import Counter

tree_path, metadata_path = sys.argv[1], sys.argv[2]

# The licence a crate is taken under when it offers a choice: the first of
# these it offers. MIT and Apache-2.0 first, as most crates offer one.
PREFERENCE = ["MIT", "Apache-2.0", "BSD-3-Clause", "BSD-2-Clause", "ISC", "Zlib",
              "0BSD", "Unicode-3.0", "BSL-1.0", "Unlicense", "MPL-2.0"]
NAMES = {
    "MIT": "MIT License",
    "Apache-2.0": "Apache License 2.0",
    "BSD-3-Clause": "BSD 3-Clause License",
    "BSD-2-Clause": "BSD 2-Clause License",
    "ISC": "ISC License",
    "Zlib": "zlib License",
    "0BSD": "BSD Zero Clause License",
    "Unicode-3.0": "Unicode License v3",
    "BSL-1.0": "Boost Software License 1.0",
    "Unlicense": "The Unlicense",
    "MPL-2.0": "Mozilla Public License 2.0",
}

wanted = set()
for line in open(tree_path):
    fields = line.split()
    if len(fields) >= 2 and fields[1].startswith("v"):
        wanted.add((fields[0], fields[1][1:]))
wanted.discard(("eglu-engines", "0.1.0"))

meta = json.load(open(metadata_path))
packages = {(p["name"], p["version"]): p for p in meta["packages"]}
missing = sorted(wanted - packages.keys())
if missing:
    sys.exit(f"cargo metadata does not know {missing}")


def choose(expression):
    """The licences an SPDX expression is taken under: one from each OR, every AND."""
    expression = expression.replace("/", " OR ").strip()
    while expression.startswith("(") and expression.endswith(")"):
        expression = expression[1:-1].strip()
    chosen = []
    for part in re.split(r"\s+AND\s+", expression):
        options = [o.strip(" ()") for o in re.split(r"\s+OR\s+", part.strip(" ()"))]
        ranked = [o for o in PREFERENCE if o in options]
        if not ranked:
            sys.exit(f"no licence to take in {expression!r}: add it to PREFERENCE")
        chosen.append(ranked[0])
    return chosen


def classify(text):
    """The licences a licence file's text is."""
    t = " ".join(text.lower().split())
    found = set()
    if "apache license" in t and "version 2.0" in t and "terms and conditions" in t:
        found.add("Apache-2.0")
    if "mozilla public license" in t and "2.0" in t:
        found.add("MPL-2.0")
    if "unicode" in t and "data files" in t and "permission is hereby granted" in t:
        found.add("Unicode-3.0")
    elif "permission is hereby granted, free of charge" in t:
        found.add("MIT")
    if "boost software license" in t:
        found.add("BSL-1.0")
    if "this is free and unencumbered software" in t:
        found.add("Unlicense")
    if "redistribution and use in source and binary forms" in t:
        found.add("BSD-3-Clause" if ("neither the name" in t or "endorse or promote" in t) else "BSD-2-Clause")
    if "altered source versions must be plainly marked" in t:
        found.add("Zlib")
    if "permission to use, copy, modify, and/or distribute this software for any purpose" in t:
        found.add("ISC" if "provided that the above copyright notice" in t else "0BSD")
    return found


# A copyright notice: "Copyright", "(c)" or "©", then a year or a name.
# Lines of a licence's own text that start the same way ("copyright license
# to reproduce", "(c) You must retain", "COPYRIGHT AND PERMISSION NOTICE",
# the appendix's "Copyright [yyyy] [name of copyright owner]") are not.
NOTICE_START = re.compile(r"^\s*(?:[#*/;]+\s*)?((copyright\b|\(c\)|©)(?:\s*(?:\(c\)|©))*\s*(.*))$", re.I)
PLACEHOLDER = re.compile(r"\[yyyy\]|\{yyyy\}|<year>|\[year\]|<copyright|\[name of|\{name of|copyright notice", re.I)


def notice(line):
    """The notice a line is, or None."""
    match = NOTICE_START.match(line)
    if not match or PLACEHOLDER.search(line) or not re.search(r"[a-z]", line):
        return None
    whole, lead, rest = match.groups()
    if lead.lower() == "copyright":
        if not re.match(r"[0-9\[]|[A-Z]", rest) or re.match(r"licen[cs]e\b", rest, re.I):
            return None
    elif not re.match(r"[0-9]", rest):
        return None
    return " ".join(whole.split())


def split(text):
    """A licence file's copyright notices, and its text without them. "All
    rights reserved." on the line after a notice belongs to the notice."""
    notices, body = [], []
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        found = notice(lines[index])
        if found is None:
            body.append(lines[index])
        else:
            if index + 1 < len(lines) and lines[index + 1].strip().lower() == "all rights reserved.":
                found += " All rights reserved."
                index += 1
            notices.append(found)
        index += 1
    return notices, "\n".join(body).strip("\n")


FILE = re.compile(r"^(licen[cs]e|copying|copyright|notice|unlicense)", re.I)


def licence_files(package):
    """The crate's licence files, from its own folder; for a crate from git
    with none there, from the folders above it up to the checkout's root."""
    folder = os.path.dirname(package["manifest_path"])
    from_git = (package.get("source") or "").startswith("git+")
    while True:
        files = sorted(f for f in os.listdir(folder)
                       if FILE.match(f) and os.path.isfile(os.path.join(folder, f)))
        if files or not from_git:
            return [(f, open(os.path.join(folder, f), encoding="utf-8", errors="replace").read()) for f in files]
        parent = os.path.dirname(folder)
        if os.path.basename(os.path.dirname(parent)) == "checkouts" or parent == folder:
            return []
        folder = parent


crates = []
for key in sorted(wanted):
    package = packages[key]
    expression = package.get("license") or ""
    if not expression:
        sys.exit(f"{key[0]} {key[1]} names no licence: read its files and decide by hand")
    files = licence_files(package)
    crates.append({
        "name": key[0], "version": key[1], "expression": expression,
        "repository": (package.get("repository") or "").rstrip("/"),
        "authors": package.get("authors") or [],
        "chosen": choose(expression),
        "files": [(name, text, classify(text)) for name, text in files],
        # Apache-2.0 asks that a NOTICE file go along whole.
        "notice_files": [text.strip("\n") for name, text in files if re.match(r"notice", name, re.I)],
    })

# Each crate's notices for each licence it is taken under: the copyright
# lines of its files of that licence, of its COPYRIGHT and NOTICE files, and
# of files that are no licence's text. A crate whose files carry none takes
# those of a crate from the same repository (alloc-stdlib, alloc-no-stdlib's),
# and failing that its authors.
for crate in crates:
    crate["notices"] = {}
    for licence in crate["chosen"]:
        lines = []
        for name, text, kinds in crate["files"]:
            if licence in kinds or not kinds or re.match(r"(copyright|notice)", name, re.I):
                lines += split(text)[0]
        crate["notices"][licence] = list(dict.fromkeys(lines))
for crate in crates:
    for licence, lines in crate["notices"].items():
        if lines:
            continue
        for other in crates:
            if other is not crate and crate["repository"] and other["repository"] == crate["repository"]:
                lines += other["notices"].get(licence, [])
                if lines:
                    break
        if not lines:
            authors = ", ".join(re.sub(r"\s*<[^>]*>", "", a) for a in crate["authors"])
            lines.append(f"Copyright the {crate['name']} authors" + (f": {authors}" if authors else ""))

# Each licence's text: the one most of its crates' files carry, less the
# copyright lines (listed per crate instead).
texts = {}
for licence in sorted({l for c in crates for l in c["chosen"]}, key=PREFERENCE.index):
    candidates = Counter()
    original = {}
    for crate in crates:
        for name, text, kinds in crate["files"]:
            if kinds == {licence}:
                body = split(text)[1]
                key = " ".join(body.split())
                candidates[key] += 1
                original.setdefault(key, body)
    if not candidates:
        sys.exit(f"no crate ships the text of {licence}: add it by hand")
    texts[licence] = original[candidates.most_common(1)[0][0]]

ABOUT = [
    ("Harper", "harper-core, through eGlu-dot-app/harperSwift, by Automattic: grammar checking"),
    ("anydoc", "by Firecrawl: Office, OpenDocument, RTF, EPUB and CSV documents to Markdown"),
    ("pdf-inspector", "by Firecrawl: PDFs to Markdown, and which pages are only pictures"),
]
INTRO = ("eGlu's engines are built from source with the open-source crates below: "
         "every crate compiled into the engines' library for the Mac, iPhone and iPad. "
         "Each is listed under the licence eGlu takes it under (where a crate offers a "
         "choice, the first of " + ", ".join(PREFERENCE[:3]) + " and so on that it offers), "
         "with the copyright notices its licence files carry, and each licence's full "
         "text follows its list.")


def mpl_sources(group):
    return ["The Mozilla Public License asks that you be told where the source of these "
            "files is. eGlu builds them unchanged from these crates' published source:"] + [
        f"{c['name']} {c['version']}: https://crates.io/crates/{c['name']}/{c['version']}"
        + (f" (repository {c['repository']})" if c["repository"] else "")
        for c in group]


groups = {licence: [c for c in crates if licence in c["chosen"]] for licence in texts}

with open("LICENSES.md", "w") as out:
    w = lambda line="": out.write(line + "\n")
    w("# Licences")
    w()
    w(INTRO + " Regenerate this file with `./licenses.sh` after any change to `Cargo.lock`.")
    w()
    for name, about in ABOUT:
        w(f"- **{name}** ({about}).")
    w()
    w("| Crate | Version | Licence | Taken under | Repository |")
    w("|---|---|---|---|---|")
    for c in crates:
        w(f"| {c['name']} | {c['version']} | {c['expression']} | {' AND '.join(c['chosen'])} | {c['repository']} |")
    for licence, group in groups.items():
        w()
        w(f"## {NAMES[licence]} ({licence})")
        w()
        for c in group:
            w(f"- **{c['name']} {c['version']}**: " + "; ".join(c["notices"][licence]))
            for text in c["notice_files"] if licence == "Apache-2.0" else []:
                w()
                w("  ```text")
                for line in text.splitlines():
                    w(f"  {line}")
                w("  ```")
        if licence == "MPL-2.0":
            w()
            lines = mpl_sources(group)
            w(lines[0])
            w()
            for line in lines[1:]:
                w(f"- {line}")
        w()
        w("```text")
        w(texts[licence])
        w("```")

with open("Sources/Engines/Licenses.txt", "w") as out:
    w = lambda line="": out.write(line + "\n")
    w("eGlu's engines")
    w()
    for name, about in ABOUT:
        w(f"{name} ({about}).")
    w()
    w(INTRO)
    for licence, group in groups.items():
        w()
        heading = f"{NAMES[licence]} ({licence})"
        w(heading)
        w("=" * len(heading))
        w()
        for c in group:
            w(f"{c['name']} {c['version']}")
            for notice in c["notices"][licence]:
                w(f"  {notice}")
            for text in c["notice_files"] if licence == "Apache-2.0" else []:
                for line in text.splitlines():
                    w(f"    {line}")
        if licence == "MPL-2.0":
            w()
            lines = mpl_sources(group)
            w(lines[0])
            for line in lines[1:]:
                w(f"  {line}")
        w()
        w(f"The text of the {NAMES[licence]}:")
        w()
        w(texts[licence])

print(f"Wrote LICENSES.md and Sources/Engines/Licenses.txt: {len(crates)} crates, "
      f"{len(texts)} licences ({', '.join(texts)})")
PYEOF
