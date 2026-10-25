# eGlu symbol

The brand symbol: a globe that is also an "e", with a cursor in the e's opening and motion crescents behind it. The app icon, `Shared/eGlu.icon`, is drawn from it: its two layers are `eglu-icon-e.svg` and `eglu-icon-cursor.svg`. The icon before it is `App/Globe.icon`.

| File | Use |
| --- | --- |
| `eglu-symbol.svg` | The symbol, black, for light backgrounds |
| `eglu-symbol-white.svg` | The same, white, for dark backgrounds |
| `eglu-symbol-compact.svg` | Without the motion crescents, for 32 px and smaller (favicons, small UI) |
| `eglu-symbol-compact-white.svg` | The same, white |
| `eglu-icon.svg`, `eglu-icon-white.svg` | The symbol in the sketch's 800-point frame, the e's bowl centred top to bottom |
| `eglu-icon-e.svg`, `eglu-icon-cursor.svg` | The letter (with its crescents) and the cursor apart, in that frame, white: the app icon's layers |
| `*-preview-light.png`, `*-preview-dark.png` | Each at 640, 128, 64, 32 and 16 px |
| `symbol.swift` | Draws all of the above |
| `mac-icons.swift` | Draws the Mac's pictures of the app icons, light and dark, from the Icon Composer files (`Mac/Assets.xcassets/AppIcons`, for Settings › General › App Icon and the Dock); run it after changing an icon |

Each SVG is one filled path on a square artboard. The `eglu-symbol` ones are centred on the symbol's bounds; the `eglu-icon` ones keep the sketch's frame, so the layers line up.

## How it is drawn

Redrawn from the sketch in the Figma file (node 31:8, "globe 1"), with true curves in place of the sketch's traced outlines:

- The bowl is two ellipses, the inner one offset to the left: thick on the right, a hairline on the left, as a serif "e" is.
- The meridian is an even ring centred in the bowl's counter. The equator is the e's bar.
- The e's opening is cut out, not covered.
- The cursor is the classic arrow, tilted 6.8° as in the sketch, with rounded corners and a clear gap around it: the right wing's underside level, the left one at about 45°, both notches cut in as deep and the tail's sides parallel. Its tip is the sketch's, (532, 427), and it is about as tall (311).
- The motion crescents are built like the bowl, from offset ellipses, each thinner, further out and shorter than the one inside it.

To try a different measure, set it when running `symbol.swift` (each is read with `v("NAME", default)` in the file, for example `LEFT=20`). From the repository's folder:

```bash
swiftc -O Marketing/Brand/symbol.swift -o /tmp/symbol && /tmp/symbol Marketing/Brand
```

```bash
COUNT=0 NAME=eglu-symbol-compact /tmp/symbol Marketing/Brand
```

```bash
FRAME=1 NAME=eglu-icon /tmp/symbol Marketing/Brand
```

After changing the icon's layers, copy `eglu-icon-e.svg` and `eglu-icon-cursor.svg` over `Shared/eGlu.icon/Assets/e.svg` and `cursor.svg`.
