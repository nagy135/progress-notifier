# Chat grouping proposal for decision

Three independent design passes converged on chronological chat groups with explicit child branches. Their original mockups and evidence remain in `../chat-grouping-a/`, `../chat-grouping-b/`, and `../chat-grouping-c/`. The parent comparison refines that consensus into three distinct visual treatments; it is not three different data models.

## Selected direction

Option 1 with small downward arrowheads along the main rail between successive main runs, in expanded and compact modes. Arrows appear only where a later main run exists; no arrow implies hypothetical future work. Child connectors retain bent side branches and indentation. These are presentation details and require no additional API fields.

## Visual choices

1. **Timeline rail — recommended.** Earlier main runs are shallow receipts above the newer main. A continuous vertical line ties the chat together; children branch below their owner. Most explicit chronology.
2. **Chat container.** One shared border encloses related main runs and a recessed child section. Easiest to scan multiple chats, but adds a layer of chrome.
3. **Continuation cards.** Preserve separate cards, connect main runs with small downward follow-up arrows, and indent/dash child cards. Closest to the existing app; connections are less obvious at a glance.

All three have expanded and compact mockups in `comparison.html`. No combined percentage; each task retains its own progress, ETA and notes.

## Behavior common to all options

Group by the exact existing `t3Thread` environment/thread pair. Project labels never group chats. Keep chat blocks stable; progress updates do not move them. Order visible main runs by original creation order, older above newer; children sit below their actual owning run, ordered by creation. A child from an earlier run stays there even when the next main run starts. Use a persisted insertion ordinal to break timestamp ties and preserve legacy undated order.

Only visible history participates. C, X, Z and relaunch retain their current visibility rules; grouping does not silently recall hidden results. H still reveals newest hidden completion first, then positions it in its chat chronology. A hidden/missing parent leaves a labeled detached child branch; it does not hide active children or attach them to the newest main. Legacy children with no parent link remain visibly unassigned.

Selection stays on the same item UUID. Up/Down and J/K follow the rendered task order; headers/connectors are not focus stops. D remains per-task notes; M preserves order and selection. Enter opens the existing parent-chat destination. Hiding/deleting a parent affects that task only. Completion does not move a card or replay sound on recall. Scrolling still starts only at the screen limit. Child indentation, elbows and a role label supplement color.

## Proposed API and client changes

Keep `POST /items`, `GET /items`, `t3Thread`, `isChild`, name-based updates, and existing delete/undo behavior. Add two optional UUID relationship fields:

- `runId`: generated once per agent run, independent of the display name and chat ID.
- `parentRunId`: immediate spawning agent's runId, present for explicitly linked children only.

A sequential main follow-up gets a fresh runId and the same t3Thread; it has no parentRunId. A child gets its own runId, `isChild:true`, its parent's runId, and the shared user-facing chat destination. This identifies ownership before the app receives anything, preserving best-effort notifications when the app is stopped.

Persist and return both fields with active items, history, closed items and deletion snapshots. Omission preserves metadata on subsequent updates; new runs inherit nothing from prior same-name results. Old clients and saved state remain valid. Expose existing item `id` and `createdAt` in GET for diagnostics; leave retained history excluded from GET /items.

Validate UUIDs, duplicate/conflicting identities, self-parenting, cycles and known cross-chat relationships. Allow unresolved parents for out-of-order arrival, then validate when resolved. Metadata is immutable after first assignment. Reject conflicts with 409 rather than silently merging runs; a repeated terminal runId must not create another task. Parent references are metadata, not a change to update routing. Names must still be unique among concurrent tasks. Do not change network binding or origin checks.

Add CLI `--run-id UUID` and `--parent-run-id UUID`, preserving all existing flags and positional arguments. Initial parent-linked child calls require `--child`. Reuse the saved run ID on every milestone; never generate a UUID independently on each invocation. No additional endpoint or aggregate progress field is needed.

### Alternative considered

Pass C proposed exposing the existing server item UUID and adding only `parentItemId`, captured from the initial POST response. This is smaller, but cannot establish ownership if that initial notification is skipped while the app is stopped. The client explicitly supports that case (`skills/progress-notifier/scripts/progress-notify:93–103`); later updates can create the parent card after children have started. Prefer client-generated run/parent-run handles so the brief remains correct without a successful initial API response. These handles are correlation metadata; current name-based update routing remains unchanged.

## Proposed skill changes

Amend the repository skill and synchronize the installed copy only after implementation:

1. Explain the three identities: name routes one ledger, chat destination groups runs, run/parent-run IDs associate delegates.
2. Generate one UUID before the initial notification and reuse it throughout the run. A new main follow-up creates a fresh UUID; milestone updates keep the existing UUID and name.
3. Every delegate brief includes the parent's run ID, the resolved chat destination and real project metadata. Children generate their own run IDs, send `--child --parent-run-id`, and pass their own ID onward for nested delegation.
4. Without reliable ownership metadata, keep `--child` and omit the parent link. Never guess from titles, newest card or shared chat alone.
5. Document chronological placement, compact branches and unchanged history visibility/keyboard behavior.

## Scope and verification

The current cause is `Sources/ProgressNotifier/ProgressModel.swift:9`, which concatenates active items before visible completed history. `ProgressPresentation.swift:69` preserves that input order and only adds shared-thread symbols. `ProgressRegistry.swift:260` routes by name and already retains creation time, t3Thread and isChild.

Implementation would touch core relationship/state validation, the visible ordering projection, presentation geometry/cards, API serialization, CLI validation, skill and README. Validate interleaved chats, late children, overlapping main runs, missing parents, legacy state, completion/history/undo, selection and both layouts. Then run `swift test`, Python client tests and `./scripts/build.sh`; runtime layout checks follow any later authorized deployment.

This decision package contains mockups and proposals only. No application, client or skill behavior has changed; no commit, build or deployment was performed. Parent mockups were rendered in all three states with no console messages. Original independent artifacts are retained for inspection.
