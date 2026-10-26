# Landing page videos

The four looping videos on the eGlu site (`eGlu-dot-app/eGlu-site`, `media/`) and how to make them again. They were made on 24 and 25 October 2026; the scripts here were recovered from those sessions' records, step for step, after their scratch folders were deleted. Rules for making a new one are in [Guidelines.md](Guidelines.md).

| Video | Shows | Composer |
|---|---|---|
| `pinned-tab-switch-loop.mp4` | The thumb holds the iPhone's pinned button and slides through the pinned list; the Mac's pointer crosses the same pinned tiles on the same clock. | `compose/pinned-switch.py` |
| `pinned-tab-visibility-loop.mp4` | Instagram turned off and on in Settings › Pinned Tabs, on the iPhone and on the Mac, each keeping its own choice. | `compose/pinned-visibility.py` |
| `handoff-loop.mp4` | Handoff on iPhone: … › Send to App, the sheet reading the page, Send to App; then the Markdown file it made, in Paper Mono. | `compose/handoff.py` |
| `ipad-cursor-loop.mp4` | A design web app on iPad with a Magic Keyboard: the pointer picks a tool, draws, resizes, pans; the page's own cursors show. | `compose/ipad-cursor.py` |

Each comes with a poster (`*-poster.webp`), one frame of it.

## The folders

| Folder | What is in it |
|---|---|
| `compose/` | The composers (Python, Pillow, numpy; run with `PATH=/opt/anaconda3/bin:$PATH`), and the hand: `hand-prompt.txt`, `clean.py`, `vectorize.py`, `hand-sky.py`, `pose_right.py`. Also `scene.py` and `poster.py` for stills, `redact.py` for covering real names in a Mac share menu. |
| `record/iphone/` | `rec.sh` starts and stops a simulator recording; `events.py` finds when a switch flips or the screen moves in a take; `wait-ready.py` waits for Handoff's sheet to be ready. Set `DEVICE` to the simulator's id (default: the booted one). |
| `record/ipad/` | `script.py` writes the pointer path the iPad demo build plays (`take-script.json`); `track.py` follows a page's drawn cursor in a take (Figma take only). |
| `record/mac/` | Swift tools, built with `swiftc -O x.swift -o x`: `backdrop` (a dark window behind everything), `axmove`, `axsize`, `axfront`, `axclose`, `axdump`, `windows`, `winlist` (place, size, raise and list windows through Accessibility), `pointer`, `pointer2`, `pointer3` (each video's scripted pointer: smooth curves, clicks only while the app's window is under it), `click`, `key`, `esc`, `scrollup`. `analyse.py` finds when the pointer left and each tile lit in a take. They post real mouse and key events: the Terminal running them needs Accessibility permission, and nothing else should be on screen. |
| `hairline/` | The iPad and Magic Keyboard line drawing (`magic-keyboard.js`, a figure for the Hairline engine, see the `/hairline-create` skill), `render-still.mjs` to render its still parts to `still-dark.png`, and the Scrub figure (`scrub.js`, `export-hand.mjs`) an early version of the hand came from. |
| `demo-pages/` | Made-up sites the takes show, served on this Mac (`python3 -m http.server 8766` here): the Mossgrove job post, the Mossgrove Canvas design app (`canvas/`, with its cursors), an issue page, a video call and a brand page. |
| `app-demo/` | The changes the takes need in the app: `ipad-scripted-pointer.patch` (the iPad plays `EGLU_DATA_ROOT/pointer-go.json` and draws the iPad's pointer dot; applies to main as of 26 Oct and builds) and `apply_demo_hooks.py` (every recorded demo edit, including the Mac ones, which no longer apply to main). Apply them in a scratch checkout, build under a test bundle id (`net.taehee.safience.demo`), and never merge them. |

Not here: the hand pictures themselves (`hand-1.png`, `hand-lines.png`, `hand-smooth.png`, `hand-sky.png`) and `still-dark.png`, which were never committed. Make them again as below.

## Common to all four

- **Canvas:** 2730 by 1536 at 60 frames a second, ground `(17, 17, 19)`. Final files are 1600 by 900.
- **iPhone:** iPhone 17 Pro Max simulator, dark appearance, `xcrun simctl status_bar <device> override --time 9:41 --batteryState discharging --batteryLevel 100`, the app started with `SIMCTL_CHILD_EGLU_ISOLATED_QA=1 SIMCTL_CHILD_EGLU_DATA_ROOT=<folder>` so a test workspace is used. Drawn in Apple's Pro Max Deep Blue frame (`Marketing/AppStore/source/bezels/promax-blue.png`, fetched by `bezels.sh`) at scale 0.3815, placed at (380.6, 116.7).
- **Recording:** `xcrun simctl io <device> recordVideo --codec=h264 --force take.mov`, stopped with `kill -INT`. The simulator records at a varying rate, so convert first: `ffmpeg -i take.mov -vf "fps=60" -c:v libx264 -crf 12 -g 30 -pix_fmt yuv420p take-cfr.mp4`.
- **Mac:** a Debug build under the test bundle id, data in its own folder (`open -n --env EGLU_DATA_ROOT=<folder> <app> --args -look dark`), `record/mac/backdrop` behind it, the window placed with `axmove` and raised with `axfront`, recorded with `ffmpeg -f avfoundation -capture_cursor 1 -framerate 60 -pixel_format bgr0 -i "<screen>:none" -vf "crop=…" -c:v libx264 -preset ultrafast -crf 14 mac-take.mp4` while the scripted pointer runs.
- **Encode and poster:**

```sh
ffmpeg -y -i raw.mp4 -vf "scale=1600:-2:flags=lanczos" -c:v libx264 -preset slow -crf 25 -pix_fmt yuv420p -an -movflags +faststart name-loop.mp4
ffmpeg -y -ss <t> -i raw.mp4 -frames:v 1 -vf "scale=1600:-2:flags=lanczos" -update 1 poster.png
cwebp -quiet -q 80 poster.png -o name-loop-poster.webp
```

Each composer takes `--still t out.png` to render one frame, for checking a moment before rendering the whole loop.

## The hand

1. Generate `hand-1.png` (1024 by 1536) from `compose/hand-prompt.txt` with an image model (it was made with `codex exec`'s image tool).
2. `python3 clean.py hand-1.png hand-lines.png` takes the drawn phone's outline out, keeping the thumb over it. Its phone box (`x0, y0, x1, y1, r`) is that picture's; measure a new picture's phone and change it.
3. `python3 vectorize.py hand-lines.png hand-smooth.png` redraws the lines as smooth, even strokes.
4. `python3 hand-sky.py hand-smooth.png hand-sky.png` colours it the site's sky blue `(61, 155, 233)`, the colour all the composers draw their lines in.
5. `pose_right.py` mirrors it for the right thumb, which Handoff and the visibility video use.

## pinned-tab-switch-loop

1. iPhone: pin Hacker News, Instagram and Google; record the long press on the pinned button and the slide through the list (about 16 s).
2. Mac: a test workspace with the same pinned tabs and their icons in `~/Library/Caches/Safience/Icons/`; `record/mac/pointer park 1260 676`, then record while `pointer run start.txt` crosses Hacker News, Instagram, Google and Instagram again on the phone's clock, clicking the last.
3. `python3 compose/pinned-switch.py take-cfr.mp4 hand-sky.png promax-blue.png mac-take.mov 1.39 raw.mp4` (1.39: the Mac take's time when the phone's is 0; find it with `record/mac/analyse.py`). The long press is held longer than recorded, shown by an arc filling round the thumb; short lines burst from the thumb and the pointer on each press. About 11.5 s.

## pinned-tab-visibility-loop

1. iPhone: four takes with `record/iphone/rec.sh start <name>` / `stop`: `seg-list-with` (the pinned list with Instagram), `seg-off` (Settings › Pinned Tabs, Instagram off), `seg-list-without`, `seg-on`. `events.py` gives each take's switch and movement times.
2. Mac: launched into Settings › Pinned Tabs (`--args -look dark -showing settings -settingsPane pinned`); record while `pointer2 run start.txt <pid>` switches Instagram's "View on macOS" off and on.
3. `python3 compose/pinned-visibility.py <folder of seg-*.mp4> hand-sky.png promax-blue.png mac-take.mp4 1.63 raw.mp4`. About 18.5 s.

## handoff-loop

1. Serve `demo-pages/` and open `demo-pages/jobs/mossgrove/senior-product-designer.html` (shown as `mossgrove.example`). Preferences: `{"handoff":true,"address":"automatic","intelligence":true}`; Handoff needs Apple Intelligence in the simulator.
2. Record one take: the page menu, Send to App, the sheet reading the page (it takes about two minutes on the simulator), Send to App, the share sheet. `record/iphone/wait-ready.py` tells when the sheet is ready.
3. Copy the Markdown file the take wrote (in the app's container, `tmp/Handoff/*/*.md`).
4. `python3 compose/handoff.py take-cfr.mp4 hand-sky.png promax-blue.png file.md 0 raw.mp4`. Its `KEYS` table maps loop time to take time and cuts the long wait with a crossfade; edit it for a new take. Then the phone moves left and the file comes in, set in Paper Mono (installed in `~/Library/Fonts`). About 17.75 s; poster at 13.0 s.

## ipad-cursor-loop

1. Apply `app-demo/ipad-scripted-pointer.patch` in a scratch checkout and build for the simulator under a test bundle id.
2. iPad simulator, dark, workspace with one tab: `http://localhost:8766/canvas/index.html` (Mossgrove Canvas).
3. `python3 record/ipad/script.py take-script.json` writes the pointer's path; start recording, copy it to `$EGLU_DATA_ROOT/pointer-go.json` (the app plays it within 0.2 s and logs to `pointer-log.txt`), stop after about 15 s. The path ends with an undo, so the canvas is back as it began.
4. Render the keyboard: `node hairline/render-still.mjs <magic-keyboard page>` gives `still-dark.png`.
5. `python3 compose/ipad-cursor.py take-cfr.mp4 still-dark.png take-script.json <offset> raw.mp4 --no-panel`; the offset is when the pointer first moves in the take (the frame difference in the tool rail). Poster at 5.6 s.
