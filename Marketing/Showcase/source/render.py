#!/usr/bin/env python3
"""Compose native simulator footage using an explicit, auditable edit list."""

import argparse
import json
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = (1920, 1080)
INK = "#161713"
MUTED = "#686c62"
FONT = "/System/Library/Fonts/SFNS.ttf"


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def font(size, weight="Regular"):
    face = ImageFont.truetype(FONT, size)
    face.set_variation_by_name(weight)
    return face


def text(draw, xy, value, size, weight="Regular", fill=INK, spacing=8):
    draw.multiline_text(xy, value, font=font(size, weight), fill=fill, spacing=spacing)


def background():
    image = Image.new("RGB", SIZE)
    draw = ImageDraw.Draw(image)
    top, bottom = (242, 242, 234), (218, 220, 205)
    for y in range(SIZE[1]):
        colour = tuple(round(a + (b - a) * y / (SIZE[1] - 1)) for a, b in zip(top, bottom))
        draw.line((0, y, SIZE[0], y), fill=colour)
    return image


def brand(image, repo):
    mark = Image.open(repo / "Marketing/Brand/eglu-symbol-preview-light.png").crop((0, 0, 688, 688))
    alpha = mark.convert("L").point(lambda value: 255 - value if value < 220 else 0)
    symbol = Image.new("RGBA", mark.size, INK)
    symbol.putalpha(alpha)
    symbol.thumbnail((76, 76), Image.Resampling.LANCZOS)
    image.paste(symbol, (100, 62), symbol)
    text(ImageDraw.Draw(image), (196, 65), "eGlu", 52, "Semibold")


def panel(repo, scene, number, step, path):
    image = background()
    brand(image, repo)
    draw = ImageDraw.Draw(image)
    text(draw, (112, 230), f"0{number} / 03   ·   {scene['deviceLabel']}", 24, "Medium", MUTED)
    text(draw, (106, 286), scene["headline"], 72, "Semibold", spacing=4)
    y = 610
    for index, caption in enumerate(scene["captions"]):
        active = index == step
        draw.ellipse((112, y + 15, 122, y + 25), fill=scene["accent"] if active else "#babeb1")
        text(draw, (146, y), caption, 31, "Semibold" if active else "Regular", INK if active else MUTED)
        y += 72
    for index in range(3):
        draw.line((112 + index * 210, 938, 292 + index * 210, 938), fill=scene["accent"] if index == number - 1 else "#c6caba", width=4)
    text(draw, (112, 979), "Native simulator capture · Synthetic demo content", 21, fill=MUTED)
    image.save(path)


def slate(repo, path, ending=False):
    image = background()
    brand(image, repo)
    draw = ImageDraw.Draw(image)
    if ending:
        text(draw, (108, 338), "Desktop web apps.\nSeparate spaces.", 100, "Semibold", spacing=10)
        text(draw, (112, 679), "eGlu on iPad and iPhone", 35, fill=MUTED)
    else:
        text(draw, (112, 241), "THREE EVERYDAY WORKFLOWS", 25, "Medium", MUTED)
        text(draw, (106, 314), "Your projects,\nside by side.", 104, "Semibold", spacing=5)
        text(draw, (1144, 376), "01   Review a design\n\n02   Switch projects\n\n03   Use a desktop site", 35, "Medium", spacing=6)
    text(draw, (112, 979), "Actual eGlu interface · Local synthetic demo pages", 24, fill=MUTED)
    image.save(path)


def geometry(repo, device, cache):
    source = repo / "Marketing/AppStore/source"
    spec = json.loads((source / ("frames.json" if device == "ipad" else "frames-iphone.json")).read_text())["params"]
    bezel = Image.open(source / "bezels" / spec["bezel"]).convert("RGBA")
    scale = 960 / int(spec["bh"])
    width, height = round(int(spec["bw"]) * scale), 960
    x, y = round(1440 - width / 2), 60
    bezel_path = cache / f"{device}-bezel.png"
    bezel.resize((width, height), Image.Resampling.LANCZOS).save(bezel_path)
    hx, hy, hw, hh = map(int, spec["hole"].split(","))
    sw, sh = round(hw * scale), round(hh * scale)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=round(int(spec["corner"]) * scale), fill=255)
    mask_path = cache / f"{device}-mask.png"
    mask.save(mask_path)
    return x, y, x + round(hx * scale), y + round(hy * scale), sw, sh, bezel_path, mask_path


def encode_args():
    return ["-c:v", "libx264", "-preset", "medium", "-crf", "19", "-profile:v", "high", "-pix_fmt", "yuv420p", "-r", "30", "-g", "60", "-video_track_timescale", "30000", "-an"]


def still(image, duration, output):
    run("ffmpeg", "-y", "-v", "error", "-loop", "1", "-framerate", "30", "-i", image, "-frames:v", round(duration * 30), *encode_args(), output)


def footage(repo, scene, number, cut, index, clips, cache):
    start, end = cut["in"], cut["out"]
    speed = cut.get("speed", 1)
    if not (0 <= start < end and 0 < speed <= 4):
        raise ValueError(f"Invalid edit: {cut}")
    frames = math.ceil((end - start) / speed * 30)
    bg = cache / f"scene-{number}-step-{cut['step']}.png"
    panel(repo, scene, number, cut["step"], bg)
    x, y, sx, sy, sw, sh, bezel, mask = geometry(repo, scene["device"], cache)
    output = cache / f"scene-{number}-cut-{index}.mp4"
    graph = (
        f"[1:v]setpts=(PTS-STARTPTS)/{speed},fps=30,scale={sw}:{sh}:flags=lanczos,setsar=1,format=rgba[v];"
        "[v][3:v]alphamerge[rounded];"
        f"[0:v][rounded]overlay={sx}:{sy}:shortest=1[screen];"
        f"[screen][2:v]overlay={x}:{y}:shortest=1,format=yuv420p[out]"
    )
    run("ffmpeg", "-y", "-v", "error", "-loop", "1", "-framerate", "30", "-i", bg,
        "-ss", start, "-t", end - start, "-i", clips / cut.get("source", scene["source"]),
        "-loop", "1", "-framerate", "30", "-i", bezel,
        "-loop", "1", "-framerate", "30", "-i", mask,
        "-filter_complex", graph, "-map", "[out]", "-frames:v", frames, *encode_args(), output)
    return output


def duration(path):
    result = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)])
    return float(json.loads(result)["format"]["duration"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("edits", type=Path)
    parser.add_argument("clips", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.edits.read_text())
    cache = args.output / "intermediates"
    cache.mkdir(parents=True, exist_ok=True)
    paths, chapters = [], []
    intro = cache / "intro.png"
    slate(args.repo, intro)
    intro_video = cache / "intro.mp4"
    still(intro, 3, intro_video)
    paths.append(intro_video)
    clock = duration(intro_video)
    chapters.append({"start": 0, "end": clock, "title": "eGlu showcase"})
    subtitles = []
    for number, scene in enumerate(config["scenes"], 1):
        chapter_start = clock
        for index, cut in enumerate(scene["cuts"]):
            part = footage(args.repo, scene, number, cut, index, args.clips, cache)
            length = duration(part)
            subtitles.append({"start": clock, "end": clock + length, "text": scene["captions"][cut["step"]]})
            clock += length
            paths.append(part)
        chapters.append({"start": chapter_start, "end": clock, "title": scene["title"]})
    ending = cache / "ending.png"
    slate(args.repo, ending, True)
    ending_video = cache / "ending.mp4"
    still(ending, 3, ending_video)
    paths.append(ending_video)
    chapters.append({"start": clock, "end": clock + duration(ending_video), "title": "eGlu on iPad and iPhone"})
    listing = cache / "concat.txt"
    listing.write_text("".join(f"file '{path.resolve()}'\n" for path in paths))
    metadata = cache / "chapters.txt"
    metadata.write_text(";FFMETADATA1\n" + "".join(
        f"[CHAPTER]\nTIMEBASE=1/1000\nSTART={round(ch['start'] * 1000)}\nEND={round(ch['end'] * 1000)}\ntitle={ch['title']}\n" for ch in chapters))
    run("ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", listing,
        "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000", "-i", metadata,
        "-map", "0:v", "-map", "1:a", "-map_metadata", "2", "-map_chapters", "2",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-shortest", "-movflags", "+faststart", args.output / "eGlu-showcase.mp4")
    (args.output / "timeline.json").write_text(json.dumps({"chapters": chapters, "captions": subtitles}, indent=2) + "\n")
    print(json.dumps({"video": str(args.output / "eGlu-showcase.mp4"), "chapters": chapters}, indent=2))


if __name__ == "__main__":
    main()
