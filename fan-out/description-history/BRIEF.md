# Description history design review

This folder contains three independent proposals, not production app or API changes.

## Shared behavior

- Optional `description` on existing `POST /items`, alongside `name`, `project`, `progress`, and `etaSeconds`.
- A described update pairs its text with the progress from that same request and a server timestamp.
- Default: latest described update and a total update count on each task.
- D: unfold or fold description history across all tasks, newest first.
- Every history entry includes its own percentage and proportional bar.
- Keep existing clients compatible; tasks with no descriptions need no empty history section.
- Keep the panel anchored at the top right; grow to the screen limit before enabling scrolling.
- Designs must retain a useful narrow macOS panel, legible longer descriptions, and reduced-motion behavior.

## Review boundary

Only prototype artifacts may change. No Swift, client, server, runtime data, installed app, commits, or deployment are part of this review.

Each agent owns a/, b/, or c/. Prior fan-out designs elsewhere are preserved.
