---
name: progress-notifier
description: Show and update floating progress cards in the local Progress Notifier macOS app when the user asks for progress notifications or invokes progress-notifier. Accepts a task name, percentage, ETA, and optional description, T3 project name and icon; flashes on updates and completes with sound.
---

# Progress Notifier

Use the bundled `scripts/progress-notify` client on the Mac (requires Python 3). It sends updates only when Progress Notifier is already running. If the app is stopped or unavailable, the client silently succeeds without sending anything. Do not launch, build, install, retry, or ask the user to start the app as part of reporting progress. The user chooses when to open `/Applications/Progress Notifier.app`.

## One run, one task group

Create **one task/card for the agent's run** and use its **exact same `name` on every
update**, from the first update through completion. That name is the grouping key:
all descriptions and recorded percentages are stored under that one task. The project
label is display metadata; it does not group different task names into one ledger.

Choose a stable task title describing the whole job, unique among concurrent agents.
Do not rename it to the current phase, create a new task for each milestone, or put
changing milestone text in the name. Keep `--project` and its icon consistent. Put
what just happened in **`--description` on every agent progress update**, including
the initial update and completion. Revise the percentage and seconds remaining as
work advances. Missing descriptions are supported for legacy clients, but agents
following this skill should always provide one.

```sh
~/.agents/skills/progress-notifier/scripts/progress-notify 'Build release' 0 180 \
  --project 'progress-notifier' --description 'Preparing the release build'
~/.agents/skills/progress-notifier/scripts/progress-notify 'Build release' 45 90 \
  --project 'progress-notifier' --description 'Compiled the app; running tests'
~/.agents/skills/progress-notifier/scripts/progress-notify 'Build release' 100 0 \
  --project 'progress-notifier' --description 'Tests passed and the release is ready'
```

These commands update **one card**, producing one newest-first ledger with three
saved description/percentage entries. `name` stays `Build release`; only description,
progress, and ETA change. Parallel runs use different stable names so their ledgers
do not overwrite each other. Percentages may be fractional. ETA is **seconds remaining
at this update**, not a timestamp or total duration. The app counts it down but never
fabricates progress or completes a task when the ETA expires.

When running in a T3 thread, use the thread's actual project name and icon. Discover the current project ID with `t3_thread_list`, then read it with `t3_project_read`. Pass its `title` as `--project` and its non-null `projectIcon` object as JSON with `--project-icon`; do not invent an emoji. When `projectIcon` is null, omit the flag: the app generates T3's default project monogram and color. Outside T3, use the known project name and omit the icon unless supplied. Keep the task title concise; the project appears in its own heading above it. Names must still be unique across concurrent tasks.

```sh
~/.agents/skills/progress-notifier/scripts/progress-notify 'Build release' 20 120 --project 'progress-notifier' --description 'Prepared build inputs'
~/.agents/skills/progress-notifier/scripts/progress-notify 'Check Nix config' 40 60 --project 'nix-darwin' \
  --project-icon '{"kind":"lucide","name":"snowflake","color":"blue"}' \
  --description 'Checked the host configuration'
```

The API fields are `project` and `projectIcon`. T3 icon shapes are `{"kind":"emoji","emoji":"🎹"}`, `{"kind":"lucide","name":"snowflake","color":"blue"}`, and `{"kind":"monogram","text":"PN","color":"violet"}`. Omitted metadata is preserved on later updates, including completion. Send `--project ''` to clear both fields. Old clients and saved items remain supported. Every update flashes its card, even if only the ETA changes; compact bars flash individually. Reduce Motion disables scaling.

Send a short `--description` at meaningful milestones to say what just happened:

```sh
~/.agents/skills/progress-notifier/scripts/progress-notify 'Build release' 45 90 \
  --project 'progress-notifier' --description 'Compiled the app; running tests'
```

The API accepts optional plain text descriptions (up to 2,000 characters; newlines and tabs allowed); agents must include one as described above.
Each is saved with that request's percentage and server timestamp. Consecutive identical
description/percentage pairs are deduplicated. Omitted or blank descriptions preserve
existing notes and add no entry; progress and ETA still update. The card shows the latest
note and the number of earlier descriptions (excluding the current note). The arrow/count is hidden when there are no earlier descriptions or when the ledger is unfolded. Up/Down or K/J selects a task (Down/J next, Up/K previous).
D unfolds the timestamp ledger for the focused task only, newest first, with a recorded
percentage and bar for each note. Shift+D opens all tasks with earlier descriptions;
if all are already open, it folds them all. In that mode, D toggles only the selected
task and moving selection preserves the other ledgers. With a single ledger opened
using D, moving selection switches the ledger to that task and folds the others.
Both D and Shift+D expand compact mode. A mint outline marks the selection. Navigation
keeps it visible; background updates do not change which task is selected. The latest 200 notes per task persist
through relaunch and H recall. `GET /items` returns `description`, `updateCount`, and
`updates` (id, description, progress, recordedAt). The API `updateCount` includes the current note; the on-card arrow excludes it. Do not treat the notes as separate tasks.

Report meaningful milestones while the requested work runs. Use honest estimates; revise them as new information arrives. Send `100 0` only when the work actually succeeds. This plays the macOS Glass sound, flashes and enlarges the card, and keeps it visible as completed history until the user clears it with C or dismisses it. Do not automatically dismiss successful results. The active API entry retires after the brief feedback phase, so the same name can be used for a new run while its completed record remains visible. C hides completed records without deleting history; H can recall them. Like other recalled history, completed records are hidden on app relaunch. On failure or cancellation, dismiss the card and explain the outcome in chat; do not signal success.

```sh
~/.agents/skills/progress-notifier/scripts/progress-notify --list
~/.agents/skills/progress-notifier/scripts/progress-notify --dismiss 'Project · Build release'
~/.agents/skills/progress-notifier/scripts/progress-notify --health
```

Delete the selected item with **Z** or `--dismiss`. Its existing task name stays suppressed until **Shift+Z** undoes the deletion: all later updates, including 100% and a new run with the same name, are discarded. No new identifier is needed. Undo restores the original item and its notes, then accepts future updates again; it does not replay discarded updates. Deletions form a persistent stack, undone newest first, including across relaunches. Use another unique task name for an independent run if an earlier task remains deleted. Z deletes the selected task in either mode; compact mode marks it with a trailing dot. Shift+Z expands and selects the restored item. Holding Z or Shift+Z does not repeat. Deleting a completed history result also removes that record from recall until undo; updates for its name remain suppressed. C and H do not undo deletions. Name-based dismissal targets an active run first, otherwise that name’s visible completed records.

**X** and the on-card close button hide an item without banning updates or adding to the deletion stack. The next accepted update restores the same task with its progress and notes, including completion updates. Closed active cards stay hidden across relaunch until an update arrives, remain listed by `GET /items`, and still count toward the 50 tracked-item limit. Closing a completed result preserves it for H recall. **Shift+X** restores the last closed item from its own persistent stack, independently of the Z/Shift+Z ban stack, and expands the panel to select it. The card close button also adds to this close stack. An update or H recall that already reopens a card removes its close entry; Shift+X restores the next still-closed item. X works in either mode; neither X nor Shift+X repeats while held. The window’s close button still hides the whole window.

Q, ⌘W, or the window's X hides the window while the app keeps receiving updates. Updates do not reopen a hidden window. Opening the app again restores the current items. Click anywhere except an X, or press M, to toggle between the full list and a compact list with an icon and title-free bar for each item, without a header. Compact rows use the project icon, or a task-name monogram when there is no project metadata. With no items, the expanded window says “No progress”. Items and dismissals are saved across quitting/relaunching. The app automatically shows completed results as history and saves the latest 200 across relaunches. With the panel focused, H recalls one result at a time, newest first, and expands the panel; C hides all completed results and resets H to the newest result without deleting history or affecting active tasks. Recalled cards stay until cleared or individually dismissed and do not replay completion effects. History can also be recalled and cleared from the menu bar menu; it stays hidden after relaunch. `GET /items` lists current tasks only, excluding recalled history. Use the menu bar's Quit or ⌘Q to stop the app entirely; later skill calls silently skip until the user opens it again.

The API is `http://127.0.0.1:8766`, local to the Mac running the app. For direct clients:

```sh
curl --fail --silent --show-error http://127.0.0.1:8766/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"Project · Build release","progress":30,"etaSeconds":120,"description":"Compiled the app; running tests"}'
```

`GET /items` lists tracked items (including while the window is hidden); `DELETE /items?name=URL_ENCODED_NAME` dismisses one. No authentication is needed for local processes. Requests from web page origins are rejected. Do not expose or proxy this API to the network as part of sending progress. A stopped or unavailable app needs no chat warning; continue the user's work. For explicit diagnostics only, `--health --require-running` returns an error when unavailable.
