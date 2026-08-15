#!/usr/bin/env python3

import json
import re
import sys
import tempfile
from pathlib import Path


def marker_path(session_id: str) -> Path:
    safe_id = re.sub(r"[^A-Za-z0-9_-]", "_", session_id)
    return Path(tempfile.gettempdir()) / "protocol-session-titles" / safe_id


def local_title(prompt: str) -> str:
    words = re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]*", prompt)
    ignored = {"a", "an", "and", "for", "in", "of", "please", "the", "to"}
    meaningful = [word for word in words if word.lower() not in ignored]
    return " ".join(meaningful[:6])[:80]


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0

    session_id = event.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return 0

    marker = marker_path(session_id)
    if event.get("hook_event_name") == "SessionStart":
        if event.get("session_title"):
            marker.parent.mkdir(parents=True, exist_ok=True)
            marker.touch(exist_ok=True)
        return 0

    if event.get("hook_event_name") != "UserPromptSubmit" or marker.exists():
        return 0

    prompt = event.get("prompt")
    if not isinstance(prompt, str):
        return 0
    title = local_title(prompt)
    if not title:
        return 0

    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.touch(exist_ok=True)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "sessionTitle": title}}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
