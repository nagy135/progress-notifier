# Progress ledger — Design C

A restrained native ledger inside the existing translucent panel. A narrow timestamp column and full-width ruled rows make the sequence legible without introducing nested cards. Every meter records the **same task’s overall progress** at that moment; these are not subtasks. The latest row stays in exactly the same position when history opens.

## Layout and hierarchy

- Panel: 350px wide with 10px shadow allowance on either side, 20px outer corners. Task cards: 322px wide, 12px corners, 12px horizontal / 11px vertical padding, 8px stack spacing.
- Palette: ink `#283330`, secondary `#64706b`, current mint `#399d88`, earlier mint `#7caa9a`, track `#d7e5df`, translucent pale gray panel. Historical bars are quieter but retain exactly proportional lengths.
- System font throughout: title 17px, task title 13px semibold, description 12px with 1.42 line height, project and metadata 10px, timestamps 9px. Tabular percentages and timestamps.
- Snapshot grid: 30px timestamp column, 8px gap, remaining width for note and 4px bar. Full notes wrap at a constant width. No truncation of the long-note sample.
- Count: `3 updates` at the right of the task’s ETA/age line; includes the latest described snapshot. It is a static label, not an individual expansion control.
- Project monograms and headings stay above stable task titles; dismiss affordances remain at the top right. Demo dismiss buttons explain their illustrative state rather than mutating the fixture.

## Collapsed, expanded, and arrival behavior

The default shows each task’s latest note, timestamp, current percentage, and total described-update count. D or the footer’s **Show updates** opens earlier rows for **all tasks together**. The latest row is already the top row, so opening only reveals the earlier rows below. Timestamps are newest-first, never sorted by percentage; progress can legitimately decrease.

The toggle is global and reversible, with an accessible pressed state. D ignores key repeat, modifiers, and text-entry targets. No task-local fold states compete with it. In the eventual native app, handle D only while the panel has keyboard focus, consistent with existing shortcuts. Keep M, H, C, Q, and Escape unchanged; the history preference can remain set while M hides details in compact mode. Pressing D in compact mode should switch to the expanded panel with history shown; subsequent D presses fold history without changing mode.

**New update** inserts a described snapshot at the front of the first task, updates the current meter/count, and preserves whether history is open. The prototype scrolls to the newest update on this explicit demo action. In production, stay at the top when already there; if the user is reading older history, preserve their visible row’s position and show a small “New update” affordance to return to the latest. Do not steal scroll position on background arrivals. Earlier rows retain their recorded percentages and descriptions.

**Long note** replaces the second task’s latest description with a realistic multi-line note. This is a layout demonstration, not a proposed editing action. **Screen-height test** appends older snapshots and unfolds history. **Reset** restores the exact shared two-task fixture. H/C recalled-completion flows are outside this prototype; their snapshot histories should use the same ledger and global visibility setting.

For a task with no described updates, keep the existing title, ETA, age, and current bar; omit the timestamp column, count, and note region entirely. D does not add an empty placeholder. If an old client subsequently sends a percentage without a note, always show that live percentage; retain the latest note and its recorded timestamp. When its percentage differs, label it “Latest note · at 85%” and show the live meter separately, so an old note is never presented as describing an unrecorded percentage. Expanded history then contains the actual saved snapshots unchanged. This mixed-client state is specified here but not included in the fixture.

## Motion and native implementation handoff

One requestAnimationFrame clock interpolates each card’s clipping height and the viewport height over 240ms with a cubic ease-out. Content is always laid out at the final fixed width; only clipping bounds change, so glyphs never scale or rewrap during the fold. Reversal starts from the last drawn heights. The latest summary stays pinned within each card; subsequent cards move with the stack. The panel’s top and right edges remain fixed on desktop. The phone-width preview uses normal document flow for accessibility, rather than pretending to be a native window.

The viewport grows with the sum of card heights until the available height cap, then enables scrolling. A separate slim scrollbar avoids changing content width. Reduce Motion applies final sizes immediately. In AppKit, use the existing shared animation clock and top-right content anchor for row and NSPanel frame changes; do not add competing implicit SwiftUI animations. Native window rounding and focus changes need actual native validation later.

## Proposed data and API contract (not implemented)

Retain `name` as the stable, case-sensitive identity; `project` is metadata. The visible task title continues to come from `name`. Add an optional string `description` to `POST /items` and the CLI:

```json
{
  "name": "Smooth history transitions",
  "project": "progress-notifier",
  "progress": 85,
  "etaSeconds": 120,
  "description": "Pinned the panel to its top-right corner"
}
```

```sh
./scripts/progress-notify 'Smooth history transitions' 85 120 \
  --project progress-notifier \
  --description 'Pinned the panel to its top-right corner'
```

These are proposed examples only; no API requests are made by this prototype.

- Each accepted nonempty description records `{id, description, progress, recordedAt}` on the existing task. Timestamp comes from the server; a monotonic per-task sequence breaks equal-timestamp ties. Persist snapshots with that task across relaunches and completed-task recall.
- Omitted, null, or whitespace-only description creates no snapshot, does not erase prior notes, and does not increment the count. Progress/ETA still update normally. Old clients need no changes; old persisted tasks decode with an empty snapshot list.
- Trim the outer whitespace; propose a 2,000-character limit and reject control characters apart from newlines/tabs. Validate before changing the task. The current sample request size limits still apply.
- Suppress an immediately repeated `(normalized description, progress)` pair, even if ETA changed, so retries do not fill history. Same text at a different percentage is a new snapshot. Different text at the same percentage is a new snapshot. A repeated pair after an intervening distinct snapshot is a new milestone. An optional explicit idempotency key could provide stronger transport retry guarantees later.
- The task’s live percentage is independent of the most recent described percentage. Do not manufacture snapshots for old clients or overwrite an old snapshot’s recorded meter.
- Recommend a dedicated `updates` array rather than overloading the existing completed-task `history` collection. Return snapshots newest-first from GET and preserve their server order; never order by progress.
- Recommend a per-task retention cap of 200 described updates. If trimming occurs, show “200 saved updates” rather than implying a lifetime total. Counts reflect retained rows, including the latest. Completion/dismissal follows current lifecycle rules; this proposal does not change silent dismissed-task behavior.

## Preview and validation

Open `index.html` directly in a browser; it has no build step, dependencies, fonts to download, or network calls. Test D, rapid D reversals, New update both folded and open, Long note, Screen-height test, Reset, short windows, and system Reduce Motion.

Performed static checks: HTML parsed with Python’s HTMLParser, duplicate IDs checked, inline JavaScript syntax checked with `node --check`, and fixture/control/animation hooks verified. No browser or native-app validation was performed. Text metrics, contrast on different desktop backdrops, assistive technology behavior, scroll anchoring on background arrivals, and macOS native frame rounding still need runtime review. Production Swift, API, clients, tests, app data, and sibling proposals were not modified.
