# Making a new flow video

Rules for a new looping video of a flow in eGlu, so it sits with the four on the site. They come from how those were made and from the changes asked for along the way. How to build one is in [README.md](README.md).

## What a video is for

- **One flow, one idea.** A video shows one thing eGlu does, start to finish, in the fewest steps that make it clear: a pinned tab switched with one thumb, a setting kept per device, a page handed to an app. If it needs a caption to be understood, the flow is too long or the wrong one.
- **Real app, made-up content.** Record the real app, never a mock of its interface. Everything on its pages is made up: the demo sites in `demo-pages/` (Mossgrove), with their own icons. No real people's names, faces, accounts, mail or messages; cover any that show (`compose/redact.py`).
- **Both devices when the point is both.** When a flow is about eGlu being the same (or deliberately not the same) across devices, show the iPhone and the Mac on one clock. Otherwise show only the device the flow belongs to.

## Frame

- **Canvas** 2730 by 1536 (16:9), shown at 1600 by 900. Ground `(17, 17, 19)`, the same on every video, so they read as one set on the page.
- **Dark appearance** on every device, with the status bar at 9:41 and a full battery.
- **The iPhone** in Apple's Pro Max Deep Blue frame at one size and place (scale 0.3815 at (380.6, 116.7)), left of centre when something stands beside it, in the middle when it is alone.
- **The Mac** close up: the part of the window that matters, large enough to read, running off the canvas's right and bottom edges rather than shrunk to fit whole. A dark backdrop window behind it, so no desktop shows.
- **The iPad** as a line drawing of the iPad on its Magic Keyboard, the take in its screen; no zoomed side panel.
- **Nothing else:** no headline, caption, logo or background graphics in the video. The page around it carries the words.

## The hand and the pointer

- **The hand** is a line drawing, one even stroke, no fill, no shading, no nails or wrinkles, drawn in the site's sky blue `(61, 155, 233)`; it has to look like a hand holding a phone, in a natural pose, before anything else. The right thumb taps; the left hand holds.
- **The thumb comes in** from off the phone about 0.75 s before a tap, rests a little short of the target, glides onto it in about 0.15 s, and leaves soon after. There is a short pause before every press, so the eye arrives first.
- **A press is shown** by short lines bursting from the tip as it lands and as it lifts, in the hand's colour, never by a halo or glow (it competes with the app's own glow on pinned tiles). A long press is held longer than recorded and shown by an arc filling round the thumb's tip, so it reads as long.
- **The Mac pointer** is the system's own, captured in the recording. It moves on smooth eased curves (`record/mac/pointer*.swift`), never in straight jumps, and clicks get the same short burst lines from its tip.
- **The iPad pointer** is the iPad's own dot, or the page's own cursor where the page sets one; its path is scripted and smooth, and the cursors must look refined, not jittery.

## Time

- **10 to 20 seconds.** The four run from 11.5 to 18.5.
- **60 frames a second** from start to end; convert simulator takes to a steady 60 before composing.
- **Cut the waiting, not the motion.** A long wait (a model reading a page) is cut with a short crossfade (about 0.25 s); everything the person does plays at its real speed.
- **Hold the result.** After the flow ends, hold its result for a beat (1 to 2.5 s) so it can be read.
- **Loop without a seam.** The last 0.35 s crossfades back to the first frame; the scene ends as it began (an undo at the end of the iPad take, a switch turned back on).
- **Devices in step.** When two devices appear, one clock drives both: record each take, find the offset from the takes themselves (`analyse.py`, `events.py`), and line them up in the composer.

## Text in the video

- Only what the app itself shows. Where a video shows a file eGlu made (Handoff), set it as the text it is, in Paper Mono, from the real file the take wrote, with the demo's own address in place of `localhost`.

## Files

- `<flow>-loop.mp4`: H.264, CRF 25, slow preset, no sound, `+faststart`, 1600 by 900.
- `<flow>-loop-poster.webp`: one frame at the moment that explains the flow best (not the first frame), quality 80.
- Commit the composer and any new demo page or tool here with the video's section in README.md; nothing that makes a video lives only in a scratch folder.

## Checklist before it goes on the site

- [ ] One flow, understood without words.
- [ ] Real app; no real personal data anywhere in any frame.
- [ ] Dark, 9:41, same ground, same phone frame and size.
- [ ] The hand looks like a hand; presses read as presses; long presses read as long.
- [ ] Steady 60 fps, no jumps, waits cut, result held.
- [ ] The loop's seam can't be seen.
- [ ] Watched in the site at its real size, in light and dark page themes.
- [ ] Scripts and demo pages committed here.
