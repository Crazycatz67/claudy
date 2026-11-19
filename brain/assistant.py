"""Claudy's assistant features on the Mac (B6 H1-H10): sessions, presets, ask modes, step coach.

eye.py owns the camera, the watcher and Claude; this file holds the parts that only
need data, so they stay small and testable.

What eye.py relies on (the contract):
    presets = load_presets()            dict name -> {label, task, watch, ask, guide?} from brain/presets.json
    s = Session(); s.start()            new folder ~/.claudy/sessions/<YYYY-MM-DD_HH-MM-SS>/
    s.add_keyframe(t, frame, sharp)     keeps a 960 px copy in keyframes/ and an index line
    s.add_note(t, text); s.add_photo(path)
    s.history(n) -> [(t, path)]         up to n keyframes spread over this and the last session (H2)
    s.since(minutes) -> (t, path)|None  the keyframe closest to that long ago, or the first one (H5)
    s.end(summarise) -> Path|None       writes notes.md, best/, timelapse.mp4, summary.md (H3, H10).
        summarise(prompt) -> str is called once (the small model); "" or "ERROR..." falls back
        to a plain list of notes. An empty session (no keyframes, no notes) is deleted.
    mode_for(question) -> str           ask | memory | changed | count | safety | worksheet | step
    MODE_HINTS[mode]                    extra instruction added to the question
    c = Coach(); c.load(name) -> bool   guide = ~/.claudy/guides/<name>.txt (or a path), one step per line
    c.current -> str|None, c.advance(), c.back(), c.status() -> str
"""
import json
import re
import shutil
import time
from pathlib import Path

import cv2

from common import HOME, save_jpg, write_json

SESSIONS = HOME / "sessions"
GUIDES = HOME / "guides"
PRESETS = Path(__file__).with_name("presets.json")
TIMELAPSE_FPS = 4
BEST_N = 6

for d in (SESSIONS, GUIDES):
    d.mkdir(parents=True, exist_ok=True)


def load_presets(path: Path = PRESETS) -> dict:
    """Read the editable preset file. A typo in it must not stop Claudy, so it warns and goes on."""
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as e:
        print(f"Note: could not read {path.name} ({e}); presets are off until it is fixed.")
        return {}
    return {k: v for k, v in data.items() if not k.startswith("_") and isinstance(v, dict)}


# ---- ask modes (H2, H5, H6, H7, H9, H1) ------------------------------------------
# Plain keyword rules, so choosing a mode costs no Claude request. First match wins.
MODE_RULES = [
    ("step", r"\b(next step|done with (this|the) step|is (this|the) step done|what('s| is) the next step|step done)\b|^next\W*$"),
    ("changed", r"\bwhat('s| has| have)? (changed|moved|is different)\b|\bwhat changed\b|\banything (changed|moved|different)\b"),
    ("memory", r"\bwhere('s| is| are| did i (put|leave)| have i (put|left)| was| were)\b|\bhave you seen\b|\blast (saw|seen)\b"),
    ("count", r"\bhow many\b|\bcount\b"),
    ("safety", r"\b(safe|safety|dangerous|danger|hazard)\b"),
    ("worksheet", r"\b(worksheet|whiteboard|this page|the page|homework|exercise|question \d+|read (this|it) (back|out))\b"),
]

MODE_HINTS = {
    "ask": "",
    "memory": ("The frames are from earlier in his session, oldest first, with how long ago each was taken; the last one is now. "
               "Say where you last saw the thing he asks about, in which frame (how long ago) and where on the desk. "
               "If you never saw it, say so plainly."),
    "changed": ("The first frame is the desk earlier, the last one is the desk now. "
                "Name what was added, removed or moved between them. Ignore small changes in light or his hands."),
    "count": ("Count the parts he asks about in the newest frame. Group them by kind (for example screws by size) "
              "and give each count as a number. If some are hidden or unclear, say how many you are unsure about."),
    "safety": ("Do a safety check of the newest frame: hot tools left on or out of their stand, liquids near electronics or an open case, "
               "loose metal (screws, wire offcuts) on a board, trailing cables, blades. Name each risk and where it is, most serious first. "
               "If nothing is risky, say it looks safe."),
    "worksheet": ("He is pointing the camera at a page or a whiteboard. First read the question back word for word, "
                  "then explain it simply or check his answer if one is written. If the text is too blurry, say to hold it closer and steadier."),
    "step": "",   # filled in by the coach with the current step
}


def mode_for(question: str) -> str:
    q = question.lower().strip()
    for mode, rule in MODE_RULES:
        if re.search(rule, q):
            return mode
    return "ask"


def minutes_in(question: str):
    """'what changed in the last 10 minutes' -> 10.0; no number -> None (compare with the start)."""
    m = re.search(r"(\d+(?:\.\d+)?)\s*(min|minute|minutes|m)\b", question.lower())
    if m:
        return float(m.group(1))
    m = re.search(r"(\d+(?:\.\d+)?)\s*(h|hour|hours)\b", question.lower())
    return float(m.group(1)) * 60 if m else None


# ---- sessions (H3, H10, and the history H2 and H5 read) -----------------------------
class Session:
    def __init__(self, root: Path = SESSIONS):
        self.root = root
        self.dir = None
        self.started = 0.0
        self.keys = []     # {"t", "path", "sharp"}
        self.notes = []    # {"t", "text"}
        self.photos = []   # paths of full-detail photos from the phone

    @property
    def active(self) -> bool:
        return self.dir is not None

    def start(self):
        self.started = time.time()
        name = time.strftime("%Y-%m-%d_%H-%M-%S", time.localtime(self.started))
        self.dir = self.root / name
        (self.dir / "keyframes").mkdir(parents=True, exist_ok=True)
        self.keys, self.notes, self.photos = [], [], []

    def add_keyframe(self, t: float, frame, sharp: float):
        if not self.active:
            return
        path = self.dir / "keyframes" / f"k_{len(self.keys):04d}.jpg"
        save_jpg(path, frame, max_side=960, quality=82)
        self.keys.append({"t": t, "path": str(path), "sharp": float(sharp)})
        write_json(self.dir / "index.json", {"started": self.started, "keyframes": self.keys})

    def add_note(self, t: float, text: str):
        if self.active:
            self.notes.append({"t": t, "text": text})

    def add_photo(self, path):
        if self.active and path:
            self.photos.append(str(path))

    def _all_keys(self):
        """This session's keyframes, after the previous session's, so 'where did I leave it' can reach back."""
        older = []
        for d in sorted(p for p in self.root.iterdir() if p.is_dir() and p != self.dir)[-1:]:
            try:
                older = json.loads((d / "index.json").read_text()).get("keyframes", [])
            except (OSError, ValueError):
                pass
        return [k for k in older + self.keys if Path(k["path"]).exists()]

    def history(self, n: int = 8):
        keys = self._all_keys()
        if len(keys) > n:   # spread over the whole time, always keeping the newest
            step = (len(keys) - 1) / (n - 1)
            keys = [keys[round(i * step)] for i in range(n)]
        return [(k["t"], k["path"]) for k in keys]

    def since(self, minutes=None):
        keys = [k for k in self.keys if Path(k["path"]).exists()]
        if not keys:
            return None
        if minutes is None:
            k = keys[0]
        else:
            target = time.time() - minutes * 60
            k = min(keys, key=lambda k: abs(k["t"] - target))
        return k["t"], k["path"]

    def end(self, summarise=None):
        """Close the session folder. Returns it, or None when nothing happened."""
        if not self.active:
            return None
        d, self.dir = self.dir, None
        if not self.keys and not self.notes and not self.photos:
            shutil.rmtree(d, ignore_errors=True)
            return None
        clock = lambda t: time.strftime("%H:%M", time.localtime(t))
        lines = [f"- {clock(n['t'])} {n['text']}" for n in self.notes]
        (d / "notes.md").write_text(f"# Notes, {d.name}\n\n" + ("\n".join(lines) or "(no notes)") + "\n")
        best = d / "best"
        best.mkdir(exist_ok=True)
        for i, k in enumerate(sorted(self.keys, key=lambda k: -k["sharp"])[:BEST_N]):
            shutil.copyfile(k["path"], best / f"best_{i + 1}.jpg")
        for p in self.photos:
            if Path(p).exists():
                shutil.copyfile(p, best / Path(p).name)
        self._timelapse(d / "timelapse.mp4")
        minutes = max(1, round((time.time() - self.started) / 60))
        text = ""
        if summarise and lines:
            prompt = ("You are Claudy, a desk robot. Below are your notes from Farhan's work session "
                      f"({minutes} min). Write a short session summary in markdown: one heading line, then "
                      "3 to 6 bullet points saying what he did, any problems or warnings, and what is left to do. "
                      "Plain words. Do not use any tools.\n\nNotes:\n" + "\n".join(lines))
            text = (summarise(prompt) or "").strip()
        if not text or text.startswith("ERROR"):
            text = f"# Session {d.name}\n\n" + ("\n".join(lines) or "- Nothing was noted.")
        lapse = " Time-lapse: timelapse.mp4." if (d / "timelapse.mp4").exists() else ""
        extra = f"\n\n{len(self.keys)} keyframes, {minutes} min.{lapse} Best photos: best/\n"
        (d / "summary.md").write_text(text + extra)
        return d

    def _timelapse(self, out: Path):
        if len(self.keys) < 2:
            return
        size = None
        writer = None
        for k in self.keys:
            img = cv2.imread(k["path"])
            if img is None:
                continue
            if size is None:   # every frame must be the same size; lenses can differ, so resize
                size = (img.shape[1] - img.shape[1] % 2, img.shape[0] - img.shape[0] % 2)
                writer = cv2.VideoWriter(str(out), cv2.VideoWriter_fourcc(*"mp4v"), TIMELAPSE_FPS, size)
            writer.write(cv2.resize(img, size))
        if writer:
            writer.release()


# ---- step coach (H1) ------------------------------------------------------------------
class Coach:
    def __init__(self):
        self.name = None
        self.steps = []
        self.i = 0

    def load(self, name: str) -> bool:
        p = Path(name).expanduser()
        if not p.is_file():
            p = GUIDES / (name if name.endswith(".txt") else name + ".txt")
        try:
            raw = p.read_text().splitlines()
        except OSError:
            return False
        # One step per line; blank lines and lines starting with # are ignored; "1." numbering is dropped.
        steps = [re.sub(r"^\s*(\d+[.)]|-|\*)\s*", "", s).strip() for s in raw if s.strip() and not s.lstrip().startswith("#")]
        if not steps:
            return False
        self.name, self.steps, self.i = p.stem, steps, 0
        return True

    def stop(self):
        self.name, self.steps, self.i = None, [], 0

    @property
    def current(self):
        return self.steps[self.i] if self.name and self.i < len(self.steps) else None

    def advance(self):
        if self.name and self.i < len(self.steps):
            self.i += 1
        return self.current

    def back(self):
        if self.name and self.i > 0:
            self.i -= 1
        return self.current

    def status(self) -> str:
        if not self.name:
            return "no guide"
        if self.current is None:
            return f"{self.name}: all {len(self.steps)} steps done"
        return f"{self.name}: step {self.i + 1} of {len(self.steps)}: {self.current}"
