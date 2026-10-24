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

The app waits silently with a menu bar icon. New items show the floating panel without taking keyboard focus. Drag its background to move it. Large stacks scroll. Move the bundle to `/Applications` if desired. It is locally ad-hoc signed, not notarized.

## Send progress

Using the included Python 3 client (starts the built app if needed):

```sh
./scripts/progress-notify 'Build release' 0 180
./scripts/progress-notify 'Build release' 45 90
./scripts/progress-notify 'Build release' 100 0
```

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

The ETA counts down independently of progress. Expired estimates say “Finishing soon”; only a client can mark an item complete. At 100%, an existing item flashes green, scales up, plays the macOS Glass sound, and disappears after 1.25 seconds. Reduce Motion disables the scale effect. Repeated completion requests do not play extra sounds. Unknown completions do not create cards.

Click an item's X to dismiss it. Updates for that name stay silent until its client sends 100%; the name is then available for a new run. Dismissal does not cancel the client's actual work. When all cards close, the app keeps listening. Use the menu bar icon to show progress or quit. State is in memory only.

## API

The listener binds **only to IPv4 loopback `127.0.0.1:8766`**, using Apple's [Network framework local endpoint binding](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint). It does not listen on LAN or IPv6 addresses. Any local process can send updates; there is no token. Browser-origin requests are rejected and no CORS access is provided.

| Request | Result |
| --- | --- |
| `GET /health` | App name, version, and status. |
| `POST /items` | Create/update an item; returns `{"ok":true}`. Requires `Content-Type: application/json`. |
| `GET /items` | `{"items":[{"name":"Build release","progress":45,"etaSeconds":89.2,"completing":false}]}` |
| `DELETE /items?name=Build%20release` | Dismiss an item without a success sound. Idempotent. |

Invalid input returns JSON `{"error":"…"}` with an HTTP 4xx status. Supports HTTP/1.0 and HTTP/1.1, one request per connection, Content-Length bodies up to 16 KiB, headers up to 8 KiB, 50 visible items, and 64 simultaneous connections with a five-second read timeout. Chunked request bodies are unsupported. Always include Content-Length for POST; curl and the Python client supply it automatically.

```sh
./scripts/progress-notify --list
./scripts/progress-notify --dismiss 'Build release'
./scripts/progress-notify --health --no-launch
```

## Agent skill

The self-contained skill is in [`skills/progress-notifier`](skills/progress-notifier). Copy that directory into your agent's skills directory. Viktor's shared installation lives in `~/.dots/agents/.agents/skills/progress-notifier` (also exposed at `~/.agents/skills/progress-notifier`). It includes a client and instructions for task naming, ETA updates, successful completion, and cancellation.

## Verify

```sh
swift test
./scripts/build.sh
open 'build/Progress Notifier.app'
python3 scripts/smoke-test.py
```

The smoke test sends real progress cards and plays one completion sound. It cleans up its own test items. Registry and HTTP parser tests cover dismissal, duplicate completions, stale updates, ETA replacement, invalid input, fragmented requests, and payload limits.
