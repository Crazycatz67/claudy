"""Claudy's eye: watches the iPhone camera non-stop while awake.

Run it in Terminal on the Mac:
    python eye.py --task "building a PC"
    python eye.py --camera phone      (use the Claudy Phone app instead of a camera number)

While it runs:
  - It keeps the last minute of video and remembers the clear frames from
    each moment where something changed (keyframes).
  - When you finish an action, it checks with Claude and speaks only if
    something looks wrong (turn off with --no-watch or by typing "watch off").
  - Type a question in the Terminal and press Enter. Claude answers out loud
    from what Claudy has already seen. No posing for photos.

Typed commands:   sleep | wake | watch on | watch off | task: <what you're doing> | quit
Keys in the video window:   space = sleep/wake,  q = quit
"""
import argparse
import collections
import os
import platform
import queue
import shutil
import subprocess
import sys
import threading
import time

import cv2
import numpy as np

from common import (BEST, KEYS, LATEST, NOTES, SEND, STATE, HOME, ago, read_json,
                    save_jpg, shrink, write_json)

# --- tuning: change these if it is too chatty or too quiet -------------------
MOVE = 0.012        # share of the picture that must change to count as "moving"
SETTLE_S = 1.5      # seconds of stillness that end an action
MIN_ACTIVE_S = 0.6  # ignore flickers shorter than this
COOLDOWN_S = float(os.environ.get("CLAUDY_COOLDOWN", 25))     # never check on its own more often than this
BUFFER_S = 60       # seconds of video kept in memory
SAMPLE_FPS = 3      # full frames kept per second
MAX_NOTES = 20
# ------------------------------------------------------------------------------

CHECK_PROMPT = """You are Claudy, a small desk robot that watches Farhan work through a camera and helps him like a sharp, friendly lab partner.
What Farhan is doing: {task}
Your notes so far (oldest first):
{notes}
Use the Read tool to look at these camera frames (oldest first, the last one is now):
{frames}
Reply in exactly two lines:
NOTE: one short sentence saying what he is doing right now.
SAY: a short warning to say out loud if you see a mistake, a safety risk or a step he probably missed. Otherwise NONE.
Only warn when you are fairly sure. Never comment on things that are fine."""

ASK_PROMPT = """You are Claudy, a small desk robot that watches Farhan work through a camera and helps him like a sharp, friendly lab partner.
What Farhan is doing: {task}
Your notes so far (oldest first):
{notes}
Use the Read tool to look at these camera frames (oldest first, the last one is now):
{frames}
Your answer will be spoken out loud: use at most three short sentences, plain words, no lists, no markdown.
If the frames do not show enough to answer, say what you would need to see.
Farhan asks: {question}"""


class Eye:
    def __init__(self, args):
        self.args = args
        self.task = args.task
        self.watch = not args.no_watch
        self.awake = True
        self.running = True
        self.cap = None
        self.buffer = collections.deque(maxlen=BUFFER_S * SAMPLE_FPS)  # (t, frame, sharpness)
        self.keyframes = collections.deque(maxlen=6)                   # (t, path)
        self.notes = read_json(NOTES, [])[-MAX_NOTES:]
        self.jobs = queue.Queue()
        self.busy = False
        self.last_check = 0.0
        self.last_reply = "Awake. Type a question below."
        self.prev_small = None
        self.prev_t = 0.0
        self.motion = 0.0
        self.active_since = None
        self.last_move = 0.0
        self.key_n = 0
        self.last_sample = 0.0
        self.last_save = 0.0
        self.claude = shutil.which(args.claude) or args.claude
        self.phone = args.camera == "phone"
        self.link = None            # PhoneLink when --camera phone
        self.pending_device = None  # (name, address, answered Event, [answer]) waiting for yes/no
        self.text_seen = (0.0, [])  # (time, lines) the phone last read on-device

    # ---- camera -------------------------------------------------------------
    def open_camera(self):
        src = self.args.camera
        if self.phone:
            if self.link is None:
                from phone_link import PhoneLink
                self.link = PhoneLink(approve=self.approve_device, on_message=self.on_phone)
                self.link.start()
                print("Waiting for the Claudy Phone app. Open it on the same Wi-Fi.")
            self.link.drop_frames()   # nothing seen while asleep may slip into the buffer
            self.cap = self.link
            return
        if src.isdigit():
            backend = cv2.CAP_AVFOUNDATION if platform.system() == "Darwin" else cv2.CAP_ANY
            cap = cv2.VideoCapture(int(src), backend)
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
        else:
            cap = cv2.VideoCapture(src)  # a video file, for testing
        if not cap.isOpened():
            sys.exit(f"Could not open camera {src}. Run find_camera.py to see which number your iPhone is.")
        self.cap = cap

    def close_camera(self):
        if self.phone:
            # The link stays up so the phone can still wake Claudy; its frames are just not used.
            self.cap = None
            if self.link:
                self.link.drop_frames()
            return
        if self.cap:
            self.cap.release()
            self.cap = None

    # ---- seeing ---------------------------------------------------------------
    @staticmethod
    def sharpness(frame) -> float:
        g = cv2.cvtColor(shrink(frame, 640), cv2.COLOR_BGR2GRAY)
        return float(cv2.Laplacian(g, cv2.CV_64F).var())

    def update_motion(self, frame, now: float):
        """Compare with the picture from ~0.2 s ago: how much of it changed?"""
        small = cv2.GaussianBlur(cv2.cvtColor(cv2.resize(frame, (160, 90)), cv2.COLOR_BGR2GRAY), (5, 5), 0)
        if self.prev_small is not None:
            changed = float(np.mean(cv2.absdiff(small, self.prev_small) > 18))
            self.motion = 0.7 * self.motion + 0.3 * changed
        if self.prev_small is None or now - self.prev_t >= 0.2:
            self.prev_small, self.prev_t = small, now

    def best_since(self, t0: float):
        frames = [f for f in self.buffer if f[0] >= t0]
        return max(frames, key=lambda f: f[2]) if frames else (self.buffer[-1] if self.buffer else None)

    def add_keyframe(self, t_from: float):
        best = self.best_since(t_from)
        if best is None:
            return
        path = KEYS / f"key_{self.key_n % 6}.jpg"
        self.key_n += 1
        save_jpg(path, best[1], max_side=1600)
        self.keyframes.append((best[0], str(path)))
        self.save_state()

    def step(self, frame, now: float):
        self.update_motion(frame, now)
        if now - self.last_sample >= 1 / SAMPLE_FPS:
            self.buffer.append((now, frame.copy(), self.sharpness(frame)))
            self.last_sample = now
        if now - self.last_save >= 0.5:
            save_jpg(LATEST, frame, max_side=1920)
            best = self.best_since(now - 2)
            if best is not None:
                save_jpg(BEST, best[1], max_side=1920)
            self.last_save = now
            self.save_state()

        moving = self.motion > MOVE
        if moving:
            self.last_move = now
            if self.active_since is None:
                self.active_since = now
        elif self.active_since is not None and now - self.last_move >= SETTLE_S:
            if self.last_move - self.active_since >= MIN_ACTIVE_S:   # a real action just ended
                self.add_keyframe(self.last_move)
                if self.watch and not self.busy and now - self.last_check >= COOLDOWN_S:
                    self.last_check = now
                    self.jobs.put(("check", None, None))
            self.active_since = None

    # ---- talking to Claude ------------------------------------------------------
    def frames_for(self, kind: str, point=None):
        """Pick what Claude sees: recent keyframes plus the clearest frame of the last 2 s."""
        keep = list(self.keyframes)[-(2 if kind == "check" else 3):]
        out = []
        for i, (t, p) in enumerate(keep):
            dst = SEND / f"{kind}_{i}.jpg"
            shutil.copyfile(p, dst)
            out.append((t, dst))
        best = self.best_since(time.time() - 2)
        if point and self.buffer:
            best = self.buffer[-1]   # a tap points at what is on screen now, not the sharpest older frame
        if best is not None and (kind == "ask" or not out):
            dst = SEND / f"{kind}_now.jpg"
            img = best[1]
            if point:
                img = img.copy()
                h, w = img.shape[:2]
                c = (int(float(point["x"]) * w), int(float(point["y"]) * h))
                r = max(12, min(h, w) // 25)
                cv2.circle(img, c, r + 3, (255, 255, 255), 3, cv2.LINE_AA)
                cv2.circle(img, c, r, (0, 0, 255), 4, cv2.LINE_AA)
            save_jpg(dst, img, max_side=1600)
            out.append((best[0], dst))
        return out

    def run_claude(self, prompt: str, model: str) -> str:
        env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}  # use the plan, not API billing
        cmd = [self.claude, "-p", "--allowedTools", "Read", "--output-format", "text"]
        if model:
            cmd += ["--model", model]
        try:
            r = subprocess.run(cmd, input=prompt, cwd=HOME, env=env, capture_output=True, text=True, timeout=180)
        except FileNotFoundError:
            return "ERROR: Claude Code is not installed or not on the PATH."
        except subprocess.TimeoutExpired:
            return "ERROR: Claude took too long to answer."
        return r.stdout.strip() or ("ERROR: " + r.stderr.strip()[:300])

    def worker(self):
        while self.running:
            try:
                kind, question, point = self.jobs.get(timeout=0.5)
            except queue.Empty:
                continue
            if not self.awake:
                continue
            self.busy = True
            if kind == "ask":
                self.to_phone("face", state="thinking")
                self.to_phone("haptic", pattern="heartbeat")
            frames = self.frames_for(kind, point)
            if frames:
                self.to_phone("sending")   # privacy rule: the photo eyes flash before Claude sees a frame
            listing = "\n".join(f"- {p} ({ago(t)})" for t, p in frames) or "- (no frames yet)"
            notes = "\n".join(f"- {n['text']} ({ago(n['t'])})" for n in self.notes[-10:]) or "- (none yet)"
            if kind == "check":
                reply = self.run_claude(CHECK_PROMPT.format(task=self.task, notes=notes, frames=listing),
                                        self.args.watch_model)
                note, say = self.parse_check(reply)
                if note:
                    self.add_note(note)
                if say:
                    self.to_phone("haptic", pattern="attention")
                    self.speak(say, face="concerned")
                elif reply.startswith("ERROR"):
                    print("\n" + reply)
            else:
                self.last_reply = "Thinking..."
                extra = ""
                if point:
                    extra += " (He tapped the spot marked with a red ring in the last frame.)"
                seen_t, lines = self.text_seen
                if lines and time.time() - seen_t < 10:
                    extra += " (Text the phone just read in view: " + " / ".join(lines)[:500] + ")"
                reply = self.run_claude(ASK_PROMPT.format(task=self.task, notes=notes, frames=listing,
                                                          question=question + extra), self.args.ask_model)
                if reply.startswith("ERROR"):
                    print("\n" + reply)
                    self.to_phone("face", state="concerned")
                    self.to_phone("say", text="Sorry, I could not get an answer.", quiet=True)
                else:
                    self.add_note(f"Farhan asked: {question}")
                    self.speak(reply)
            self.busy = False

    @staticmethod
    def parse_check(reply: str):
        note = say = ""
        for line in reply.splitlines():
            if line.upper().startswith("NOTE:"):
                note = line[5:].strip()
            elif line.upper().startswith("SAY:"):
                say = line[4:].strip()
        if say.upper().rstrip(".") == "NONE":
            say = ""
        return note, say

    def add_note(self, text: str):
        self.notes.append({"t": time.time(), "text": text})
        self.notes = self.notes[-MAX_NOTES:]
        write_json(NOTES, self.notes)

    def speak(self, text: str, face: str = "happy"):
        self.last_reply = text
        print(f"\nClaudy: {text}\nYou: ", end="", flush=True)
        if self.link and self.link.connected:
            # The phone is Claudy's head: it talks (or only captions with --quiet), the Mac stays silent.
            self.to_phone("face", state=face)
            self.to_phone("say", text=text, quiet=bool(self.args.quiet))
        elif shutil.which("say") and not self.args.quiet:
            subprocess.Popen(["say", text])

    # ---- the phone (only with --camera phone) -----------------------------------
    def to_phone(self, type_: str, **fields):
        if self.link:
            self.link.send(type_, **fields)

    def approve_device(self, name: str, address: str) -> bool:
        """Called by the link for a device it has never seen; the typing thread takes the answer."""
        answered, answer = threading.Event(), [False]
        self.pending_device = (name, address, answered, answer)
        print(f"\nNew device '{name}' at {address} wants to be Claudy's head. Type yes or no: ", end="", flush=True)
        if not answered.wait(110):   # the link refuses after 120 s; let go of the question first
            print("\nNo answer, so the device was refused.")
        self.pending_device = None
        return answer[0]

    def on_phone(self, msg: dict):
        kind = msg.get("type")
        data = msg.get("data")
        if kind == "hello":
            self.link.send("welcome", brain_version="0.2", task=self.task, watch=self.watch)
            self.to_phone("face", state="idle" if self.awake else "sleeping")
        elif kind == "ask" and str(msg.get("text", "")).strip():
            point = msg.get("point") if isinstance(msg.get("point"), dict) else None
            print(f"\nPhone asks: {msg['text']}" + (f"  (tapped {point})" if point else ""))
            if not self.awake:
                self.set_awake(True)
            self.jobs.put(("ask", str(msg["text"]).strip(), point))
        elif kind == "event":
            name = msg.get("name")
            if name in ("sleep", "wake"):
                self.set_awake(name == "wake")
            elif name == "task" and str(data or "").strip():
                self.task = str(data).strip()
                self.add_note(f"New task: {self.task}")
                print(f"\nTask set from the phone: {self.task}")
            elif name in ("mode", "gesture", "shake", "confirm"):
                print(f"\nPhone: {name} {data if data is not None else ''}")
        elif kind == "text_seen" and isinstance(msg.get("lines"), list):
            self.text_seen = (time.time(), [str(x) for x in msg["lines"]][:20])
        elif kind == "photo":
            print(f"\nPhoto from the phone saved: {msg.get('path')}")

    def save_state(self):
        write_json(STATE, {"t": time.time(), "awake": self.awake, "task": self.task, "watch": self.watch,
                           "keyframes": [{"t": t, "path": p} for t, p in self.keyframes]})

    # ---- typed commands ----------------------------------------------------------
    def typing(self):
        while self.running:
            try:
                line = input("You: ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            low = line.lower()
            if self.pending_device:
                _, _, answered, answer = self.pending_device
                answer[0] = low in ("y", "yes")
                answered.set()
                continue
            if not line:
                continue
            if low in ("quit", "exit"):
                self.running = False
            elif low == "sleep":
                self.set_awake(False)
            elif low == "wake":
                self.set_awake(True)
            elif low in ("watch on", "watch off"):
                self.watch = low.endswith("on")
                print(f"Watching on its own: {'on' if self.watch else 'off'}")
            elif low.startswith("task:"):
                self.task = line[5:].strip()
                self.add_note(f"New task: {self.task}")
                print(f"Task set: {self.task}")
            elif not self.awake:
                print("Claudy is asleep. Type 'wake' first.")
            else:
                self.jobs.put(("ask", line, None))

    def set_awake(self, on: bool):
        self.awake = on
        if on and self.cap is None:
            self.open_camera()
        self.to_phone("face", state="idle" if on else "sleeping")
        if not on:
            self.close_camera()
            self.buffer.clear()
            for p in (LATEST, BEST):
                p.unlink(missing_ok=True)
        self.last_reply = "Awake." if on else "Asleep. Camera off."
        print(self.last_reply)
        self.save_state()

    # ---- window -------------------------------------------------------------------
    def draw(self, frame):
        view = shrink(frame, 960).copy() if frame is not None else np.zeros((540, 960, 3), np.uint8)
        state = ("THINKING" if self.busy else "AWAKE") if self.awake else "ASLEEP"
        if self.phone:
            state += f"  phone: {self.link.device if self.link and self.link.connected else 'not connected'}"
        col = (80, 200, 255) if self.busy else ((90, 220, 120) if self.awake else (120, 120, 120))
        cv2.rectangle(view, (0, 0), (view.shape[1], 34), (20, 20, 20), -1)
        cv2.putText(view, f"Claudy {state}  watch:{'on' if self.watch else 'off'}  task: {self.task[:40]}",
                    (10, 23), cv2.FONT_HERSHEY_SIMPLEX, 0.6, col, 1, cv2.LINE_AA)
        bar = int(min(1.0, self.motion / (MOVE * 4)) * 120)
        cv2.rectangle(view, (view.shape[1] - 132, 10), (view.shape[1] - 132 + bar, 24), (255, 200, 80), -1)
        cv2.rectangle(view, (0, view.shape[0] - 30), (view.shape[1], view.shape[0]), (20, 20, 20), -1)
        cv2.putText(view, self.last_reply[:110], (10, view.shape[0] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5,
                    (235, 235, 235), 1, cv2.LINE_AA)
        return view

    def run(self):
        if not shutil.which(self.claude):
            print("Note: Claude Code ('claude') was not found. Asking and watching will not work until it is installed.")
        self.open_camera()
        threading.Thread(target=self.worker, daemon=True).start()
        threading.Thread(target=self.typing, daemon=True).start()
        print(__doc__.split("Typed commands:")[1].strip() if "Typed commands:" in __doc__ else "")
        frame = None
        try:
            while self.running:
                now = time.time()
                if self.awake and self.cap is not None:
                    ok, new = self.cap.read()   # the phone link waits up to 0.1 s for a frame
                    if ok:
                        frame = new
                        self.step(frame, now)
                    elif self.phone:
                        if not self.link.connected:
                            frame = None
                    elif not self.args.camera.isdigit():
                        break  # test video finished
                    else:
                        time.sleep(0.05)
                        continue
                else:
                    frame = None
                    time.sleep(0.05)
                if not self.args.no_window:
                    cv2.imshow("Claudy eye", self.draw(frame))
                    k = cv2.waitKey(1) & 0xFF
                    if k == ord("q"):
                        break
                    if k == ord(" "):
                        self.set_awake(not self.awake)
                elif not self.args.camera.isdigit() and not self.phone:
                    time.sleep(1 / 30)  # play test videos at real speed
        finally:
            self.running = False
            self.close_camera()
            if self.link:
                self.link.stop()
            cv2.destroyAllWindows()
            write_json(STATE, {"t": 0, "awake": False, "task": self.task, "watch": False, "keyframes": []})


def main():
    p = argparse.ArgumentParser(description="Claudy's eye: watch through the iPhone camera.")
    p.add_argument("--camera", default="1", help="camera number from find_camera.py, 'phone' for the Claudy Phone app, or a video file to test")
    p.add_argument("--task", default="working at his desk", help="what you are doing, e.g. 'building a PC'")
    p.add_argument("--no-watch", action="store_true", help="only answer questions, never speak up on its own")
    p.add_argument("--watch-model", default="haiku", help="model for the quick automatic checks")
    p.add_argument("--ask-model", default="", help="model for your questions (blank = Claude Code's default)")
    p.add_argument("--claude", default="claude", help="path to the Claude Code command")
    p.add_argument("--no-window", action="store_true", help="no video window")
    p.add_argument("--quiet", action="store_true", help="print answers instead of speaking them")
    Eye(p.parse_args()).run()


if __name__ == "__main__":
    main()
