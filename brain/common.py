"""Shared paths and helpers for Claudy's eye (eye.py) and Claude connector (server.py)."""
import json
import os
import time
from pathlib import Path

import cv2

HOME = Path(os.environ.get("CLAUDY_HOME", Path.home() / ".claudy"))
KEYS = HOME / "keyframes"
SEND = HOME / "send"
STATE = HOME / "state.json"
NOTES = HOME / "notes.json"
LATEST = HOME / "latest.jpg"
BEST = HOME / "best.jpg"

for d in (HOME, KEYS, SEND):
    d.mkdir(parents=True, exist_ok=True)


def save_jpg(path: Path, frame, max_side: int | None = None, quality: int = 88) -> None:
    """Write a JPEG atomically, so the other program never reads half a file."""
    if max_side:
        frame = shrink(frame, max_side)
    ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if ok:
        tmp = path.with_name(path.stem + ".tmp.jpg")
        tmp.write_bytes(buf.tobytes())
        os.replace(tmp, path)


def shrink(frame, max_side: int):
    h, w = frame.shape[:2]
    s = max_side / max(h, w)
    return frame if s >= 1 else cv2.resize(frame, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)


def write_json(path: Path, data) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1))
    os.replace(tmp, path)


def read_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def ago(t: float) -> str:
    s = max(0, int(time.time() - t))
    return f"{s} s ago" if s < 90 else f"{s // 60} min ago"
