"""A pretend Claudy Phone, for testing the Mac side without the iPhone.

It connects to phone_link.py (or eye.py --camera phone), sends `hello`, some made-up
camera frames (a moving coloured square, no real camera), an `ask`, and prints every
message the Mac sends back. It answers `ping` with `pong`, as the app must.

    python fake_phone.py                                   (Mac on this computer)
    python fake_phone.py --ask "what is this?" --point 0.5 0.5 --sleep
"""
import argparse
import json
import threading
import time

import cv2
import numpy as np
from websockets.exceptions import ConnectionClosed
from websockets.sync.client import connect


def make_frame(i: int, stop_at: int, w: int = 1280, h: int = 720) -> bytes:
    img = np.full((h, w, 3), 40, np.uint8)
    # Moves, then holds still, so the eye sees an action end and keeps a keyframe.
    x = int((min(i, stop_at) * 60) % (w - 200))
    cv2.rectangle(img, (x, 260), (x + 200, 460), (60, 160, 240), -1)
    cv2.putText(img, f"fake phone frame {i}", (40, 80), cv2.FONT_HERSHEY_SIMPLEX, 1.6, (255, 255, 255), 3)
    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return buf.tobytes()


def main():
    p = argparse.ArgumentParser(description="Pretend to be the Claudy Phone app.")
    p.add_argument("--url", default="ws://127.0.0.1:8765/ws")
    p.add_argument("--device", default="Fake iPhone")
    p.add_argument("--frames", type=int, default=12, help="frames to send, 3 a second")
    p.add_argument("--ask", default="What do you see?", help="question to send after the frames ('' = none)")
    p.add_argument("--point", type=float, nargs=2, metavar=("X", "Y"), help="tap-to-point, 0-1 from top left")
    p.add_argument("--photo", action="store_true", help="also send one full-detail photo")
    p.add_argument("--sleep", action="store_true", help="send event sleep at the end")
    p.add_argument("--wait", type=float, default=15, help="seconds to keep listening after the ask")
    args = p.parse_args()

    got = []
    with connect(args.url, max_size=16 * 2**20, compression=None, open_timeout=10) as ws:
        def listen():
            try:
                for data in ws:
                    if isinstance(data, bytes):
                        print(f"<- {len(data)} bytes of binary (unexpected)")
                        continue
                    msg = json.loads(data)
                    got.append(msg)
                    if msg.get("type") == "ping":
                        ws.send(json.dumps({"type": "pong", "t": msg.get("t")}))
                    print(f"<- {json.dumps(msg)}", flush=True)
            except ConnectionClosed as e:
                print(f"connection closed: {e.rcvd.code if e.rcvd else '?'} {e.rcvd.reason if e.rcvd else ''}")

        threading.Thread(target=listen, daemon=True).start()
        ws.send(json.dumps({"type": "hello", "device": args.device, "app_version": "fake-1", "mode": "inspect"}))
        print(f"-> hello as '{args.device}'")
        for i in range(args.frames):
            jpg = make_frame(i, args.frames * 2 // 3)
            ws.send(json.dumps({"type": "frame", "t": time.time(), "mode": "inspect", "lens": "wide",
                                "w": 1280, "h": 720, "distance_cm": 32.5, "hands": [], "sharp": 0.8}))
            ws.send(jpg)
            time.sleep(1 / 3)
        print(f"-> {args.frames} frames")
        ws.send(json.dumps({"type": "text_seen", "lines": ["FAKE LABEL 123"]}))
        if args.photo:
            ws.send(json.dumps({"type": "photo", "id": "test1", "w": 1280, "h": 720, "distance_cm": None}))
            ws.send(make_frame(99, 99))
            print("-> photo test1")
        if args.ask:
            ask = {"type": "ask", "text": args.ask}
            if args.point:
                ask["point"] = {"x": args.point[0], "y": args.point[1]}
            ws.send(json.dumps(ask))
            print(f"-> {json.dumps(ask)}")
        end = time.time() + args.wait
        while time.time() < end and not any(m.get("type") == "say" for m in got):
            time.sleep(0.2)
        time.sleep(1)
        if args.sleep:
            ws.send(json.dumps({"type": "event", "name": "sleep", "data": None}))
            print("-> event sleep")
            time.sleep(1)
    kinds = [m.get("type") for m in got]
    print("summary:", " ".join(kinds) or "(nothing came back)")


if __name__ == "__main__":
    main()
