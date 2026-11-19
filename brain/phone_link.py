"""Claudy link, Mac side: the WebSocket server the Claudy Phone app connects to.

It follows docs/PROTOCOL.md. eye.py uses it for `--camera phone`; you can also run it
alone to check that the phone reaches the Mac:
    python phone_link.py          (prints every message, keeps the newest frame)

What other code relies on (the contract):
    link = PhoneLink(approve=None, on_message=None, port=8765)
    link.start()                 server + Bonjour in a background thread; returns at once
    link.read(timeout) -> (ok, frame)   newest JPEG not read yet, as a BGR numpy image
    link.meta                    the `frame` message that described that image (dict)
    link.connected -> bool       an accepted phone is connected right now
    link.device -> str | None    its name from `hello`
    link.send(type, **fields)    send one JSON message; quietly does nothing with no phone
    link.stop()
  approve(name, address) -> bool   called (in a worker thread) the first time a device
      name is seen; True remembers it in ~/.claudy/devices.json. Default asks at the terminal.
  on_message(msg: dict)        called (in the link thread, so keep it quick) for every JSON
      message from an accepted phone except frame, photo and pong. Photos are saved to
      ~/.claudy/photos/<id>.jpg and passed on as {"type": "photo", ..., "path": ...}.

Rules it enforces: only private, link-local or loopback addresses may connect; only the
path /ws; one phone at a time (a newly accepted phone replaces the old one); a JSON
`ping` every 5 s, and a phone that sends nothing for 20 s is dropped.
"""
import asyncio
import ipaddress
import json
import os
import shutil
import socket
import subprocess
import threading
import time

import cv2
import numpy as np
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

from common import HOME, read_json, write_json

PORT = 8765
PATH = "/ws"
SERVICE = "_claudy._tcp"
BRAIN_VERSION = "0.2"
DEVICES = HOME / "devices.json"
PHOTOS = HOME / "photos"
PING_S = 5
SILENT_DROP_S = 20      # phone pongs every 5 s and sends ~3 frames a second, so 20 s silent = gone
APPROVE_WAIT_S = 120    # how long a new device may wait for "yes" at the terminal

# The doc's list (10.x, 172.16-31.x, 192.168.x, link-local) plus loopback, so
# fake_phone.py can test on this Mac, and the IPv6 equivalents.
ALLOWED_NETS = [ipaddress.ip_network(n) for n in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "127.0.0.0/8",
    "fe80::/10", "fc00::/7", "::1/128")]


def is_local(address: str) -> bool:
    try:
        ip = ipaddress.ip_address(address.split("%")[0])   # drop an IPv6 zone like %en0
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return any(ip in n for n in ALLOWED_NETS)


def ask_terminal(name: str, address: str) -> bool:
    answer = input(f"\nNew device '{name}' at {address} wants to connect to Claudy. Allow it? (yes/no) ")
    return answer.strip().lower() in ("y", "yes")


class PhoneLink:
    def __init__(self, approve=None, on_message=None, port: int = PORT):
        self.approve = approve or ask_terminal
        self.on_message = on_message or (lambda msg: None)
        self.port = port
        self.loop = None
        self.ws = None              # the accepted phone's connection
        self.device = None
        self.meta = {}
        self.last_seen = 0.0
        self.frames_in = 0
        self._frame = None
        self._fresh = threading.Condition()
        self._ready = threading.Event()
        self._stop = None
        self._bonjour = None
        self._approving = threading.Lock()   # one terminal question at a time

    # ---- used by eye.py (any thread) -----------------------------------------------
    @property
    def connected(self) -> bool:
        return self.ws is not None

    def start(self):
        threading.Thread(target=self._run, daemon=True, name="phone-link").start()
        if not self._ready.wait(5):
            raise RuntimeError("phone link did not start")
        self._advertise()

    def stop(self):
        if self._bonjour:
            self._bonjour.terminate()
            self._bonjour = None
        if self.loop and self._stop:
            self.loop.call_soon_threadsafe(self._stop.set)

    def read(self, timeout: float = 0.1):
        """Like cv2.VideoCapture.read(): (True, frame) for a new frame, else (False, None)."""
        with self._fresh:
            if self._frame is None:
                self._fresh.wait(timeout)
            frame, self._frame = self._frame, None
        return (frame is not None), frame

    def drop_frames(self):
        with self._fresh:
            self._frame = None

    def send(self, type_: str, **fields):
        ws, loop = self.ws, self.loop
        if ws is None or loop is None:
            return
        text = json.dumps({"type": type_, **fields})
        fut = asyncio.run_coroutine_threadsafe(ws.send(text), loop)
        fut.add_done_callback(lambda f: f.exception())   # a closed socket is not an error here

    # ---- Bonjour ---------------------------------------------------------------------------
    def _advertise(self):
        # macOS ships dns-sd, so no extra library; it advertises until we terminate it.
        if not shutil.which("dns-sd"):
            print("Note: dns-sd not found, so the phone cannot find the Mac by itself. Use its manual address.")
            return
        name = f"Claudy on {socket.gethostname().split('.')[0]}"
        # A tiny shell minder stops dns-sd when Python ends in any way (even kill -9), so a
        # stale "Claudy" never stays advertised with nothing listening behind it.
        minder = ('dns-sd -R "$1" "$2" local "$3" "path=$4" >/dev/null 2>&1 & d=$!; '
                  'trap \'kill $d 2>/dev/null; exit\' TERM INT; '
                  'while kill -0 "$5" 2>/dev/null && kill -0 $d 2>/dev/null; do sleep 1; done; kill $d 2>/dev/null')
        self._bonjour = subprocess.Popen(["sh", "-c", minder, "minder", name, SERVICE, str(self.port), PATH,
                                          str(os.getpid())], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # ---- server (link thread) ------------------------------------------------------------
    def _run(self):
        asyncio.run(self._main())

    async def _main(self):
        self.loop = asyncio.get_running_loop()
        self._stop = asyncio.Event()
        # Our own JSON ping (the phone shows "offline" without it), so the library's
        # control-frame pings are off; frames are already JPEG, so no compression.
        async with serve(self._handle, None, self.port, process_request=self._check_request,
                         ping_interval=None, compression=None, max_size=16 * 2**20):
            self._ready.set()
            await self._stop.wait()

    def _check_request(self, connection, request):
        host = connection.remote_address[0] if connection.remote_address else ""
        if not is_local(host):
            print(f"\nRefused a connection from {host}: not on the local network.")
            return connection.respond(403, "Claudy only talks to the local network.\n")
        if request.path.split("?")[0] != PATH:
            return connection.respond(404, "Claudy listens on /ws\n")
        return None

    async def _handle(self, ws):
        address = ws.remote_address[0]
        try:
            hello = json.loads(await asyncio.wait_for(ws.recv(), 10))
        except (asyncio.TimeoutError, ValueError, TypeError, ConnectionClosed):
            await ws.close(1008, "send hello first")
            return
        name = str(hello.get("device") or "unnamed device") if isinstance(hello, dict) else ""
        if not isinstance(hello, dict) or hello.get("type") != "hello" or not await self._allowed(name, address):
            await ws.close(1008, "not accepted on the Mac")
            return

        old, self.ws, self.device = self.ws, ws, name
        if old is not None:
            await old.close(1000, "another phone connected")
        self.last_seen = time.time()
        print(f"\nPhone connected: {name} ({address}), app {hello.get('app_version', '?')}, "
              f"mode {hello.get('mode', '?')}")
        self.on_message(hello)
        pinger = asyncio.create_task(self._ping(ws))
        try:
            await self._receive(ws)
        except ConnectionClosed:
            pass
        finally:
            pinger.cancel()
            if self.ws is ws:
                self.ws = None
                self.drop_frames()
                print(f"\nPhone disconnected: {name}")
                self.on_message({"type": "disconnected", "device": name})

    async def _allowed(self, name: str, address: str) -> bool:
        if name in read_json(DEVICES, []):
            return True
        loop = asyncio.get_running_loop()

        def ask():
            with self._approving:
                if name in read_json(DEVICES, []):      # accepted while this one was waiting
                    return True
                ok = bool(self.approve(name, address))
                if ok:
                    write_json(DEVICES, sorted(set(read_json(DEVICES, [])) | {name}))
                print(f"{'Accepted' if ok else 'Refused'} '{name}'.")
                return ok
        try:
            return await asyncio.wait_for(loop.run_in_executor(None, ask), APPROVE_WAIT_S)
        except asyncio.TimeoutError:
            print(f"\nNo answer for '{name}', so it was refused. It can try again.")
            return False

    async def _ping(self, ws):
        while True:
            await asyncio.sleep(PING_S)
            if time.time() - self.last_seen > SILENT_DROP_S:
                print("\nPhone went quiet for 20 s, dropping it.")
                await ws.close(1001, "no messages for 20 s")
                return
            try:
                await ws.send(json.dumps({"type": "ping", "t": time.time()}))
            except ConnectionClosed:
                return

    async def _receive(self, ws):
        described = None    # the frame/photo message waiting for its JPEG
        async for data in ws:
            self.last_seen = time.time()
            if isinstance(data, bytes):
                if described is not None:
                    self._got_jpeg(described, data)
                described = None        # a JPEG with no message before it is ignored
                continue
            try:
                msg = json.loads(data)
            except ValueError:
                continue
            if not isinstance(msg, dict):
                continue
            kind = msg.get("type")
            if kind in ("frame", "photo"):
                described = msg
            elif kind == "pong":
                pass
            else:
                self.on_message(msg)    # unknown types are passed on; callers ignore them

    def _got_jpeg(self, msg: dict, data: bytes):
        frame = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
        if frame is None:
            print("\nGot a picture from the phone that is not a readable JPEG; skipped it.")
            return
        if msg.get("type") == "photo":
            PHOTOS.mkdir(parents=True, exist_ok=True)
            safe = "".join(c for c in str(msg.get("id", "photo")) if c.isalnum() or c in "-_")[:40] or "photo"
            path = PHOTOS / f"{safe}.jpg"
            path.write_bytes(data)
            self.on_message({**msg, "path": str(path)})
            return
        with self._fresh:
            self._frame, self.meta = frame, msg
            self.frames_in += 1
            self._fresh.notify_all()


def main():
    import argparse
    p = argparse.ArgumentParser(description="Run only the phone link and print what the phone sends.")
    p.add_argument("--port", type=int, default=PORT)
    args = p.parse_args()
    link = PhoneLink(on_message=lambda m: print(f"\nphone: {json.dumps(m)[:200]}"), port=args.port)
    link.start()
    print(f"Listening on port {args.port}, path {PATH}, Bonjour {SERVICE}. Ctrl+C to stop.")
    try:
        while True:
            ok, frame = link.read(1.0)
            if ok:
                h, w = frame.shape[:2]
                print(f"frame {link.frames_in}: {w}x{h} {link.meta.get('mode', '?')}", end="\r")
    except KeyboardInterrupt:
        pass
    finally:
        link.stop()


if __name__ == "__main__":
    main()
