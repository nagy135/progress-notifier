#!/usr/bin/env python3
"""Exercise the running app. Creates temporary cards and plays one completion sound."""
from concurrent.futures import ThreadPoolExecutor
import json
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = "http://127.0.0.1:8766"
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
PREFIX = "Smoke " + uuid.uuid4().hex[:8]
names = [PREFIX + " · Build 🚀", PREFIX + " · Tests + lint & QA"]


def call(path, method="GET", body=None, headers=None, status=200):
    req = urllib.request.Request(BASE + path, data=body, method=method, headers=headers or {})
    try:
        response = OPENER.open(req, timeout=4)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        result = json.load(response)
        assert response.code == status, (response.code, result)
        return result


def update(name, progress, eta=30, **metadata):
    return call("/items", "POST", json.dumps({"name": name, "progress": progress, "etaSeconds": eta, **metadata}).encode(),
                {"Content-Type": "application/json"})


def items():
    return [item for item in call("/items")["items"] if item["name"].startswith(PREFIX)]


def dismiss(name):
    call("/items?" + urllib.parse.urlencode({"name": name}), "DELETE")


try:
    assert call("/health")["app"] == "progress-notifier"
    icon = {"kind": "lucide", "name": "snowflake", "color": "blue"}
    update(names[0], 0, 120, project="progress-notifier")
    update(names[1], 10, 90, project="nix-darwin", projectIcon=icon)
    assert len(items()) == 2
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda name: update(name, 42, 60), names))
    assert all(item["progress"] == 42 and 55 <= item["etaSeconds"] <= 60 for item in items())
    assert items()[0]["project"] == "progress-notifier"
    assert items()[1]["projectIcon"] == icon
    update(names[1], 42, 45)  # ETA-only updates keep the icon and trigger a new pulse.
    assert items()[1]["projectIcon"] == icon

    call("/items", "POST", b'{"name":"bad","progress":101,"etaSeconds":0}',
         {"Content-Type": "application/json"}, status=400)
    call("/items", "POST", b'{}', {"Content-Type": "application/json"}, status=400)
    for metadata in [{"project": 42}, {"projectIcon": "snowflake"},
                     {"projectIcon": {"kind": "lucide", "name": "../file", "color": "blue"}},
                     {"projectIcon": {"kind": "emoji", "emoji": ""}}]:
        body = {"name": names[0], "progress": 42, "etaSeconds": 30, **metadata}
        call("/items", "POST", json.dumps(body).encode(), {"Content-Type": "application/json"}, status=400)
    call("/items", "POST", b'not json', {"Content-Type": "application/json"}, status=400)
    call("/items", "POST", b'{}', {"Content-Type": "text/plain"}, status=415)
    call("/items", "POST", b'{}', {"Content-Type": "application/json", "Origin": "https://example.com"}, status=403)
    call("/missing", status=404)
    call("/items", "PUT", status=405)
    call("/items", "DELETE", status=400)
    call("/items", "POST", b'x' * 16385, {"Content-Type": "application/json"}, status=413)

    # The listener must assemble a request split across separate TCP writes.
    body = json.dumps({"name": names[0], "progress": 73, "etaSeconds": 20}).encode()
    header = f"POST /items HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n".encode()
    with socket.create_connection(("127.0.0.1", 8766), timeout=3) as connection:
        connection.sendall(header + body[:5])
        time.sleep(0.05)
        connection.sendall(body[5:])
        response = b""
        while True:
            data = connection.recv(4096)
            if not data:
                break
            response += data
        assert response.startswith(b"HTTP/1.1 200"), response
    assert next(item for item in items() if item["name"] == names[0])["progress"] == 73
    update(names[0], 73, 20, project="")
    assert "project" not in items()[0] and "projectIcon" not in items()[0]

    dismiss(names[1])
    update(names[1], 60)
    assert len(items()) == 1
    update(names[1], 100, 0)
    assert len(items()) == 1
    update(names[0], 100, 0)
    update(names[0], 100, 0)
    assert items()[0]["completing"] is True
    time.sleep(1.6)
    assert not items()
    update(names[0], 100, 0)
    assert not items()
    print("PASS: live API, project metadata/icons, legacy and ETA-only updates, validation, fragmented HTTP, dismissal, and completion")
finally:
    for name in names:
        try:
            dismiss(name)
            update(name, 100, 0)
        except Exception:
            pass
