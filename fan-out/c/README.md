# Variant C: age beneath the progress row

Open `index.html` locally. It is self-contained, uses no dependencies or remote assets, and renders one expanded panel at exactly 350 CSS pixels wide. The panel is `.pn-c`; its styles are scoped for extraction into a comparison. Header controls and dismiss buttons are static mockup controls.

## Choice and rationale

Place “Added 5 minutes ago” in a quiet, left-aligned footer immediately below the progress bar and percentage. Use the existing secondary text color, 11px system type, tabular digits, a 14px line height, and 4px spacing above it. Align it with the full-width progress bar, including for entries without a project.

This is persistent entry history, so it follows current state: title → ETA → progress → age. It has an unambiguous “Added” label and enough width for the full relative phrase. It preserves the title's existing wrapping width, keeps the ETA in its familiar position, and avoids the dismiss button. No badge, icon, or extra divider is needed.

## Three placements considered

1. **Below the progress row (chosen).** Full-width, stable across project and no-project entries, and accommodates seconds/minutes without collision. Costs 18px per entry compared with the existing layout.
2. **In the title stack, directly below ETA.** Keeps both time facts together and offers a straightforward SwiftUI change. Adds the same height but crowds the title area; the no-project icon also narrows the available width for long age phrases.
3. **On the ETA row, trailing-aligned opposite the remaining time.** Could preserve the current card height. At 350px, the existing icon and dismiss control leave too little text width for “About 4m left” plus “Added 47 seconds ago”; it would need shorter wording, truncation, or wrapping.

## Grounding and visual choices

Read `Sources/ProgressNotifier/ProgressCard.swift`. Preserved the expanded 350px panel, 10px outer padding, 4px list inset, 6px item spacing, 20px panel rounding, 12px item rounding, 12px horizontal/9px vertical item padding, project heading, two-line 13px semibold titles, 11px ETA, 5px progress bars, 38px percentage column, and top-right dismiss buttons. Mint is `#3bb8a3`, matching the source RGB values. The quiet palette uses `#252729` primary text, `#62666a` secondary text, translucent `#f6f7f8` material, and `#dce2e3` desktop surround.

The layout decision is intentionally limited to one added text line. A more decorative badge or clock would compete with the small native controls. Both sample titles wrap to test the retained two-line limit; one entry has a project and one has the existing generic task icon.

## Validation and limitations

Browser fit checks are emitted to the console on load: exact panel width, title line counts, age-line fit, and descendants extending past the panel's right edge. T3's headless browser rendered the page at 430px and 350px viewport widths. Both runs reported a 350px-wide, 296px-high panel, two entries, two lines per title, both age phrases fitting on one line, and no descendants extending past the panel. The 430px screenshot was visually inspected: the footer reads separately from ETA, keeps the mint progress bar dominant, and works with both entry structures.

This is a light-appearance HTML approximation of SwiftUI `regularMaterial`, not a pixel-perfect AppKit render. The text and ages are static; production must calculate age from the first-added timestamp, preserve it across updates, and refresh only in expanded mode. The existing expanded timeline could supply the current time. Localization and larger accessibility type can require additional wrapping. A footer increases scroll height by 18px per entry.
