# A — Quiet footer below the progress bar

Open `index.html` locally in a browser. No server, installation, fonts, images, or dependencies are needed. The panel is exactly 350 CSS pixels wide. Extract `.progress-panel` and its inline styles for comparison; `.stage` is only the neutral presentation background.

## Chosen placement

Place “Added 5 minutes ago” at the bottom left of each expanded item, below the progress bar. Use 10px regular secondary text, 13px line height, and a 6px top gap. Align it with the full-width bar rather than the title inset, so project and no-project cards share the same timestamp position. Keep the original title, project, ETA, bar, percentage, and dismiss control positions relative to one another.

The footer gives the complete relative phrase its own reliable space. It does not compete with ETA or restrict a two-line title. No badge, divider, or icon is needed: the quiet text reads as item metadata. The mint progress remains the visual anchor.

Grounded in `Sources/ProgressNotifier/ProgressCard.swift`: 350px panel, 10px panel padding, 4px list inset, 6px card gap, 12px/9px card padding, 12px card radius, 13px semibold title with two-line limit, 11px ETA, 5px mint bar, and 38px percentage column. The mockup includes a project card and a no-project card, both with wrapping titles.

## Other placements considered independently

1. **On the ETA line, after a middle dot.** Very compact and puts both time concepts together. Full phrases exceed the available title column on some no-project cards and longer ETAs, so this needs wrapping or shorter copy; it can also make elapsed age look like remaining time.
2. **Above the title, opposite the project name.** Easy to scan near item identity and potentially no extra height on project cards. Competes with project names and the dismiss area, needs a new top metadata row for no-project cards, and reduces width for long project names.

The footer is the most stable of these three at 350px. The cost is 19px extra height per item (6px gap + 13px line), so fewer entries fit before scrolling. It is also a lower-salience location and requires a slightly longer eye movement to associate age with the title.

## Validation and limits

Validated with T3's headless browser at 390px and 350px viewport widths. The panel measured exactly 350px; both titles wrapped to two 16px lines; both progress bars measured 5px; no child crossed the panel's horizontal bounds; both full timestamp phrases fit. Visual inspection confirmed separate ETA and age lines, unobstructed dismiss controls, and matching footer alignment. The page contains these read-only console checks for repeatable layout validation. Total rendered page height was 365px, including the presentation background's padding.

This is a static placement mockup: relative strings are frozen examples of time since **first addition**, not since the last update. Buttons are visual only. CSS blur approximates SwiftUI `regularMaterial`; real vibrancy, SF Symbols, SF Rounded percentage rendering, accessibility settings, localization, and screen scaling need native validation. Compact mode is intentionally absent. An implementation should use the first-added date and the existing expanded `TimelineView`; it should preserve that date across progress updates.
