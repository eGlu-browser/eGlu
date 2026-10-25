#!/bin/zsh
# Writes LICENSES.md: every crate the release build links, with its license,
# from cargo metadata. Also writes Sources/Engines/Licenses.txt, the text the
# app's "Licences" button shows.

set -euo pipefail
cd "$(dirname "$0")"

metadata=$(mktemp)
trap "rm -f $metadata" EXIT
cargo metadata --format-version 1 --filter-platform aarch64-apple-ios > "$metadata"

emit() {
    python3 - "$metadata" <<'PYEOF'
import json, sys
meta = json.load(open(sys.argv[1]))
resolve = meta["resolve"]
packages = {p["id"]: p for p in meta["packages"]}
root = next(n["id"] for n in resolve["nodes"]
            if packages[n["id"]]["name"] == "eglu-engines")
wanted = {root}
queue = [root]
by_id = {n["id"]: n for n in resolve["nodes"]}
while queue:
    node = by_id[queue.pop()]
    for dep in node["deps"]:
        for kind in dep["dep_kinds"]:
            if kind["kind"] in (None, "normal"):
                if dep["pkg"] not in wanted:
                    wanted.add(dep["pkg"])
                    queue.append(dep["pkg"])
names = sorted((packages[i]["name"], packages[i]["version"], packages[i].get("license") or "?", packages[i].get("repository") or "") for i in wanted if i != root)
for name, version, license, repo in names:
    print(f"| {name} | {version} | {license} | {repo} |")
PYEOF
}

{
    echo "# Licenses"
    echo
    echo "eGlu's engines build from source, so every crate they link is listed"
    echo "here with its license. Regenerate with ./licenses.sh after a version bump."
    echo
    echo "- **Harper** (harper-core, via eGlu-dot-apps/harperSwift): grammar linting. Apache-2.0. Copyright Automattic."
    echo "- **anydoc**: Office, OpenDocument, RTF, EPUB and CSV to Markdown. MIT. Copyright Firecrawl."
    echo "- **pdf-inspector**: PDF to Markdown and OCR-needed detection. MIT. Copyright Firecrawl."
    echo
    echo "| Crate | Version | License | Repository |"
    echo "|---|---|---|---|"
    emit
} > LICENSES.md

{
    echo "eGlu's engines"
    echo
    echo "Harper (harper-core, via eGlu-dot-apps/harperSwift): grammar linting."
    echo "Apache License 2.0. Copyright Automattic."
    echo
    echo "anydoc: Office, OpenDocument, RTF, EPUB and CSV to Markdown. MIT License. Copyright Firecrawl."
    echo
    echo "pdf-inspector: PDF to Markdown and OCR-needed detection. MIT License. Copyright Firecrawl."
    echo
    echo "Every crate the engines link, with its license:"
    echo
    emit
} > Sources/Engines/Licenses.txt

echo "Wrote LICENSES.md and Sources/Engines/Licenses.txt"
