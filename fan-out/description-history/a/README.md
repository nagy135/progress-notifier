# Margin notes

An independent design proposal for Progress Notifier. Prototype only; no production code, live API, or native app is involved.

The latest note reads as a small margin annotation beneath the task identity. Unfolding reveals a continuous sequence down the same left rail. Every bar describes **one task’s overall progress at a particular time**. The shared baseline and restrained older mint bars make the progression comparable without suggesting independent subtasks.

## Layout and tokens

- Panel: 350 CSS px / native points, plus an external shadow; 20 px outer corners, 14 px inset, 8 px task spacing. The inner task card is 320 px wide with 12 px corners and 12 px horizontal padding.
- Typography: local system/SF stack; 17 px panel heading, 13 px semibold task title, 12/17 px note, 10 px project and metadata, 9 px history timestamps. Percentages use tabular figures.
- Material: translucent mist `#e8ede9`, ink `#283330`, secondary `#626e69`, current mint `#3aab92`, older mint `#80af9c`, track `#cddbd5`. White highlights distinguish the material layers without a heavy outline.
- Description rail: 4 px markers, 1 px connector, 13 px note inset. Each proportional bar is 3 px high, with its percentage aligned at the right. All historical bars have identical available width.
- Count: `3 updates` beneath the latest note, aligned with its text. The count includes the latest described snapshot. Its chevron reflects the global unfold state.

## Behavior

**Default:** project, stable task title, ETA/age, latest description, current progress bar and percentage, compact update count. A long latest description wraps at its final fixed width; it is never squeezed or truncated. Task X hides that task for this local demo; Reset restores it.

**Unfolded:** the latest note stays in place. Earlier snapshots appear immediately underneath, newest first, each with its description, timestamp, bar and percentage. The count moves to the end of the sequence and a quiet “Newest first” label clarifies the ordering. Full note text remains available without a second disclosure.

**D:** toggles history for every task together. The visible History / D button and each update-count button invoke the same global action. D ignores modified shortcuts and editable fields. History intent applies to newly arriving tasks too. No per-task expansion state is proposed.

**Motion:** one `requestAnimationFrame` clock interpolates measured drawer and task heights and derives the outer panel height in the same frame. The right and top edges stay fixed. Text and bar widths stay constant; no scale transforms or intermediate rewrap. Rapid reversals begin from the current measured heights. System reduced motion and the demo checkbox apply the final layout directly. New updates also resize using this clock, with a short color highlight and no scale pulse.

**Screen cap:** content grows until the panel reaches the viewport-height allowance, then the single panel viewport scrolls. Scroll position is preserved on updates; no forced jump to the newest row when reading older notes. A native implementation should preserve the visible snapshot ID and its offset when inserting above a scrolled viewport. The HTML demo preserves `scrollTop`, rather than implementing that full native row anchoring behavior.

**New update:** New update inserts a realistic snapshot at the top of the first task. Long note inserts a multi-line sample. Counts immediately increase; the global unfolded state stays unchanged. Repeated clicks exercise long history and the scroll cap. Reset restores the exact shared fixture.

## Data and API recommendation

Keep `name` as the existing stable task identity; do not introduce a new title-based identity or use the changing description to identify a task. Add optional `description` to the existing request:

```json
{
  "name": "Smooth history transitions",
  "project": "progress-notifier",
  "progress": 85,
  "etaSeconds": 120,
  "description": "Pinned the panel to its top-right corner"
}
```

Store described snapshots per task as `{id, description, progress, receivedAt, sequence}`; use a server-assigned timestamp and sequence for deterministic newest-first ordering. Persist them with their task, including completed-task recall. Display relative times; expose an exact local timestamp through native help/accessibility. The demo uses fixture times rather than a live clock.

- Missing, null, empty or whitespace-only description: update current percentage/ETA as today, append no snapshot, retain previous notes. Old clients therefore keep working. Do not clear notes on omission.
- With no described snapshots: retain the existing current-progress card, show no update count, and add no empty history drawer when D is enabled. This case is specified here rather than adding a third task to the comparison fixture.
- If an undescribed update moves current progress beyond the latest described snapshot, collapsed mode keeps the **current** meter and labels the description `Last note at 85%` with its time. Expanded mode retains a separate current meter above the notes, and each note’s bar uses its immutable snapshot percentage. Never rewrite a historical bar to match current progress.
- Trim descriptions, allow ordinary multiline text, normalize line endings, reject unsupported control characters, and propose a 2,000-character maximum with a clear validation response. Render plain text only.
- Consecutive identical normalized description **and** percentage is a retry: append nothing and preserve the original snapshot timestamp. ETA-only changes still apply. The same text at a different percentage is a new milestone; different text at the same percentage is also retained. Nonconsecutive repeats are new events, unless an optional request idempotency key identifies a transport retry.
- Order by receipt sequence/time, never by percentage: progress can legitimately move backward. A note is a snapshot, not a child task.
- Propose a bounded 200-note per-task retention policy; the count reflects retained notes. If older notes are pruned, expose that fact at the bottom of expanded history. Retention needs a product decision before implementation.

## Preview and validation

Open `index.html` directly in a browser; it is self-contained, with inline CSS/JS, local system fonts and no network requests. No build step or server is needed.

Suggested inspection: D repeatedly and mid-transition; the visible History and count controls; New update in both modes; Long note; repeated additions until scrolling appears; reduce motion; dismiss and reset; resize the viewport. The menu bar and M/H/C hints provide native context; M/H/C themselves are not simulated. Hide panel is demonstrative and Reset restores it.

Performed: Python HTML structural checks for required elements, unique IDs, inline resources and fixture content; JavaScript syntax check with Node; runtime smoke check against a small DOM stub for fixture rendering, global toggles, insertion ordering and count changes. No real browser or native runtime verification was performed. Material blur, exact SF rendering, visual layout and scroll behavior still require parent/browser inspection. Native animation coordination and AppKit screen geometry remain implementation work after a design is chosen.
