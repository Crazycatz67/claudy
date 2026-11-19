"""Claudy's remote page (C1): live view, last answers and sleep/wake/ask from any device on your Wi-Fi.

Started by eye.py with --remote. Open http://<mac-name>.local:8766 on a laptop or tablet
on the same network and type the PIN that eye.py printed.

Safety rules it keeps:
  - Only private, link-local or loopback addresses get any answer (same filter as phone_link).
  - Nothing but the PIN form works without the PIN. A right PIN gives a random cookie for
    this run only; 5 wrong PINs lock the form for 60 s.
  - Commands must be POSTed as JSON with the header X-Claudy: 1 (a plain link or form on
    another web site cannot send that), and the cookie is SameSite=Strict.
  - It never runs Mac commands: an "open ..." typed here still needs a yes on the phone.

What eye.py relies on (the contract):
    page = RemotePage(get_state, on_command, latest_jpg, port=8766, pin=None)
    page.start()          serves in a background thread; prints nothing; page.pin is the PIN
    page.stop()
  get_state() -> dict     JSON-safe; shown as is (awake, task, watch, step, answers [{t, q, a}])
  on_command(name, text)  name is "sleep", "wake" or "ask"; called in a server thread
  latest_jpg              Path of the newest frame (missing while asleep = no picture)
"""
import http.cookies
import json
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from phone_link import is_local

PORT = 8766
STREAM_FPS = 3

PAGE = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Claudy</title><style>
body{font-family:-apple-system,system-ui,sans-serif;background:#111;color:#eee;margin:0;padding:12px;max-width:900px}
img{width:100%;background:#222;border-radius:8px;min-height:120px}
button,input{font-size:16px;padding:8px 12px;border-radius:6px;border:0;margin:4px 4px 4px 0}
button{background:#3a6;color:#fff}input{width:60%}
#state{color:#9cf;margin:8px 0}.a{border-top:1px solid #333;padding:6px 0}.q{color:#aaa}
</style></head><body>
<h3>Claudy</h3><img id="v" src="/stream" alt="live view (none while asleep)">
<div id="state">...</div>
<button onclick="cmd('wake')">Wake</button><button onclick="cmd('sleep')">Sleep</button><br>
<input id="q" placeholder="Ask Claudy..." onkeydown="if(event.key=='Enter')ask()"><button onclick="ask()">Ask</button>
<div id="answers"></div>
<script>
function cmd(name,text){fetch('/cmd',{method:'POST',headers:{'Content-Type':'application/json','X-Claudy':'1'},
 body:JSON.stringify({name:name,text:text||''})}).then(r=>{if(r.status==401)location.reload()})}
function ask(){const q=document.getElementById('q');if(q.value.trim()){cmd('ask',q.value);q.value=''}}
function esc(s){return String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
let wasAwake=null;
async function poll(){try{const s=await (await fetch('/state.json')).json();
 document.getElementById('state').textContent=(s.awake?'Awake':'Asleep')+(s.busy?', thinking':'')+' | task: '+s.task+
  ' | watch: '+(s.watch?'on':'off')+(s.step?' | '+s.step:'')+(s.phone?' | phone: '+s.phone:'');
 if(s.awake&&wasAwake===false)document.getElementById('v').src='/stream?'+Date.now();
 wasAwake=s.awake;
 document.getElementById('answers').innerHTML=(s.answers||[]).slice().reverse().map(a=>
  '<div class="a">'+(a.q?'<div class="q">'+esc(a.q)+'</div>':'')+esc(a.a)+'</div>').join('');
}catch(e){} setTimeout(poll,1500)}
poll();
</script></body></html>"""

LOGIN = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Claudy</title><style>body{font-family:system-ui;background:#111;color:#eee;padding:24px}
input,button{font-size:20px;padding:8px;border-radius:6px;border:0}</style></head><body>
<h3>Claudy</h3><p>Type the PIN shown in the Mac's Terminal.</p>%s
<form method="post" action="/login"><input name="pin" inputmode="numeric" autofocus> <button>Open</button></form></body></html>"""


class RemotePage:
    def __init__(self, get_state, on_command, latest_jpg: Path, port: int = PORT, pin=None):
        self.get_state, self.on_command, self.latest = get_state, on_command, Path(latest_jpg)
        self.port = port
        self.pin = pin or f"{secrets.randbelow(10**6):06d}"
        self.token = secrets.token_urlsafe(24)
        self.fails = []          # times of wrong PINs
        self.httpd = None
        self.running = False

    def start(self):
        page = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):   # keep the Terminal for Claudy's own messages
                pass

            def setup(self):
                super().setup()
                self.local = is_local(self.client_address[0])

            def _send(self, code, body=b"", ctype="text/plain; charset=utf-8", headers=()):
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                for k, v in headers:
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(body)

            def _authed(self):
                c = http.cookies.SimpleCookie(self.headers.get("Cookie", ""))
                return "claudy" in c and secrets.compare_digest(c["claudy"].value, page.token)

            def do_GET(self):
                if not self.local:
                    return self._send(403, b"Local network only.")
                path = self.path.split("?")[0]
                if not self._authed():
                    if path == "/":
                        return self._send(200, (LOGIN % "").encode(), "text/html; charset=utf-8")
                    return self._send(401, b"PIN needed.")
                if path == "/":
                    return self._send(200, PAGE.encode(), "text/html; charset=utf-8")
                if path == "/state.json":
                    return self._send(200, json.dumps(page.get_state()).encode(), "application/json")
                if path == "/latest.jpg":
                    try:
                        return self._send(200, page.latest.read_bytes(), "image/jpeg")
                    except OSError:
                        return self._send(404, b"Asleep: no picture.")
                if path == "/stream":
                    return self._stream()
                self._send(404, b"Not found.")

            def _stream(self):
                # MJPEG: every browser shows it in a plain <img>. It ends when Claudy sleeps
                # (no picture), and the page reopens it on wake.
                self.send_response(200)
                self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                last = None
                try:
                    while page.running:
                        try:
                            st = page.latest.stat().st_mtime
                            jpg = page.latest.read_bytes() if st != last else None
                        except OSError:
                            return
                        if jpg:
                            last = st
                            self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: "
                                             + str(len(jpg)).encode() + b"\r\n\r\n" + jpg + b"\r\n")
                        time.sleep(1 / STREAM_FPS)
                except (BrokenPipeError, ConnectionResetError):
                    return

            def do_POST(self):
                if not self.local:
                    return self._send(403, b"Local network only.")
                n = min(int(self.headers.get("Content-Length") or 0), 4096)
                body = self.rfile.read(n).decode("utf-8", "replace")
                path = self.path.split("?")[0]
                if path == "/login":
                    now = time.time()
                    page.fails = [t for t in page.fails if now - t < 60]
                    if len(page.fails) >= 5:
                        return self._send(429, (LOGIN % "<p>Too many tries. Wait a minute.</p>").encode(),
                                          "text/html; charset=utf-8")
                    pin = "".join(c for c in body.split("pin=", 1)[-1] if c.isdigit())
                    if secrets.compare_digest(pin, page.pin):
                        return self._send(303, b"", headers=[("Location", "/"), (
                            "Set-Cookie", f"claudy={page.token}; Path=/; HttpOnly; SameSite=Strict")])
                    page.fails.append(now)
                    return self._send(401, (LOGIN % "<p>Wrong PIN.</p>").encode(), "text/html; charset=utf-8")
                if path != "/cmd":
                    return self._send(404, b"Not found.")
                if not self._authed():
                    return self._send(401, b"PIN needed.")
                if self.headers.get("X-Claudy") != "1":
                    return self._send(403, b"Missing X-Claudy header.")
                try:
                    msg = json.loads(body)
                    name, text = str(msg.get("name", "")), str(msg.get("text", ""))[:500]
                except (ValueError, AttributeError):
                    return self._send(400, b"Bad JSON.")
                if name not in ("sleep", "wake", "ask") or (name == "ask" and not text.strip()):
                    return self._send(400, b"Unknown command.")
                page.on_command(name, text.strip())
                self._send(200, b'{"ok": true}', "application/json")

        ThreadingHTTPServer.daemon_threads = True
        self.httpd = ThreadingHTTPServer(("0.0.0.0", self.port), Handler)
        self.running = True
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def stop(self):
        self.running = False
        if self.httpd:
            self.httpd.shutdown()
            self.httpd.server_close()
