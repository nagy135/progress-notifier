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

Opening the app shows a floating panel and a menu bar icon. With no items it says “No progress”. Drag its background to move it. The panel grows with its content until it reaches the available screen height; only then does the stack scroll and show a scrollbar. Recalling, clearing, dismissing, and adding cards use the same smooth resize as mode changes, including when a transition is reversed. Click anywhere except an X, or press M, to toggle between the full list and a compact list of icons and minimal progress bars, without a header or titles. Compact icons match the item's project icon; items without project metadata use a task-name monogram. The panel has no hover tooltips. In expanded mode, a mint outline and tint indicate that the window has keyboard focus; compact mode has no selection or focus tint. Light mode uses a mostly opaque white surface, darker teal progress bars, and a subtle panel outline in both modes so dark backgrounds do not wash out the content. Escape releases keyboard focus while leaving the panel visible. The panel grows and shrinks from its top-right corner in a 0.22-second transition, keeping the same close button, icons, and progress bars throughout. Switching modes does not flash items. Reduce Motion switches layouts immediately. Q, ⌘W, or the window's X hides the window while updates continue in the background. Updates keep it hidden until you open the app again or choose Show Progress from the menu bar. ⌘Q or the menu bar's Quit stops the app. Move the bundle to `/Applications` if desired. It is locally ad-hoc signed, not notarized.

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

Expanded items show their first-added age beside the ETA on the same line, for example “About 4m left · Added 47 seconds ago”. The age refreshes every second and survives progress updates and relaunches. Older saved items without a creation time say “Added earlier”. The ETA counts down independently of progress. Expired estimates say “Finishing soon”; only a client can mark an item complete. Each accepted update briefly flashes and scales its card, including ETA-only and repeated progress values; compact bars flash individually. At 100%, an existing item flashes green, scales up, plays the macOS Glass sound, and stays visible as a completed history record until cleared with C or dismissed with its X. Reduce Motion disables the scale effect. Repeated completion requests do not replay the effect or sound. Unknown completions do not create cards.

Click an item's X to dismiss it. Updates for that name stay silent until its client sends 100%; the name is then available for a new run. Dismissal does not cancel the client's actual work. When the last card disappears, the window stays visible with “No progress” (unless you hid it). Items and dismissals are saved to `~/Library/Application Support/Progress Notifier/state.json` and restored after relaunch. Completed results automatically join visible history; the latest 200 are saved and stay hidden on launch, like recalled history. Press H while the panel has focus to bring back one completed result at a time, newest first; recalling expands the panel and does not replay the sound or flash. Press C to hide all completed results, including any still finishing, without affecting active work or deleting history. H then starts from the newest result again. Each completed or recalled result stays visible until cleared or dismissed with its X. History actions are also available in the menu bar menu. History starts with completions recorded by this version; older discarded results cannot be recovered. Compact mode is also remembered.

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
Compact mode has no borders or selected task, and Up/Down and J/K do nothing there.
Expanding restores the previous selection. Navigation stops at the first and last tasks. Progress updates and
new tasks keep the same selection; removing the focused task selects its next neighbor,
or the previous one when it was last.

Each ledger row has a time column, description, recorded percentage, and proportional
bar, with the newest update first. **Shift+D** opens all tasks with earlier descriptions;
when all are open, it folds them all. In this mode, D toggles only the selected task
and moving focus preserves the other ledgers. If any are folded, Shift+D opens all again.
With a single ledger opened using D, moving focus folds the old row and reveals the
newly focused task's history. Keyboard
navigation keeps the selected task in view. D from compact mode expands the panel and
shows the previously focused ledger; Shift+D also expands compact mode and toggles all ledgers. M preserves selection and the ledger setting; D does not
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

`GET /items` returns current tasks, including their brief 1.25-second completion phase. Completed results remain visible as history after leaving the active API; retained and recalled history does not appear in the API or block a new task using the same name. `DELETE /items?name=...` dismisses an active run, or hides its visible completed records when no active run has that name.

Invalid input returns JSON `{"error":"…"}` with an HTTP 4xx status. Supports HTTP/1.0 and HTTP/1.1, one request per connection, Content-Length bodies up to 16 KiB, headers up to 8 KiB, 50 visible items, and 64 simultaneous connections with a five-second read timeout. Chunked request bodies are unsupported. Always include Content-Length for POST; curl and the Python client supply it automatically.

```sh
./scripts/progress-notify --list
./scripts/progress-notify --dismiss 'Build release'
./scripts/progress-notify --health --require-running
```

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
