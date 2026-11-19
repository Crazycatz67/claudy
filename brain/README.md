# Claudy brain, Stage A: your iPhone as Claudy's eyes

Everything here is free. It uses Apple's Continuity Camera (iPhone as a wireless
webcam), Python, and the Claude Max plan you already have.

## What's in the folder

| File | What it does |
|---|---|
| `eye.py` | Watches the iPhone camera non-stop while awake. Remembers clear frames from every moment something changed, checks with Claude when you finish an action, and answers your typed questions out loud. |
| `server.py` | Lets Claude Desktop see through Claudy: tools `look`, `whats_happening` and `zoom`. |
| `find_camera.py` | Finds which camera number is your iPhone. |
| `common.py` | Shared helpers. |

## Setup (one time, about 15 minutes)

Do these in order. Each step should work before you go to the next.

**1. Put the folder in place.** Unzip the kit so this folder is `~/Developer/claudy/brain`. Open Terminal and go there:

```
cd ~/Developer/claudy/brain
```

**2. Make a Python environment and install the three libraries.**

```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

If `python3` is missing: `brew install python`. Every new Terminal window needs
`source .venv/bin/activate` again before running the scripts.

**3. Get the iPhone ready.** Same Apple Account on the iPhone and Mac, Wi-Fi and
Bluetooth on for both. Put the phone on a stand or MagSafe mount, locked, in
landscape, back camera facing your desk.

**4. Find the iPhone's camera number.**

```
python find_camera.py
```

The first time, macOS asks whether Terminal may use the camera: allow it. Open the
saved `camera_0.jpg`, `camera_1.jpg`... The one showing your desk from the phone is
your number. It is often 1 or 2 (0 is usually the MacBook's own camera).

**5. Check Claude Code is signed in to your Max plan.**

```
claude
```

If it asks you to log in, choose your Claude account (not an API key). Type `/exit`.
Then check this prints an empty line, so nothing bills as API usage:

```
echo $ANTHROPIC_API_KEY
```

**6. Wake Claudy.** Use your camera number in place of 1:

```
python eye.py --camera 1 --task "building a PC"
```

A video window opens. Move something on the desk and stop: about 2 seconds later
Claudy checks quietly and only speaks if it sees a problem. Click back into Terminal
and type a question, for example `what am I holding?`, then press Enter.

**7. (Optional) Let Claude Desktop see through Claudy.** In Claude Desktop open
Settings, then Developer, then Edit Config. Add this, replacing `farhanamin` if your
Mac username is different:

```json
{
  "mcpServers": {
    "claudy": {
      "command": "/Users/farhanamin/Developer/claudy/brain/.venv/bin/python",
      "args": ["/Users/farhanamin/Developer/claudy/brain/server.py"]
    }
  }
}
```

If the file already has an `mcpServers` section, add only the `"claudy": {...}` part
inside it. Quit and reopen Claude Desktop. With `eye.py` running, ask Claude "what's
on my desk?" and it will use the tools.

## Using it

| You type | What happens |
|---|---|
| any question | Claude answers out loud from what Claudy has already seen |
| `task: soldering the LED board` | tells Claudy what you are doing, so its checks are smarter |
| `watch off` / `watch on` | stop or start speaking up on its own |
| `sleep` / `wake` | camera off / on (or press space in the video window) |
| `quit` | stop (or press q in the video window) |

## Tuning

At the top of `eye.py`:

- Too chatty: raise `COOLDOWN_S` (seconds between automatic checks, default 25).
- Misses actions: lower `MOVE`. Triggers on nothing: raise it.
- Automatic checks use the fast `haiku` model. If Claude Code rejects that name, run
  with `--watch-model ""` to use its default model.

## If something goes wrong

- **"Could not open camera"**: wrong number, or Terminal lacks camera permission
  (System Settings, Privacy & Security, Camera).
- **The iPhone does not appear**: unlock it once, check both devices use the same Apple
  Account, and turn Continuity Camera on (iPhone Settings, General, AirPlay &
  Continuity).
- **"ERROR: Claude Code is not installed"**: install it, or pass the full path with
  `--claude /path/to/claude`.
- **Claude Desktop says Claudy can't see**: `eye.py` must be running in Terminal.
