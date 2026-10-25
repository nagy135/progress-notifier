# B — age as an item footer

Open `index.html` directly in a browser. It has no dependencies or network requests. Extract `.progress-panel` plus its styles for the combined comparison.

The chosen placement is a left-aligned, 10px secondary-text footer **below the progress bar**, inside each expanded item: “Added 5 minutes ago”. It uses the full item content width, including for tasks without a project. It represents time since first addition, not time since the latest update.

This preserves the current project → title → ETA hierarchy and the existing 5px mint bar with right-aligned percentage. Long titles retain their two-line allowance; neither title nor ETA loses horizontal space. A dedicated footer clearly separates historical age from remaining time. The mock follows `Sources/ProgressNotifier/ProgressCard.swift`: 350px panel, 20px corner radius, 10px panel padding, 4px list inset, 6px item gaps, 12px horizontal / 9px vertical item padding, 13px semibold titles and 11px ETA.

Three candidates considered independently:

1. **Below the bar — chosen.** Reliable width, stable alignment across project/no-project entries, and easy to scan as the last detail in each item. Adds 18px per item (5px gap + 13px line), so fewer entries fit before scrolling. Age is less immediately visible than near the title.
2. **Immediately below ETA, aligned with the title.** Groups time-related information and keeps the bar last, but two adjacent time lines can be mistaken for competing estimates. The no-project icon also narrows the age line.
3. **Right of ETA on the same line.** Saves height, but full “Added 47 seconds ago” wording competes with ETA at 350px, particularly with the no-project icon and dismiss button. Wrapping would make row heights inconsistent; truncation would obscure the new information.

Validation: rendered with T3 HTML Preview at 390px and 360px viewport widths. Both report an exact 350px panel, two items, both titles occupying two lines, zero horizontally overflowing descendants, and both full age labels visible. Visually inspected the previews: title, ETA, dismiss controls, percentage and footer fit without collisions. The page content height is 357px including the 60px presentation padding. Python's standard-library HTML parser also verified balanced elements, unique IDs and no external resource elements. No app/source changes are included.

Limitations: HTML approximates macOS regularMaterial and SF Symbols; native SwiftUI rendering may differ slightly. Fixtures are static, expanded-only, and controls are visual examples. Native implementation should derive age from the immutable first-added date, preserve it across updates, and use the existing timeline to refresh the text. Localized age strings may need a wrapping line; this design has full-width space and no fixed item height.
