#!/usr/bin/env python3
"""The appcast Sparkle reads to update eGlu for Mac (Release/mac.sh release).

Takes the appcast as last published (or none), puts a new item for this
version at its top, and writes it out:

    Release/appcast.py --previous old.xml --out appcast.xml --version 1.0.8 --build 38 \
        --url https://github.com/eGlu-dot-app/eGlu/releases/download/v1.0.8/eGlu-1.0.8.dmg \
        --length 12345 --signature BASE64 --notes CHANGELOG.md

The item says the build (sparkle:version, which Sparkle compares), the
version people see, the least macOS it runs on, the disk image's length and
EdDSA signature (sign_update's), and the CHANGELOG's section for the version
as its release notes. It refuses a build that isn't newer than the newest
already there: Sparkle would never offer it.

  --newest old.xml   prints the newest build in an appcast, or nothing.
"""

import argparse
import html
import re
import sys
from email.utils import formatdate
from xml.etree import ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", DC)


def newest_build(tree):
    builds = []
    for item in tree.iter("item"):
        version = item.find(f"{{{SPARKLE}}}version")
        if version is None:
            enclosure = item.find("enclosure")
            value = enclosure.get(f"{{{SPARKLE}}}version") if enclosure is not None else None
        else:
            value = version.text
        if value and value.strip().isdigit():
            builds.append(int(value.strip()))
    return max(builds) if builds else None


def notes_for(version, changelog):
    """The CHANGELOG's section for the version ("## 1.0.3", a date after it
    or not), else Unreleased's, as HTML: its lines, its lists as lists."""
    text = open(changelog, encoding="utf-8").read()
    sections = re.split(r"(?m)^## ", text)
    chosen = None
    for section in sections[1:]:
        title = section.splitlines()[0].strip()
        if title.split()[0] == version:
            chosen = section
            break
    if chosen is None:
        chosen = next((s for s in sections[1:] if s.startswith("Unreleased")), "")
        print(f"note: no '## {version}' in {changelog}; the notes are Unreleased's", file=sys.stderr)
    out, listing = [], False
    for line in chosen.splitlines()[1:]:
        line = line.rstrip()
        heading = re.match(r"^### (.*)", line)
        item = re.match(r"^- (.*)", line)
        if listing and not item:
            out.append("</ul>")
            listing = False
        if heading:
            out.append(f"<h3>{inline(heading.group(1))}</h3>")
        elif item:
            if not listing:
                out.append("<ul>")
                listing = True
            out.append(f"<li>{inline(item.group(1))}</li>")
        elif line:
            out.append(f"<p>{inline(line)}</p>")
    if listing:
        out.append("</ul>")
    return "\n".join(out)


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--previous")
    parser.add_argument("--newest")
    parser.add_argument("--out")
    parser.add_argument("--version")
    parser.add_argument("--build", type=int)
    parser.add_argument("--url")
    parser.add_argument("--length", type=int)
    parser.add_argument("--signature")
    parser.add_argument("--notes")
    parser.add_argument("--minimum", default="26.0")
    args = parser.parse_args()

    if args.newest:
        build = newest_build(ET.parse(args.newest))
        print(build if build is not None else "")
        return

    if args.previous:
        tree = ET.parse(args.previous)
        channel = tree.getroot().find("channel")
    else:
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "eGlu"
        ET.SubElement(channel, "link").text = "https://github.com/eGlu-dot-app/eGlu"
        ET.SubElement(channel, "description").text = "Updates to eGlu for Mac."
        ET.SubElement(channel, "language").text = "en"
        tree = ET.ElementTree(root)

    newest = newest_build(tree)
    if newest is not None and args.build <= newest:
        sys.exit(f"Build {args.build} is not newer than {newest}, the newest in the appcast: raise CURRENT_PROJECT_VERSION.")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"eGlu {args.version}"
    ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = str(args.build)
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = args.version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = args.minimum
    description = ET.SubElement(item, "description")
    description.text = notes_for(args.version, args.notes) if args.notes else ""
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": str(args.length),
        "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": args.signature,
    })
    # The newest first, after the channel's own lines.
    items = channel.findall("item")
    place = list(channel).index(items[0]) if items else len(channel)
    channel.insert(place, item)
    ET.indent(tree, space="  ")
    tree.write(args.out, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
