"""Run things on the Mac (C5), from a small allowlist, never without a yes.

Only four kinds of action exist, and each runs one fixed program with a list of
arguments (never a shell, so nothing in the request can become a command):
    app     open -a <App>          only an app found in /Applications, ~/Applications or /System/Applications
    folder  open <folder>          a name from ~/.claudy/places.json, or an existing folder inside your home
    url     open <http(s) URL>     "search <words>" becomes a web search URL
    script  ~/.claudy/scripts/<name>   an executable file in that folder, no arguments, 60 s limit

What eye.py relies on (the contract):
    act = parse(text) -> Action | None   None means "not a request to run something", so it is a question
    Action.kind, Action.target, Action.say   say = the sentence read out on the confirm card
    act.problem -> str | None            why it cannot run (unknown app, missing script...); no card is shown
    act.run() -> str                     runs it and returns a short spoken result
  The caller must get a yes first (phone `confirm` card, or the terminal) and call run() only then.
  CLAUDY_ACTIONS_DRYRUN=1 prints the command instead of running app/folder/url (for tests).
"""
import os
import re
import subprocess
import urllib.parse
from pathlib import Path

from common import HOME, read_json

SCRIPTS = HOME / "scripts"
PLACES = HOME / "places.json"
APP_DIRS = [Path("/Applications"), Path.home() / "Applications", Path("/System/Applications"),
            Path("/System/Applications/Utilities")]
SEARCH_URL = "https://duckduckgo.com/?q="
SCRIPTS.mkdir(parents=True, exist_ok=True)

# "open my project folder", "run script backup", "search for resistor colour codes", "go to github.com"
PATTERNS = [
    ("script", r"^(?:please\s+)?(?:run\s+(?:the\s+|my\s+)?(?:script\s+)?|start\s+(?:the\s+|my\s+)?script\s+)(?P<x>[\w.-]+?)(?:\s+script)?$"),
    ("url", r"^(?:please\s+)?(?:open|go to)\s+(?P<x>https?://\S+|[\w-]+(?:\.[\w-]+)*\.(?:com|org|net|io|dev|edu|ac\.uk|co\.uk|ai)(?:/\S*)?)$"),
    ("search", r"^(?:please\s+)?(?:search|google|look up)\s+(?:for\s+|the web for\s+)?(?P<x>.+)$"),
    ("folder", r"^(?:please\s+)?open\s+(?:the\s+|my\s+)?(?P<x>.+?)\s+folder$"),
    ("folder", r"^(?:please\s+)?open\s+(?P<x>~/\S*|/\S+)$"),
    ("app", r"^(?:please\s+)?(?:open|launch|start)\s+(?:the\s+)?(?P<x>[\w .+-]+?)(?:\s+app)?$"),
]


class Action:
    def __init__(self, kind: str, target: str, argv: list, say: str, problem=None):
        self.kind, self.target, self.argv, self.say, self.problem = kind, target, argv, say, problem

    def __repr__(self):
        return f"Action({self.kind}, {self.target!r}, {self.argv}, problem={self.problem!r})"

    def run(self) -> str:
        if self.problem:
            return self.problem
        if self.kind != "script" and os.environ.get("CLAUDY_ACTIONS_DRYRUN"):
            print(f"[dry run] would run: {self.argv}")
            return "Done (dry run)."
        try:
            r = subprocess.run(self.argv, cwd=SCRIPTS if self.kind == "script" else None,
                               capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            return "The script took longer than a minute, so I stopped waiting."
        except OSError as e:
            return f"That did not work: {e}"
        if r.returncode != 0:
            return f"That failed with code {r.returncode}. " + (r.stderr.strip().splitlines() or [""])[-1][:150]
        if self.kind == "script":
            last = (r.stdout.strip().splitlines() or ["Done."])[-1][:150]
            return f"Script {self.target} finished. {last}"
        return "Done."


def find_app(name: str):
    want = name.lower().replace(" ", "")
    for d in APP_DIRS:
        try:
            for p in d.iterdir():
                if p.suffix == ".app" and p.stem.lower().replace(" ", "") == want:
                    return p
        except OSError:
            continue
    return None


def find_folder(name: str):
    places = {k.lower(): v for k, v in read_json(PLACES, {}).items()}
    key = name.lower().strip()
    raw = places.get(key) or places.get(key + " folder") or name
    p = Path(raw).expanduser()
    if not p.is_absolute():
        p = Path.home() / raw
    p = p.resolve()
    home = Path.home().resolve()
    if p.is_dir() and (p == home or home in p.parents):   # nothing outside your home folder
        return p
    return None


def parse(text: str):
    t = re.sub(r"[.!?]+$", "", text.strip()).strip()
    low = t.lower()
    for kind, rule in PATTERNS:
        m = re.match(rule, low)
        if not m:
            continue
        x = t[m.start("x"):m.end("x")].strip()   # keep the original capitals for names and URLs
        if kind == "script":
            p = SCRIPTS / x
            if not (p.is_file() and os.access(p, os.X_OK)) or p.resolve().parent != SCRIPTS.resolve():
                return Action("script", x, [], "", f"There is no script called {x} in {SCRIPTS}.")
            return Action("script", x, [str(p)], f"Run the script {x}?")
        if kind == "url":
            url = x if x.lower().startswith(("http://", "https://")) else "https://" + x
            return Action("url", url, ["open", url], f"Open {url} in the browser?")
        if kind == "search":
            url = SEARCH_URL + urllib.parse.quote_plus(x)
            return Action("url", url, ["open", url], f"Search the web for {x}?")
        if kind == "folder":
            p = find_folder(x)
            if p is None:
                return Action("folder", x, [], "", f"I don't know a folder called {x}. Add it to {PLACES}.")
            return Action("folder", str(p), ["open", str(p)], f"Open the folder {p.name}?")
        if kind == "app":
            p = find_app(x)
            if p is None:
                return None   # "open the box" is a question, not an app; let Claude answer it
            return Action("app", p.stem, ["open", "-a", str(p)], f"Open the app {p.stem}?")
    return None
