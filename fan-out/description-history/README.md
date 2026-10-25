# Description history: three design proposals

Open `comparison.html` for the combined interactive review. The page is self-contained
and may be opened directly. D or the global controls unfold every task in all three
previews. The update and long-note buttons exercise arrivals and text wrapping.

- **A — Timeline:** `review-a.html`, based on `a/index.html`. Explicit chronological
  rail, description/timestamp labels, count below the latest note. Clearest narrative;
  uses the most vertical space.
- **B — Compact stack:** `review-b.html`, a parent refinement of `b/index.html`.
  Removes the rail, places times beside descriptions, and keeps count beside ETA.
  Densest option; historical rows have less separation.
- **C — Time ledger:** `review-c.html`, based on `c/index.html`. Separate timestamp
  column and ruled rows. Strongest time scanning and a stable count near task metadata;
  long descriptions have slightly less width. Recommended for this request.

All three original independent attempts and their API notes remain in `a/`, `b/`,
and `c/`. Review copies remove the desktop test bench, fix the simulated screen
budget so iframe resizing cannot affect it, and bridge comparison controls. No
production Swift, API, client, tests, state, or installed app were changed.

## Proposed API

Add optional `description` to the existing `POST /items` body, preserving stable
`name` identity and project metadata. Store each description together with the same
request's percentage, a server timestamp, and deterministic arrival order. Default
shows the latest note and retained-update count. D reveals all saved notes across
tasks, newest first. Each bar reflects its recorded percentage, even if progress
later decreases. An omitted description must keep existing clients compatible.

The independent proposals agree on suppressing consecutive identical description /
percentage pairs, retaining notes across completion/recall, and distinguishing live
progress from an older note's recorded progress. Proposed retention and string-length
limits differ and are still product/implementation decisions.

## Parent verification

Rendered the combined page using T3 `html_preview` at 728px/light and 360px/dark.
Browser assertions checked unfolding in every variant, invariant top/right edges,
newest-first fixture order, count increment from 3 to 4, arrivals preserving unfolded
state, long-text containment, no clipped historical bars, and page horizontal overflow.
No assertion errors were reported. For deterministic structural checks only, animation
frame callbacks were advanced to completion. Native animation and integration remain
future implementation work, after a design is selected.

The live collaborative browser inspector timed out twice; rendered HTML checks were
used instead. Agent-level static/syntax checks are recorded in each original README.
The inline review approximates macOS material, uses fixed fixture times, and does not
exercise production keyboard focus, persisted preferences, native scrolling, or actual
screen-reader behavior.
