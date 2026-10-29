# Option C — Chat rail

A continuous vertical rail makes each conversation one visual group. Main runs read oldest → newest. Completed mains become short, individually selectable receipts above the active main. Delegates branch below their specific owner with an inset, dashed outline, bent arrow, and explicit role label. Their purple accent is supplementary. Progress and ETA always belong to individual cards; there is no group percentage.

`mockup.html` is standalone and static, showing expanded 350px and compact 200px panels. Scenario: two completed main runs, a current main, two parallel delegates, and another chat in the same project. Theme variables have light/dark fallbacks; neither html nor body sets a background or outer horizontal padding. No scripts, fonts, images, or network dependencies.

## Ordering and presentation

- Group by the complete existing `(t3Thread.environmentId, t3Thread.threadId)` pair, never project or title. Show the project once per group and a short chat suffix (full destination in accessibility text/tooltip). No thread-title fetch is required. Replace the four-symbol grouping scheme with the rail.
- Main runs sort by immutable `createdAt`, ascending; UUID breaks exact ties. Two completed receipts immediately precede the new main in the example. Percentage, latest note, ETA and completion time never change order.
- Each main is followed by its explicitly linked child subtree, siblings oldest-created first. Main chronology and delegation are separate axes. A later main follows the prior main's whole subtree. Children of an older main stay there even if a followup starts; never move them under the newest main.
- Keep chat groups in stable first-appearance order while visible, not most-recent-update order. New unrelated chats append. Recalled rows join the existing group without promoting it. Group ranks are presentation state, not a public API identifier. On relaunch initialize ranks from earliest retained creation time; unlinked cards are standalone groups. Missing legacy dates use a deterministic storage-order fallback and omit the time label.
- Expanded: main receipts are ~36px; active main keeps the current description and meter; children have a ~12px inset and independent meters. Keep the existing 350px width. Receipt D expansion reveals title, timing, latest note and ledger; no loss of saved detail.
- Compact: retain 200px width and ~20px rows. Group icon/chat suffix, continuous rail, done checkmarks, inset child bars and arrows preserve the exact flattened order. Selection gets a thin mint outline in both modes. Hover/accessibility exposes task name, role, percent and destination.
- Nested delegates retain exact parent relationships; cap visual indentation at two levels to protect text width, with the actual parent name in accessible text/tooltip. A child lacking an explicit parent sits in a separately labeled “Delegates · parent unspecified” branch of its chat, never under a guessed main.

## IDs: reuse the card UUID; add only a parent edge

Existing `t3Thread` is enough to group a chat. Existing `isChild` is enough to distinguish the role. Neither identifies which sequential main run owns a child. The model already generates a UUID per run and retains it in history. Expose it rather than introduce `chatGroupId`, `runId`, `turnId`, `sequence`, or duplicate provider-thread identifiers.

Proposed additive contract:

```json
POST /items
{
  "name": "Audit history behavior",
  "progress": 0,
  "etaSeconds": 90,
  "isChild": true,
  "parentItemId": "<owning-card UUID>",
  "t3Thread": {"environmentId": "…", "threadId": "…"}
}

200 {"ok": true, "itemId": "<this-card UUID>"}
```

- Optional `parentItemId` is a UUID stored on ProgressItem and history; omission preserves it on updates. Old snapshots decode it as nil. Return the existing card ID as `itemId` from accepted POSTs and GET /items entries; also expose parentItemId and createdAt in GET. Do not change the active-only scope of GET.
- Parent links are set on the initial update, explicit corrections allowed. Require `isChild:true` when introducing a parent link; reject self/cycles and known cross-chat edges. A main has no parent. Explicit null clears a mistaken edge; `isChild:false` requires clearing the parent. Updating t3Thread must validate the existing edge too.
- Resolve parents against active items and retained history. If an ancestor was evicted, hidden or deleted, preserve the reference and display “Parent unavailable/hidden” in that chat's detached-child section. Never resurrect a hidden parent just to draw a branch. Persisted dangling UUIDs are valid; new unknown UUIDs may also remain unresolved, permitting delayed delivery.
- Keep current name-based update, deletion and suppression semantics. Unique concurrent names remain mandatory. Same-name later runs get new UUIDs and therefore cannot steal old children. No-op deleted/unknown-completion responses keep `ok:true` and omit itemId.

CLI: add `--parent-item-id UUID`, `--clear-parent`, and `--print-id`. Initial main invocation with --print-id writes only the returned UUID; parent captures it and supplies it in each child's brief. Normal output retains JSON. `--print-id` is update-only; if stopped or an older server returns no ID, output is empty and exit remains the current best-effort success. Children omit the edge when no parent UUID is available, retaining --child and the chat destination. No app launch, lookup by name, retries, or guessed parent. Every nested delegate receives its immediate parent's UUID and the same root chat destination.

## Proposed skill amendment (text only)

> Keep the same name throughout one agent invocation. Each user followup starts a fresh card after the prior run completes; a resumed invocation continues its card. Reuse the resolved root chat destination across followups. Different names in a chat remain separate runs and ledgers.
>
> On the initial card, capture its item ID using --print-id when delegation may occur. Include that ID as the progress parent in each delegate brief. Delegates use --child --parent-item-id '<parent card UUID>' on their initial update, capture their own card ID if nesting, and pass their own ID to nested delegates. IDs may be omitted on later updates. If no card ID is returned, continue with --child and the shared destination only. Never infer a main/child relationship solely from matching chat IDs or names.
>
> Earlier visible main cards sit above newer main cards; delegates branch beneath their explicit owner. Creating a new main does not hide previous results or transfer running delegates. Completion reports only that agent's success, not aggregate child success.

## Lifecycle and keyboard

Retain current completion effects once per task, immediate visible completion, 200-record history cap, hidden history on relaunch, and brief active-entry retirement. Completing a child does not complete the main; children may outlive it. A successful followup adds another main node rather than replacing its predecessor.

H still recalls one result newest-first, but inserts that result into chronological position within its chat; it does not append a history block. C hides all completed records, including receipts and completed children, without deleting edges or active children. New runs do not auto-recall records hidden by C/X/Z or relaunch. Thus “earlier above newer” applies to visible history, honoring the user's clear action.

Up/Down and J/K traverse the displayed flattened order, skipping group labels/rails. Selection remains keyed by UUID when completion, recall or children arriving changes geometry. Initial focus prefers an active main, not the oldest receipt; after removal choose nearest surviving row. D/Shift+D keep their current per-card ledger semantics; receipt detail expands as needed. M preserves selection and structure. Enter/double-click opens the same existing root-chat destination for every node. X/Z act only on the selected card; Shift+X/Shift+Z preserve their independent undo stacks. H/C do not undo deletion. Child edges do not imply cascade deletion. Empty groups disappear. Keep the current screen-height cap and scroll selected row into view without background-update scroll jumps. Use existing single-clock geometry and Reduce Motion behavior; flash only the updated card.

## Evidence from independent inspection

| Current behavior | Source |
| --- | --- |
| Active visible items precede recalled completed items, which separates old mains from followups | `Sources/ProgressNotifier/ProgressModel.swift:9` |
| UUID identity, optional creation date, destination, role already persist | `Sources/ProgressCore/ProgressRegistry.swift:76–110` |
| Matching updates uses name, while new cards get UUID and creation time | `Sources/ProgressCore/ProgressRegistry.swift:260–292` |
| Completion prepends history and reveals it immediately; history visibility is independent | `Sources/ProgressCore/ProgressRegistry.swift:227–248`, `273–282` |
| API serializes role and destination but not card identity; POST returns only ok | `Sources/ProgressNotifier/ProgressModel.swift:83–96`, `138` |
| Four group symbols apply only to duplicate visible destinations; no actual adjacency grouping | `Sources/ProgressNotifier/ProgressPresentation.swift:5–8`, `69–110` |
| Current child badge and bent arrow differentiate role but do not show parentage | `Sources/ProgressNotifier/ProgressCard.swift:255–259`, `359–373` |
| Existing width interpolates 200→350; unified geometry owns row/mode transitions | `Sources/ProgressNotifier/ProgressPresentation.swift:49–67`, `83–97` |
| Navigation follows desired item array and stores selection by UUID | `Sources/ProgressNotifier/ProgressPresentation.swift:71–79`, `122–145` |
| Keyboard and recall already have stable contracts worth preserving | `Sources/ProgressNotifier/App.swift:85–121`, `250–259` |
| Client supports chat and role but no parent identity; prints server JSON and silently skips unavailable app | `skills/progress-notifier/scripts/progress-notify:32–38`, `67–74`, `93–103` |
| Skill currently requires one stable name, links all delegates to root chat, and passes --child | `skills/progress-notifier/SKILL.md:12–23`, `43–94` |
| Root chat reference is already Hashable and has both environment and thread IDs | `Sources/ProgressCore/T3ThreadReference.swift:3–6` |
| Hosting content aligns to the anchored corner; group geometry should stay in presentation/card layer | `Sources/ProgressNotifier/PanelContent.swift:8–20` |

## Tradeoffs and follow-through

The rail costs horizontal space and extra group chrome; short receipts reclaim height. Compact adds a small chat identifier so two chats in the same project remain distinguishable. Existing legacy children cannot be attached confidently to an individual main: visibly detached is more honest than temporal guessing. Name-based identity retains its existing collision/suppression limits. Server-generated parent UUIDs require capturing an initial response; client-generated run IDs would tolerate an initially unavailable app better, at the cost of changing identity semantics and requiring IDs on every update. Prefer the smaller additive change first.

Implementation, if chosen, should test chronological placement across completion/recall, overlapping followups, old-parent late children, no-parent legacy clients, nested/cyclic edges, unchanged bans and undo, relaunch with optional fields, six-row selection order, compact transitions and screen-limit scrolling. App/client/skill changes, builds and deployment are outside this proposal.
