# Progress Notifier

A small native SwiftUI macOS app that waits for local clients to send progress. Floating cards match the style of Usage Notifier: translucent material, mint progress bars, rounded corners, and a draggable panel at the top right across Spaces.

## Build and run

Requires macOS 13+ and Apple Command Line Tools (Swift 5.9+). No third-party dependencies.

```sh
git clone git@github.com:nagy135/progress-notifier.git ~/Code/progress-notifier
cd ~/Code/progress-notifier
./scripts/build.sh
open 'build/Progress Notifier.app'
```

Opening the app shows a floating panel and a menu bar icon. With no items it says “No progress”. Drag its background to move it. The panel grows with its content until it reaches the available screen height; only then does the stack scroll and show a scrollbar. Recalling, clearing, dismissing, and adding cards use the same smooth resize as mode changes, including when a transition is reversed. Click a task to select it; double-click it to open its linked T3 Code thread, even while the panel is inactive. Click the panel background, or press M, to toggle between the full list and a compact list of icons and minimal progress bars, without a header or titles. Compact icons match the item's project icon; items without project metadata use a task-name monogram. The panel has no hover tooltips. A mint outline indicates that the window has keyboard focus in both modes; expanded mode also adds a focus tint. Compact mode marks the selected task with a small dot after its progress bar, matching the bar’s color; the dot dims when the window is inactive. Light mode uses a mostly opaque white surface, darker teal progress bars, and a subtle panel outline in both modes so dark backgrounds do not wash out the content. Focus another app to release keyboard focus. Press `.` to move the panel to the bottom-right corner and grow upward; press it again to return to the default top-right corner and grow downward. Each press snaps it to that corner of its current screen, even after dragging, and the chosen corner is remembered across launches. Press `,` to move to the next connected monitor, wrapping back to the first after the last. It keeps the chosen top/bottom corner and adjusts the scrolling limit to that monitor; with one monitor, it stays in place. Holding either position shortcut does not repeat it. The panel grows and shrinks from its chosen corner in a 0.22-second transition, keeping the same close button, icons, and progress bars throughout. Switching modes does not flash items. Reduce Motion switches layouts immediately. Q, ⌘W, or the window's X hides the window while updates continue in the background. Updates keep it hidden until you open the app again or choose Show Progress from the menu bar. ⌘Q or the menu bar's Quit stops the app. Move the bundle to `/Applications` if desired. It is locally ad-hoc signed, not notarized.

## Send progress

Using the included Python 3 client while the app is running:

```sh
./scripts/progress-notify 'Build release' 0 180
./scripts/progress-notify 'Build release' 45 90
./scripts/progress-notify 'Build release' 100 0
```

Supply a project name to show its icon and a small project heading above the task title:

```sh
./scripts/progress-notify 'Build release' 45 90 --project 'progress-notifier'
./scripts/progress-notify 'Build release' 60 45 --project 'nix-darwin' \
  --project-icon '{"kind":"lucide","name":"snowflake","color":"blue"}'
```

`projectIcon` accepts the same object returned by T3's `t3_project_read`: `{"kind":"emoji","emoji":"🎹"}`, `{"kind":"lucide","name":"snowflake","color":"blue"}`, or `{"kind":"monogram","text":"PN","color":"violet"}`. When T3 returns no override, omit the icon: the app generates the same monogram and color from the project name. Lucide SVGs are bundled for offline rendering; their [ISC license](Sources/ProgressNotifier/Resources/Lucide-LICENSE.txt) is included. Refresh them with `python3 scripts/vendor-lucide.py`.

Or use any HTTP client:

```sh
curl --fail http://127.0.0.1:8766/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"Build release","progress":45,"etaSeconds":90}'
```

The three fields are required:

| Field | Meaning |
| --- | --- |
| `name` | Stable item identity; 1–160 characters, trimmed, case-sensitive. Use unique names for concurrent jobs. |
| `progress` | A number from 0 to 100, including fractions. |
| `etaSeconds` | Estimated seconds **remaining now**, from 0 to 31536000. Each update replaces the estimate. |

Optional fields are `description` (up to 2,000 characters, with newlines and tabs allowed), `project` (up to 160 characters) and `projectIcon` (a T3 icon object). Omitted or null metadata stays unchanged on an existing item. Send `project: ""` to clear both. Metadata is saved across relaunches and returned by `GET /items` when present. The item name remains its stable identity; a project heading does not rename it.

Expanded items show their first-added age beside the ETA on the same line, for example “About 4m left · Added 47 seconds ago”. The age refreshes every second and survives progress updates and relaunches. Older saved items without a creation time say “Added earlier”. The ETA counts down independently of progress. Expired estimates say “Finishing soon”; only a client can mark an item complete. Each accepted update briefly flashes and scales its card, including ETA-only and repeated progress values; compact bars flash individually. At 100%, an existing item flashes green, scales up, plays the macOS Glass sound, and stays visible as a completed history record until cleared with C or dismissed with its X. Expanded completed cards show a prominent green checkmark at the top center. Reduce Motion disables the scale effect. Repeated completion requests do not replay the effect or sound. Unknown completions do not create cards.

Press **Z** with the panel focused to delete the selected task. Its existing name identifies it: later updates for that name are ignored, including completion and subsequent progress, until you undo the deletion. Deletion does not cancel the client's work. Press **Shift+Z** to restore the most recently deleted item, with its original position, progress, ETA, and notes; future updates apply again. Repeated undo walks the deletion stack in reverse order. Updates received while deleted are discarded. Holding either shortcut does not repeat it. Z deletes the selected task in either mode; compact mode marks it with a trailing dot. Undo expands the panel and selects the restored task. Both actions are also in the menu bar menu. If all 50 active slots are occupied, undo waits until there is room and leaves the stack intact.

Press **X** or click an item's close button to hide it without banning updates. The next accepted update brings back the same task with its progress and notes preserved, including when that update completes it. Closed active cards stay hidden across relaunch until updated and still appear in `GET /items`; they continue to count toward the 50 tracked-item limit. Closing a completed result keeps it in history for H recall. Press **Shift+X** to restore the most recently closed card and select it. Closes have their own persistent stack, independent of the Z/Shift+Z ban stack; each undo affects only its own stack. If an update or H recall already brought a card back, its close entry is removed so Shift+X restores the next still-closed card. The card close button uses this same close stack. Closing does not add to the Z/Shift+Z deletion stack. Holding X or Shift+X does not repeat. X works in both expanded and compact modes; Shift+X expands the panel and selects the restored task. Both actions are also available in the menu bar menu.

Items and both undo stacks are saved to `~/Library/Application Support/Progress Notifier/state.json` and restored after relaunch. When the last card disappears, the window stays visible with “No progress” unless you hid it. Completed results automatically join visible history; the latest 200 are saved and stay hidden on launch. Press H to recall one completed result at a time, newest first, without replaying sound or flash. Press C to hide completed results without affecting active work or deleting history; H then starts from the newest again. Deleting a completed result also removes it from recall until Shift+Z restores it. Updates for its name stay suppressed until undo, just as with an active task. C and H do not undo deletions. Compact mode is also remembered.

Send a short description of what just happened with a progress update:

```sh
./scripts/progress-notify 'Build release' 25 120 --project 'progress-notifier' \
  --description 'Compiled the app and bundled resources'
./scripts/progress-notify 'Build release' 75 30 \
  --description 'Passed the test suite; checking the installed app'
```

The default card shows the latest description, its timestamp, current progress, and the
number of earlier descriptions as a down arrow and count to the left of the progress bar.
The current description is excluded: two saved entries show a count of one. The arrow
is hidden when no earlier descriptions are available.
The indicator disappears while that task’s description ledger is unfolded. Press **D**
while the panel has focus, or click **Show updates**,
to unfold the ledger for the **focused task only**. Select the next task with Down or
J, and the previous task with Up or K. A mint outline marks selection in expanded mode.
In compact mode, a mint outline and small matching dot after the bar mark selection; Up/Down and J/K
move it just as in expanded mode. Expanding keeps the selected task. Navigation stops at the first and last tasks. Progress updates and
new tasks keep the same selection; removing the focused task selects its next neighbor,
or the previous one when it was last.

Tasks sharing the same T3 environment and thread ID form a chronological timeline.
A rail with downward continuation arrows links main runs; indented purple branches
mark child tasks. This replaces the former four-symbol grouping limit. Visible
completed results join their original timeline position. See Chat timelines below.

Press **Enter** (or keypad Enter) to focus T3 Code and open the selected task's
originating thread, in either mode and for recalled results. The app targets
`/Applications/T3 Code (Beta).app` explicitly so an installed Nightly cannot claim
the link. Double-clicking a task selects it and performs the same action, without requiring prior panel focus or task selection. Cards without a destination are still selectable but do not open T3 Code. The menu bar also has
**Open Focused Task in T3 Code (Enter)**.

Attach the destination on the first update; later updates and completion preserve it:

```sh
./scripts/progress-notify 'Build release' 0 180 --project 'progress-notifier' \
  --description 'Preparing the release build' \
  --t3-environment-id '<environmentId>' --t3-thread-id '<threadId>'
```

Agents get `environmentId` from T3's `t3_environment_read` and `currentThreadId` from
`t3_thread_list`. Delegates follow `subagent` parent relationships to the user-facing
chat and send that thread ID instead; forks keep their own destination. Parents pass
the resolved destination and project metadata in delegate briefs so children can link
their cards even without T3 tools. Separate task names preserve each delegate's
progress; a shared destination groups the cards and supplies the Enter shortcut.
Provider conversation IDs such as `CODEX_THREAD_ID` are different.
The shared skill supplies this metadata automatically for T3 runs. Existing cards
can be linked by sending both flags on their next update. No T3 Code changes or
Accessibility permission are needed for this shortcut.

Each ledger row has a time column, description, recorded percentage, and proportional
bar, with the newest update first. **Shift+D** opens all tasks with earlier descriptions;
when all are open, it folds them all. In this mode, D toggles only the selected task
and moving focus preserves the other ledgers. If any are folded, Shift+D opens all again.
With a single ledger opened using D, moving focus folds the old row and reveals the
newly focused task's history. Keyboard
navigation keeps the selected task in view. D from compact mode expands the panel and
shows the selected task’s ledger; Shift+D also expands compact mode and toggles all ledgers. M preserves selection and the ledger setting; D does not
change H/C completed-task history. Update details start folded after relaunch.

Each described update is a snapshot of the task's overall progress, not a separate
subtask. The latest 200 snapshots per task are saved across relaunches and completed-task
recall. The API’s `updateCount` includes the latest entry and reflects all retained entries;
the on-card arrow counts only the earlier descriptions. New updates are
ordered by server receipt, including when percentages decrease or timestamps tie.
Consecutive identical description/percentage pairs do not add duplicate entries or
change the original timestamp; ETA updates still apply. Omitted, null, or blank
descriptions append nothing and preserve existing notes. Old clients keep updating
live progress; if it differs from the last note's recorded percentage, the card labels
and displays both meters separately. Description text is trimmed, line endings are
normalized, and invalid descriptions are rejected before changing the task.

`GET /items` includes `description` when a latest note exists, `updateCount`, and an
`updates` array in newest-first order. Each update has `id`, `description`, `progress`,
and `recordedAt` (server-generated ISO 8601 timestamp). These are distinct from the
existing completed-task history; recalled completed tasks remain excluded from this API.

The client **never starts the app**. When the app is stopped or unavailable, calls silently succeed without sending or queuing updates. Use `--require-running` for explicit diagnostics; `--no-launch` remains an alias for this strict mode.

## API

The listener binds **only to IPv4 loopback `127.0.0.1:8766`**, using Apple's [Network framework local endpoint binding](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint). It does not listen on LAN or IPv6 addresses. Any local process can send updates; there is no token. Browser-origin requests are rejected and no CORS access is provided.

| Request | Result |
| --- | --- |
| `GET /health` | App name, version, and status. |
| `POST /items` | Create/update an item; returns `{"ok":true}`. Requires `Content-Type: application/json`. |
| `GET /items` | `{"items":[{"name":"Build release","progress":45,"etaSeconds":89.2,"completing":false,"updateCount":0,"updates":[]}]}` |
| `DELETE /items?name=Build%20release` | Dismiss an item without a success sound. Idempotent. |

`GET /items` returns current tasks, including their brief 1.25-second completion phase. Completed results remain visible as history after leaving the active API; retained and recalled history does not appear in the API or block a new task using the same name. `DELETE /items?name=...` deletes an active run and suppresses that name until Shift+Z restores it. With no active run, it deletes that name’s visible completed records individually. Repeated deletes of an absent item do not add stack entries.

`POST /items` also accepts optional `"t3Thread":{"environmentId":"...","threadId":"..."}`;
`GET /items` returns the same object when attached. Both IDs are required together
and accept 1–512 ASCII letters, digits, hyphens, underscores, or colons. Malformed destinations
return 400 before changing the task. Omitted or null destinations preserve the current
link. Links persist through relaunch, completion, recall, close, and undo; a new run
with the same name starts without the previous run's link.

Invalid input returns JSON `{"error":"…"}` with an HTTP 4xx status. Supports HTTP/1.0 and HTTP/1.1, one request per connection, Content-Length bodies up to 16 KiB, headers up to 8 KiB, 50 tracked items, and 64 simultaneous connections with a five-second read timeout. Chunked request bodies are unsupported. Always include Content-Length for POST; curl and the Python client supply it automatically.

```sh
./scripts/progress-notify --list
./scripts/progress-notify --dismiss 'Build release'
./scripts/progress-notify --health --require-running
```

Child/delegate tasks pass `--child` on their initial client update (API:
`"isChild":true`). They show a **Child** badge in expanded mode and a bent-arrow
symbol beside the project icon in both modes. The marker survives omitted fields,
completion, relaunch, and history recall; new runs default to regular tasks.
`--no-child` clears a mistaken marker. Chat navigation still targets the parent
chat, independently of this marker.

## Chat timelines and child ownership

Cards linked to the same `t3Thread` environment/thread pair now stay together.
Main runs are ordered by creation, older above newer, with small downward arrows
on the rail toward the next main run. Children branch underneath their owning run;
late delegates stay with their original owner after another followup starts.
Expanded completed cards become short receipts; D opens their saved details.
Compact mode retains the same sequence, rail and child indentation. Per-task
progress and ETA remain independent; no combined percentage is shown.

The additive API fields `runId` and `parentRunId` are optional UUID strings. Generate
one runId before the initial update and reuse it. Main followups get fresh IDs and
the same chat destination, with no parentRunId. Each child gets its own ID,
`isChild:true`, and its spawning agent's runId as parentRunId. Unknown parents are
allowed; hidden or unavailable parents leave a labeled detached branch. Legacy
children without explicit ownership remain visibly unassigned. Name-based update,
delete and undo behavior remains unchanged; concurrent task names must be unique.
Assigned IDs are immutable; conflicts, duplicate IDs, cycles and known cross-chat
edges are rejected. Old clients and snapshots continue to work. GET /items also
returns item id, createdAt and the optional run relationship fields.

```sh
# Generate once; reuse on every update, including completion.
progress_run_id="$(uuidgen)"
./scripts/progress-notify 'Build release' 0 180 --run-id "$progress_run_id" \
  --description 'Preparing build' --project progress-notifier \
  --t3-environment-id '<environmentId>' --t3-thread-id '<resolvedChatThreadId>'
# A delegate generates its own UUID and receives the parent's UUID in its brief.
./scripts/progress-notify 'Review release' 0 120 --child --run-id '<child UUID>' \
  --parent-run-id "$progress_run_id" --description 'Reviewing release' \
  --t3-environment-id '<environmentId>' --t3-thread-id '<resolvedChatThreadId>'
```

C, X, Z and relaunch keep their existing visibility rules; grouping never recalls
hidden results. H reveals the newest hidden completion and inserts it into its
chat's chronological position. Keyboard selection follows the rendered order and
survives progress updates. Closing or deleting a parent does not hide its children.

## Agent skill

The self-contained skill is in [`skills/progress-notifier`](skills/progress-notifier). Copy that directory into your agent's skills directory. Viktor's shared installation lives in `~/.dots/agents/.agents/skills/progress-notifier` (also exposed at `~/.agents/skills/progress-notifier`). It includes a client and instructions for task naming, ETA updates, successful completion, and cancellation.

## Verify

```sh
swift test
python3 -m unittest discover -s Tests/ClientTests
./scripts/build.sh
open 'build/Progress Notifier.app'
python3 scripts/smoke-test.py
```

The smoke test sends real progress cards and plays one completion sound. It cleans up its own test items. Registry and HTTP parser tests cover dismissal, duplicate completions, stale updates, ETA replacement, invalid input, fragmented requests, and payload limits.
