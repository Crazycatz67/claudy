"""Claudy's connector for Claude Desktop.

Claude Desktop starts this program by itself (see README). It gives Claude
three tools that read what eye.py is already watching. It never opens the
camera itself, so eye.py must be running in Terminal.
"""
import time

import cv2
from mcp.server.mcpserver import Image, MCPServer

from common import BEST, LATEST, NOTES, STATE, ago, read_json, shrink

mcp = MCPServer("claudy", instructions=(
    "Claudy is Farhan's desk robot. Its camera is always watching while it is awake. "
    "Use whats_happening for context about his work, look for the view right now, "
    "and zoom to read small details such as labels, pins or solder joints."))

ASLEEP = "Claudy can't see right now: it is asleep, or eye.py is not running in Terminal."


def awake() -> bool:
    s = read_json(STATE, {})
    return s.get("awake", False) and time.time() - s.get("t", 0) < 5 and LATEST.exists()


def jpg(frame, max_side: int) -> Image:
    ok, buf = cv2.imencode(".jpg", shrink(frame, max_side), [cv2.IMWRITE_JPEG_QUALITY, 85])
    return Image(data=buf.tobytes(), format="jpeg")


@mcp.tool()
def look() -> list:
    """See what Claudy's camera sees right now (the clearest frame of the last 2 seconds)."""
    if not awake():
        return [ASLEEP]
    frame = cv2.imread(str(BEST if BEST.exists() else LATEST))
    return ["Claudy's view right now:", jpg(frame, 1280)]


@mcp.tool()
def whats_happening() -> list:
    """Recent context: Claudy's notes about what Farhan has been doing, plus clear frames
    from the last few moments where something changed (oldest first), plus the view now."""
    if not awake():
        return [ASLEEP]
    s = read_json(STATE, {})
    notes = read_json(NOTES, [])[-10:]
    out = [f"Task: {s.get('task', 'unknown')}\nNotes (oldest first):\n" +
           ("\n".join(f"- {n['text']} ({ago(n['t'])})" for n in notes) or "- none yet")]
    for k in s.get("keyframes", [])[-3:]:
        frame = cv2.imread(k["path"])
        if frame is not None:
            out += [f"Moment {ago(k['t'])}:", jpg(frame, 1024)]
    out += ["Now:", jpg(cv2.imread(str(BEST if BEST.exists() else LATEST)), 1024)]
    return out


@mcp.tool()
def zoom(left: float, top: float, width: float, height: float) -> list:
    """Full-detail close-up of part of the current view. All values are fractions of the
    picture from 0 to 1, e.g. left=0.5, top=0.5, width=0.25, height=0.25 is the area just
    right of and below the centre. Use it to read labels or check small parts."""
    if not awake():
        return [ASLEEP]
    frame = cv2.imread(str(BEST if BEST.exists() else LATEST))
    h, w = frame.shape[:2]
    x0, y0 = int(max(0, min(1, left)) * w), int(max(0, min(1, top)) * h)
    x1, y1 = int(min(1, left + max(0.02, width)) * w), int(min(1, top + max(0.02, height)) * h)
    crop = frame[y0:y1, x0:x1]
    if crop.size == 0:
        return ["That area is outside the picture."]
    crop = cv2.resize(crop, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC) if max(crop.shape[:2]) < 600 else crop
    return [f"Close-up of x {left:.2f}-{left + width:.2f}, y {top:.2f}-{top + height:.2f}:", jpg(crop, 1280)]


if __name__ == "__main__":
    mcp.run()
