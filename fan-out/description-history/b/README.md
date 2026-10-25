# Margin ledger

An independent design proposal for Progress Notifier. Prototype only; no production changes.

## Rationale

Keep the existing native panel’s quiet grey material and mint progress. A fine vertical rail makes the new information read as successive observations of **one task**. The latest note carries the strongest bar and percentage. Earlier notes use thinner, muted bars without becoming separate task cards. Task titles, project labels, ETA and dismiss actions remain familiar.

The prototype shows the exact two-task comparison fixture. Outside the panel, a small test bench provides arrival, long-note, reset and reopen controls. These controls are presentation scaffolding, not proposed app chrome.

## Layout tokens

- Panel: 350 px/pt reference width; 370 outer including 10 shadow padding each side. Top-right fixed at desktop sizes. 20 radius, 14 horizontal padding.
- Task cards: 12 radius, 11 horizontal / 10 top padding; 8 gap. Translucent white over grey material.
- Colors: grey panel `#e7eae9`, primary `#262d30`, secondary `#646d70`, mint `#3bb8a3`, mint text `#237a6c`, history rail `#cbd1d0`.
- System font: 17/600 panel title, 13/600 task title, 12/17 note text, 10 project/time/ETA. Percentages use tabular digits.
- Latest bar: 5 high. Older bars: 3 high. Each bar has the same available width and represents the task’s overall percentage at that timestamp.
- Note rail: 1 wide, small mint latest dot, muted historical dots. No numbered steps or subtask checkboxes.

## Collapsed and expanded behavior

Default: project, title, latest described update with its timestamp, current percentage and progress bar. ETA sits in the footer at left; **“3 updates”** sits at right. The count includes the latest described snapshot, not just hidden rows. There is no two-line truncation of the note: long text wraps at a fixed width.

**D** globally toggles history for every task. The panel footer’s **Show updates / Hide updates** button is the visible equivalent. A task’s count button invokes the same global toggle; its accessible name explicitly says so. D ignores repeats, modifier chords and editable controls. Unfolded notes appear newest first, directly below the latest note. Every row includes description, timestamp, its own proportional bar and percentage. The latest row is shared between collapsed and expanded views rather than duplicated.

The footer changes from “Latest notes” to “Newest first.” The panel and all task histories animate from one requestAnimationFrame clock using measured heights. Widths remain fixed; there is no scale animation or intermediate text wrapping. Reversing D mid-animation restarts from current rendered heights. The top/right edges stay fixed; growth moves downward. Scrolling activates only when the stack exceeds the available screen height. Reduced motion snaps to the final dimensions. Desktop anchoring becomes normal document flow on narrow screens so the test bench remains usable.

M/H/C/Q/Esc behavior belongs to the existing application and is not implemented in this focused prototype. In the native implementation, preserve those bindings. D should retain its global state through M compact/expanded changes; compact mode can remain the existing 220 pt presentation and reveal the selected history state on expansion.

## Data and API recommendations

Keep `name` as the stable identity and existing fields unchanged. The displayed title is still `name`. Add an optional `description` on `POST /items`. This is an additive proposal; the current app does not implement it.

```json
{
  "name": "Smooth history transitions",
  "project": "progress-notifier",
  "progress": 85,
  "etaSeconds": 120,
  "description": "Pinned the panel to its top-right corner"
}
```

Proposed CLI spelling (documentation only, not executed):

```sh
./scripts/progress-notify 'Smooth history transitions' 85 120 \
  --project progress-notifier \
  --description 'Pinned the panel to its top-right corner'
```

Recommended semantics:

- A nonempty trimmed description creates a snapshot `{id, description, progress, recordedAt}` retained with the task. Generate timestamp and stable snapshot ID on the server; use receipt sequence to break timestamp ties. Sort by time, never by percentage. Progress can go backwards.
- Consecutive identical `(description, progress)` pairs are retries: do not append, increase the count or refresh the original snapshot timestamp. ETA/project updates still apply. Same percent with a different description and same description at a different percent are new snapshots. Nonconsecutive repeated content is a new observation. For stronger retry guarantees later, add an optional client event ID.
- Omitted, null or whitespace-only descriptions append nothing and clear nothing. Old clients keep working; the current progress and ETA still update. A task with no descriptions retains its existing progress-only layout, with no rail, note, or count. D leaves that task visually unchanged.
- Persist snapshots with their task, including completion/recall. Decode older stored tasks with an empty snapshot array. Do not confuse this per-task update history with the registry’s existing completed-task history.
- If an undescribed update advances current progress beyond the last described snapshot, collapsed mode keeps the latest note and shows current progress. In unfolded mode, show a separate compact **Current progress** bar above the timeline, and give every described snapshot its original recorded percentage. This avoids assigning the current percentage to an older note. This edge presentation is specified here, not exercised in this fixture.
- Validate description length (suggest 1,000 characters after trimming); reject invalid input explicitly. Retain the full description, wrap naturally, and provide the full timestamp via native help/accessibility while displaying relative age.
- Do not silently cap retained notes in the first implementation; establish a persisted retention policy explicitly if needed. The count must match notes actually available to unfold.

## Arrival behavior

**New update** prepends a described snapshot to the first visible task. **Add long note** does the same with a long wrapping description. Existing notes remain in arrival order; count and live percentage update immediately. Closed history stays closed; open history stays open. Card and window heights grow smoothly. Repeated arrivals demonstrate the screen-height cap. The prototype keeps task ordering stable and does not manufacture additional independent task meters.

For the native implementation, preserve the user’s reading position when scrolled into older history: anchor the visible snapshot ID and offer a small “New update” affordance to return to the top. At the top, keep the newest row visible. The prototype uses browser scrolling and does not implement this older-row anchoring policy.

## Preview

Open `index.html` directly in a browser, or serve **this folder** with any local static file server. No build step, network assets or third-party libraries. Use D or the panel footer to unfold. Try rapid D reversals, the long note, multiple arrivals, a short viewport and the operating system’s reduced-motion setting. Reset restores the comparison fixture.

## Validation and limits

Performed cheap static validation: Python HTML parser checked unique IDs, required controls and both task fixtures; JavaScript extracted from the HTML passed `node --check`. Checked that the file contains no external scripts, styles, network requests or scale animations. Only this assigned folder was written.

No browser rendering or interaction verification was performed. Browser material is an approximation of AppKit regularMaterial; SF rendering depends on the host OS. The prototype uses fixture ages and simulated arrival values, not a live API or clock. It does not test native window rounding, accessibility integration, completed-task recall, compact mode, persisted data, or screen-reader announcements beyond basic HTML semantics. Its animation is a design demonstration, not a replacement for the app’s shared native animation clock.
