# B — Chat spine

Recommendation: one uninterrupted vertical spine per linked chat. Main runs are nodes in oldest-to-newest creation order. Each owning run's delegates sit immediately below it on an indented branch, with elbows, a Child label and a quieter violet bar. The next main run returns to the spine. Two completed main runs appear above the current main run, never in a detached bottom history section. Expanded and compact mockups show exactly the same six tasks.

Expanded: 350 px, a project heading per chat, slender spine, individually selectable main cards; completed cards use a shallow title/time/check layout. Selecting a completed card or D exposes its usual details and ledger. Active main keeps its note and ETA. Child cards indent 14 px; role is conveyed by label and shape, not color alone. Compact: 200 px, title-free bars; completed rows retain checks, children retain elbows and indentation. Separate chats have a gap and divider. Do not roll percentages up: a parent can be coordinating rather than computing child progress.

## Ordering and lifecycle

- Group by the existing exact `(t3Thread.environmentId, t3Thread.threadId)`, never project or title. Unlinked items stay independent blocks, even with identical projects. A fork has its own chat destination.
- Build one deduplicated visible list from active records and revealed completed records, keyed by existing item UUID. Sort each chat's main runs by `createdAt` ascending, then existing UUID for timestamp ties. For legacy missing dates, place undated roots first and preserve their snapshot encounter order; do not fabricate timestamps. Each main run is followed by its descendant subtree, siblings in creation order. Parallel children do not become sequential main nodes.
- Keep chat-block order stable using each block's earliest known creation date among retained active/history records, oldest first, with environment/thread as tie-break. Hidden history may anchor position but is never rendered automatically. Do not sort by latest progress or ETA; a completion must not jump. New blocks append in normal operation. History pruning can change anchors at the retention boundary, a bounded tradeoff.
- Preserve current visibility rules: success is immediately visible history; C hides all completed rows; H reveals one result newest-completed-first, but inserts it into its chronological location. Relaunch keeps completed history hidden. No silent history recall just because a new run shares a chat. Thus “above the newer run” applies to visible/explicitly recalled history. The mockup assumes the two earlier successes have not been cleared.
- A child arriving late stays attached to its declared owner, even after a follow-up begins. Completing a parent never completes or hides its children. Do not invent “waiting” states from a zero ETA.
- If a parent is hidden/deleted/evicted or has not arrived, preserve the child under a noninteractive “Parent run not shown” branch in that chat, ordered by the child's creation. Never reparent it to the newest main run or reveal a suppressed parent. Legacy child markers without a parent link get a separate “Other delegates” branch. A child-only group remains visibly a branch.
- Up/Down and J/K traverse the flattened rendered task order, including completed rows and children; headings/connectors are not focus stops. Keep selection by item UUID during insertions, completion and reordering; if removed, select nearest surviving row. Keep selection in view only as required, not on every background update. D/Shift+D retain ledger semantics; D on a shallow completed row opens details. M preserves selection, order and connections. Enter/double-click still opens the shared chat. X/Z and undo affect only the selected task, never the whole subtree. C/H and history disclosure must not flash or replay completion sound. Scroll only at the screen-height limit, retaining the current shared geometry clock and Reduce Motion behavior.

## Minimum reliable metadata

`t3Thread` already supplies chat grouping, and `isChild` already supplies role. Neither says which main run launched a child. Creation-time inference fails when children finish late or main runs overlap. Names are reusable after completion; do not use names as parent keys.

Propose **optional `runId` and `parentRunId` UUID strings**. Each agent generates its own runId once and keeps it stable; a child copies its immediate parent's runId into parentRunId. Sequential main runs use new runIds with no parentRunId, including follow-ups in the same chat. Nested delegates receive their immediate parent's ID. No new chat ID, project grouping ID, run sequence, provider thread ID, title field or aggregate progress is needed. The existing server item UUID remains presentation/history identity; caller-generated runId is an external relationship handle available before a POST succeeds. Reusing the server UUID instead is possible, but requires an initial response capture and a running app before delegation; the skill deliberately supports an absent app.

Keep name-based update routing and name suppression for compatibility; runId is relationship metadata, not a new addressing mode in this proposal. Stable unique task names remain mandatory. IDs do not fix existing same-name concurrent-run collisions. Adding identity-based routing is a separate migration.

## Backward-compatible API/client proposal

Example main POST:

```json
{"name":"Design chat grouping","progress":62,"etaSeconds":120,"t3Thread":{"environmentId":"mac","threadId":"chat-a"},"runId":"29a2ae84-e1bc-4c4a-a554-49854d59f511"}
```

Example child adds `isChild:true`, its own runId, and `parentRunId:"29a2ae84-e1bc-4c4a-a554-49854d59f511"`. Retain the same t3Thread destination. Encode/decode optional fields in updates, saved items, deletion/closure snapshots and history; include them in GET /items when present. Old payloads and old state decode unchanged; old servers can ignore unknown JSON fields.

Validate UUID shape, reject self-parenting and cycles among retained records, reject a known parent's different chat destination, and reject explicit `parentRunId` with `isChild:false`. Allow unknown parents for out-of-order delivery. Parent-linked new requests should include `isChild:true`; omission of relationship fields preserves existing values. First assignment of runId/parentRunId is allowed on a legacy active item, then immutable within that run (conflicting assignments return 409). Explicit duplicate runId on a different retained item also returns 409; clients generate fresh UUIDs for independent runs. A new item inherits neither relationship from a prior same-name result. For unresolved references, render a detached branch; revalidate when the parent arrives, and reject an incompatible parent registration. A parentRunId without runId is invalid. Existing --no-child correction stays available for unparented legacy cards; linked misclassification needs an explicit future correction operation rather than silently breaking the tree.

CLI: add `--run-id UUID` and `--parent-run-id UUID`, validate before network I/O, include only supplied fields, reject use in health/list/dismiss modes. Require `--child` with an initial `--parent-run-id`; later updates may omit all immutable metadata. Keep current three positional arguments, silent absent-app behavior and --child/--no-child. Update both `scripts/progress-notify` and `skills/progress-notifier/scripts/progress-notify` together. No network or T3 discovery is needed to mint a UUID.

## Proposed skill amendments (text only)

Replace “name is the grouping key” with “name routes updates to one run's ledger; the shared T3 destination groups visible runs into a chat; explicit run links place delegates.” Keep stable unique titles and all milestone/completion rules.

Add: “At initial notification generate one random UUID for --run-id and remember it for the entire agent run. A follow-up starts a new run ID even in the same chat; a milestone continues the same card. Do not use the chat ID as a run ID. When spawning a child, pass your run ID as its --parent-run-id, the resolved chat destination and real project metadata. The child generates its own --run-id and passes that ID to its own children. Every child still sends --child. Never infer a missing parent from titles or newest task. Without explicit parent metadata send --child only; the UI shows an unassigned delegate branch.”

Document chronology, C/H insertion behavior and shallow completed rows. Do not promise automatic recall. Parent briefs must transmit IDs explicitly, including native agents without T3 tools.

## Evidence from this checkout

- `Sources/ProgressNotifier/ProgressModel.swift:9`: displayItems concatenates non-completing active items with recalled history; no chat ordering. `:126–135`: one completion feedback, then retire after 1.25 seconds, preserving history identity. `:83–96`: GET returns role and t3Thread but no existing item UUID.
- `Sources/ProgressCore/ProgressRegistry.swift:76–92`: existing UUID, optional createdAt, completedAt, t3Thread and isChild. `:260–292`: name routes updates, metadata omission preserves values, history inserts newest-first, new items append with new UUID. `:233–248`: H newest-first reveal and C clearing. `:279`: 200-result retention.
- `Sources/ProgressNotifier/ProgressPresentation.swift:69–98`: input order becomes rows with UUID-based reuse and focus fallback; this is where a grouped visible projection should feed presentation. `:100–111`: current shared-chat symbols only, four symbol slots; spatial grouping removes reliance on symbol capacity. `:136–145`: navigation follows desiredItems. `:49–67`: existing 350/200 width interpolation and screen-limited scrolling.
- `Sources/ProgressNotifier/ProgressCard.swift:255–259` and `:361–373`: existing expanded Child badge, compact bent arrow and shared-thread symbol; role exists but is not ownership. `:244–273`: every item currently renders full details; shallow completed summaries are a deliberate additional visual behavior.
- `Sources/ProgressCore/T3ThreadReference.swift:3–20`: exact Hashable destination includes environment and thread, validated; suitable existing grouping key.
- `Sources/ProgressNotifier/App.swift:84–121`: current keyboard bindings should remain. `Tests/ProgressNotifierTests/ThreadGroupTests.swift:28–47`: four symbol slots and overflow; `:50–64`: visible history already participates in thread marking.
- `scripts/progress-notify:26–38,67–74` and matching skill client: existing name positionals, child flags and T3 payload. `skills/progress-notifier/SKILL.md:12–39`: stable name/ledger contract; `:43–78`: parent chat resolution plus child role; `:90–94`: parent briefs currently pass destination, not owning run; `:143–157`: history and per-item close/delete contracts.

## Tradeoffs and suggested acceptance checks

The spine adds a little horizontal cost and completed rows consume vertical space; shallow summaries offset this. Within a chat chronology wins over active-first placement, so the current main may be below history. Explicit run links require parent briefs to carry two extra flags, but resolve real ownership rather than guessing. Maintaining immutable external handles adds validation complexity without changing existing name routing. Deep trees should cap visual indentation after two levels while keeping elbows and an accessible full ancestry label.

Before implementation delivery, cover shuffled arrival order, late child across follow-ups, overlapping mains, missing/hidden parent, same project across chats, >4 chats, nil-date legacy state, C/H and relaunch, completion no-jump/no replay, stable focus while inserting history, narrow/compact transitions and name-based delete/undo. Then run the repository's required Swift/Python checks and build. This design task changed artifacts only; no app/client/skill edits, builds, runtime tests, commits or deployment were performed.
