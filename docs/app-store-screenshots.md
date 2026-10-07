# App Store screenshot direction

## Current direction

On October 6, 2026, the existing **Editorial Signal** series was retained instead
of the new explorations. Keep the coral-red gradient (`#F25447`, `#DF382F`,
`#C82B27`), black Georgia headlines, cream details and real app captures.
The refreshed Mac series and editable HTML live in `design/app-store/macos/`.
Export Mac compositions at 2880 x 1800.

Phone work is deferred until new screenshots are supplied. Future iPhone
headlines must use the full available canvas width inside safe margins rather
than a narrow text column. No new phone series is part of the Mac refresh.

Use automated rendering, text measurements, asset and PNG checks for this
refresh. Do not perform manual or visual browser checks.

## Previous Grid study

On October 5, 2026, **Grid (example 01)** was selected as the foundation for
Pomodoist App Store screenshots. It is now retained as a historical study;
the current production direction is Editorial Signal above.

![Selected Grid reference](assets/app-store-grid-reference.png)

The visual character is clear, structured and calm: warm paper, a faint square
grid, heavy left-aligned type, one dark red emphasis and a large upright device
showing the real app. The headline communicates a benefit; the screenshot
provides the evidence.

These rules govern store marketing compositions. Application components,
themes and motion continue to follow the [Flutter design system](design-system.md).

## Palette and background

| Role | Value |
| --- | --- |
| Paper background | `#F2F1EC` |
| Primary text | `#161614` |
| Emphasis and eyebrow | `#A92B1D` |
| Grid lines | Primary text at 8% opacity |

At the 1320 × 2868 reference size, the square grid has a 106 px pitch and 2 px
lines. Keep it behind the type and device. The reference renderer adds a soft
radial tint using the accent at 18% opacity, centered around 55% of canvas
height. Preserve its subtlety: the grid is structure, and the headline remains
the strongest element outside the phone.

## Typography and copy

Use the locally bundled **Inter Tight** font. Use weight 800 for display text
and weight 500 for the supporting line. Keep all marketing text left aligned.

| Element | Reference size | Treatment |
| --- | --- | --- |
| Eyebrow | Approximately 37 px | Uppercase, weight 600, dark red |
| Main headline | Approximately 170 px | Weight 800, near-black, 0.96 line height |
| Emphasis line | 180 px | Weight 800, dark red, 1.05 line height |
| Supporting line | 42 px | Weight 500, near-black, 1.05 line height |

Sell one idea per slide with two short headline beats. Use sentence case,
intentional line breaks and plain English. Highlight the payoff in dark red.
Supporting copy is optional and should fit on one line. Measure long headlines
and reduce their size when necessary; preserve the hierarchy and safe margins.

The selected Focus example reads:

- Eyebrow: `POMODOIST / FOCUS`
- Main headline: `One timer.`
- Emphasis: `One task.`
- Supporting line: `Make room for focused work.`

## Reference composition

Reference coordinates below are in pixels on a **1320 × 2868** canvas. Scale
proportionally for other output sizes.

| Element | Position and dimensions |
| --- | --- |
| Caption container | x 84, y 150, width 1152, height 320 |
| Emphasis container | x 84, y 420, width 1152, height 200 |
| Supporting line container | x 84, y 665, width 1152, height 65 |
| Phone | x 172, y 800, width 1076, height approximately 2192 |

The selected reference uses the `hero` layout with these explicit positions.
The phone is upright at 0° and deliberately bleeds approximately 124 px past
the bottom edge. Around 72% of the canvas height contains the visible device.
Use the screenshot skill's default `Phone` frame and a soft shadow (editor
shadow value 45). Keep glow and scene tilt at zero, with decoration set to
`none`. The grid and restrained accent provide the visual interest.

Use actual app captures with their original UI colors. For this reference,
the source is `design/app-store/iphone/screenshots/02-focus-light.PNG`.
Preserve the UI detail that proves the headline, including the timer value
and main controls. Allow intentional device cropping while keeping text fully
inside each exported screen.

For a series, retain the palette, grid and type hierarchy. Vary device placement
where it helps the feature read; keep each slide understandable on its own.
Two-device compositions are an optional variation when they explain a real
relationship between screens. The single-device reference remains the starting
composition.

## Source files and working editor

- Fixed full-size reference: `design/app-store/editor-examples-20261005/01-grid.png`.
- Editable project: `design/app-store/editor-examples-20261005/01-grid/`.
- Project state: `app-store-screenshots.json` inside that editor directory.
- Renderer and export workflow: `.agents/skills/app-store-screenshots/`.

The reference image embedded in this document preserves the selected appearance
under `docs/assets/`. The larger files and editors under `design/` are currently
ignored by Git. The working editor is mutable and currently contains a
two-device experiment; its state was preserved when this direction was recorded.
Use the fixed reference and geometry above to reproduce the selected composition.

From the editor directory, run:

```sh
pnpm install
pnpm dev --hostname 127.0.0.1 --port 3100
```

## Export and review

Use **Export bundle** in the skill editor. The existing iPhone preset generates
1320 × 2868, 1284 × 2778, 1206 × 2622 and 1125 × 2436 PNGs. Confirm the required
store slots when preparing a final submission.

Before accepting a new slide, check that:

- Its benefit is clear at a 220 px thumbnail width.
- Every text line fits its container and stays inside the exported canvas.
- Headline, emphasis and supporting text each have at least 4.5:1 contrast
  against the background beneath them.
- The real screenshot and device frame are present in the exported PNG.
- The device is large enough to read, and any edge crop is deliberate.
- PNG dimensions match the chosen preset and exports are opaque RGB.

This direction records a selected design example. Final store assets need
current product captures and a review of every exported slide.
