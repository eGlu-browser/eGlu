#!/usr/bin/env python3
"""Compose feature chapters from native Mac and simulator recordings."""

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


def panel(repo, scene, number, total, step, path):
    image = background()
    brand(image, repo)
    draw = ImageDraw.Draw(image)
    text(draw, (112, 230), f"{number:02} / {total:02}   ·   {scene['deviceLabel']}", 24, "Medium", MUTED)
    text(draw, (106, 286), scene["headline"], 72, "Semibold", spacing=4)
    y = 610
    for index, caption in enumerate(scene["captions"]):
        active = index == step
        draw.ellipse((112, y + 15, 122, y + 25), fill=scene["accent"] if active else "#babeb1")
        text(draw, (146, y), caption, 30, "Semibold" if active else "Regular", INK if active else MUTED, spacing=4)
        y += 92
    width = 430 / total
    for index in range(total):
        x = 112 + index * width
        draw.line((x, 938, x + width - 8, 938), fill=scene["accent"] if index == number - 1 else "#c6caba", width=4)
    text(draw, (112, 979), "Native capture · Synthetic content", 21, fill=MUTED)
    image.save(path)


def slate(repo, path, ending=False):
    image = background()
    brand(image, repo)
    draw = ImageDraw.Draw(image)
    if ending:
        text(draw, (108, 338), "eGlu", 144, "Semibold")
        text(draw, (112, 557), "Mac · iPad · iPhone", 58, "Medium")
        text(draw, (112, 679), "A browser for desktop web apps.", 35, fill=MUTED)
    else:
        text(draw, (112, 241), "FEATURE OVERVIEW", 25, "Medium", MUTED)
        text(draw, (106, 314), "eGlu on Mac,\niPad and iPhone.", 104, "Semibold", spacing=5)
        text(draw, (1144, 350), "Desktop web apps\nSplit View\nSpaces\nCommand bar\nBookmarks\nTrackpad View", 38, "Medium", spacing=24)
    text(draw, (112, 979), "Actual eGlu interface · Local synthetic demo pages", 24, fill=MUTED)
    image.save(path)


def geometry(repo, device, cache, video):
    if device == "mac":
        result = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "json", str(video)])
        stream = json.loads(result)["streams"][0]
        scale = min(1220 / stream["width"], 850 / stream["height"])
        width, height = round(stream["width"] * scale), round(stream["height"] * scale)
        x, y = round(1265 - width / 2), round(560 - height / 2)
        bezel_path = cache / "mac-border.png"
        bezel = Image.new("RGBA", (width, height))
        ImageDraw.Draw(bezel).rounded_rectangle((0, 0, width - 1, height - 1), radius=12, outline="#c6caba", width=1)
        bezel.save(bezel_path)
        mask_path = cache / "mac-mask.png"
        mask = Image.new("L", (width, height))
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=12, fill=255)
        mask.save(mask_path)
        return x, y, x, y, width, height, bezel_path, mask_path
    if device not in ("ipad", "iphone"):
        raise ValueError(f"Unsupported device: {device}")
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


def footage(repo, scene, number, total, cut, index, clips, cache):
    start, end = cut["in"], cut["out"]
    speed = cut.get("speed", 1)
    if not (0 <= start < end and 0 < speed <= 4):
        raise ValueError(f"Invalid edit: {cut}")
    frames = math.ceil((end - start) / speed * 30)
    device = cut.get("device", scene["device"])
    display = dict(scene, deviceLabel=cut.get("deviceLabel", scene["deviceLabel"]))
    bg = cache / f"scene-{number}-step-{cut['step']}-{device}.png"
    panel(repo, display, number, total, cut["step"], bg)
    video = clips / cut.get("source", scene["source"])
    if end > duration(video):
        raise ValueError(f"Edit exceeds source duration: {cut}")
    x, y, sx, sy, sw, sh, bezel, mask = geometry(repo, device, cache, video)
    output = cache / f"scene-{number}-cut-{index}.mp4"
    graph = (
        f"[1:v]setpts=(PTS-STARTPTS)/{speed},fps=30,scale={sw}:{sh}:flags=lanczos,setsar=1,format=rgba[v];"
        "[v][3:v]alphamerge[rounded];"
        f"[0:v][rounded]overlay={sx}:{sy}:shortest=1[screen];"
        f"[screen][2:v]overlay={x}:{y}:shortest=1,format=yuv420p[out]"
    )
    run("ffmpeg", "-y", "-v", "error", "-loop", "1", "-framerate", "30", "-i", bg,
        "-ss", start, "-t", end - start, "-i", video,
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
            part = footage(args.repo, scene, number, len(config["scenes"]), cut, index, args.clips, cache)
            length = duration(part)
            subtitles.append({"start": clock, "end": clock + length, "text": scene["captions"][cut["step"]], "device": cut.get("device", scene["device"])})
            clock += length
            paths.append(part)
        chapters.append({"start": chapter_start, "end": clock, "title": scene["title"]})
    ending = cache / "ending.png"
    slate(args.repo, ending, True)
    ending_video = cache / "ending.mp4"
    still(ending, 3, ending_video)
    paths.append(ending_video)
    chapters.append({"start": clock, "end": clock + duration(ending_video), "title": "eGlu on Mac, iPad and iPhone"})
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
