# Development and delivery

## Checks

Run `swift test` (core, presentation, and native hosting tests) and
`python3 -m unittest discover -s Tests/ClientTests` before delivering code changes.
Build the app bundle with `./scripts/build.sh`; it creates a release executable,
packages resources and the icon, and ad-hoc signs `build/Progress Notifier.app`.

## Verified runtime

- Host: Viktor's local Mac, computer name `Viktor-Mac` (observed hostname
  `Mac.fritz.box`). Run deployment locally as `Viktor`; no SSH or fleet relay is used.
- Checkout: `/Users/Viktor/Code/progress-notifier`, branch `main`.
- External fetch/push remote: `origin`, `git@github.com:nagy135/progress-notifier.git`.
- Installed app: `/Applications/Progress Notifier.app`.
- Process: `/Applications/Progress Notifier.app/Contents/MacOS/ProgressNotifier`.
  This is a user-launched menu bar app, not a system service.
- API: `http://127.0.0.1:8766`. It must remain bound to IPv4 loopback.
- Runtime data: `~/Library/Application Support/Progress Notifier/state.json`.
  Preserve it and the app's UserDefaults when deploying.

## Deployment order

1. Review the worktree, branch, upstream, and remotes. Preserve unrelated changes,
   including untracked files. Inspect recent commit authors and follow Viktor's
   Conventional Commits style (currently unscoped subjects such as `fix: ...`).
2. Commit task changes, push `main` to the external `origin` without force, then
   synchronize this same local runtime checkout with `git pull --ff-only origin main`.
   Verify `git rev-parse HEAD` matches the intended published revision. If the remote
   advances unexpectedly or the checkout diverges, inspect before building.
3. From the checkout, run the checks above and `./scripts/build.sh`.
4. Quit the installed app with its Quit action or Command-Q. For a CLI restart,
   first preview the exact process and verify every match belongs to this app:

   ```sh
   pgrep -u "$(id -u)" -fl '^/Applications/Progress Notifier[.]app/Contents/MacOS/ProgressNotifier$'
   ```

   Only after verifying the matches, stop that process with:

   ```sh
   pkill -u "$(id -u)" -f '^/Applications/Progress Notifier[.]app/Contents/MacOS/ProgressNotifier$'
   ```

   macOS uses BSD pkill: all options must precede the pattern. If no process is
   running, skip the stop command. Wait for the old process to exit before copying.
5. Install and relaunch:

   ```sh
   ditto 'build/Progress Notifier.app' '/Applications/Progress Notifier.app'
   open '/Applications/Progress Notifier.app'
   ```

   Native app control may also be used to quit and launch this exact installed path.
   Do not launch the checkout's build bundle while the installed app owns port 8766.
6. Verify the running process path, API, code signature, and artifact identity:

   ```sh
   pgrep -u "$(id -u)" -fl '^/Applications/Progress Notifier[.]app/Contents/MacOS/ProgressNotifier$'
   ./scripts/progress-notify --health --require-running
   codesign --verify --deep --strict '/Applications/Progress Notifier.app'
   shasum -a 256 'build/Progress Notifier.app/Contents/MacOS/ProgressNotifier' '/Applications/Progress Notifier.app/Contents/MacOS/ProgressNotifier'
   ```

   Require matching executable hashes. For HTTP or lifecycle changes, also run
   `python3 scripts/smoke-test.py`; it creates temporary progress cards and plays a
   completion sound. For layout changes, check H recall, C clear, M mode changes,
   rapid reversals, and scrolling only after the stack reaches the screen limit.

The local app, restart, health check, and matching executable hashes have been
verified. No remote fleet runtime is involved in this deployment.
