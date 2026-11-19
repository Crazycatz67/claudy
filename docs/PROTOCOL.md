# Claudy link: how the phone and the Mac brain talk

One WebSocket connection, opened by the phone to the Mac. Keep this file and both
sides of the code in step: if you change a message, change it here first.

## Finding the brain

- The Mac advertises a Bonjour service: type `_claudy._tcp`, port `8765`.
- The phone browses for it and connects to `ws://<mac>:8765/ws`.
- Settings has a manual address field as a backup (some campus Wi-Fi networks block
  device discovery; a personal hotspot or a travel router fixes that).
- Local network only. The Mac side must refuse connections that do not come from a
  private address (10.x, 172.16-31.x, 192.168.x, or link-local), and must show the
  connecting device's name the first time so Farhan can accept it.

## Message format

- **Text messages** are JSON objects with a `type` field.
- **Binary messages** are JPEG images. Each one is described by the `frame` or
  `photo` JSON message sent just before it.

## Phone to Mac

| type | Fields | Meaning |
|---|---|---|
| `hello` | `device`, `app_version`, `mode` | First message after connecting |
| `frame` | `t`, `mode` ("buddy" or "inspect"), `lens`, `w`, `h`, `distance_cm` (or null), `hands` (list of boxes 0-1), `sharp` | Describes the JPEG that follows. About 3 a second, long side about 1280 |
| `photo` | `id`, `w`, `h`, `distance_cm` | Describes a full-detail JPEG that follows, in answer to `capture` |
| `ask` | `text`, `point` (optional `{x, y}` 0-1 for tap-to-point) | Farhan asked something, by voice, typing or tap |
| `event` | `name`, `data` | Something happened: `wake`, `sleep`, `shake`, `gesture` (data: which), `mode`, `task` (data: text), `confirm` (data: id, yes or no) |
| `text_seen` | `lines` | Text the phone read on-device, so the brain can use it without spending a Claude request |
| `pong` | `t` | Answer to `ping` |

## Mac to phone

| type | Fields | Meaning |
|---|---|---|
| `welcome` | `brain_version`, `task`, `watch` | Answer to `hello` |
| `face` | `state` (idle, listening, thinking, happy, concerned, warning, sleeping), `look` (optional `{x, y}`) | Set the expression |
| `say` | `text`, `quiet` (bool) | Speak this (or caption only if quiet) |
| `haptic` | `pattern` (tap, click, heartbeat, attention, stop, purr) | Play a haptic |
| `sending` | none | A frame is being sent to Claude now: flash the photo eyes |
| `torch` | `level` 0-1 | Flashlight |
| `light` | `color` (hex) or null | Screen light on or off |
| `capture` | `id`, `lens` (optional), `focus_cm` (optional) | Take one full-detail photo and send it as `photo` |
| `widget` | `name` (face, radar, crosshair, timer, light), `data` | Show a widget; crosshair data is `{x, y}`, timer data is seconds |
| `confirm` | `id`, `text` | Show the yes or no card for a command |
| `ping` | `t` | Keep-alive, every 5 seconds |

## Rules

- When the phone sleeps it sends `event: sleep`, stops the camera and stops sending
  frames. The Mac must then clear its frame buffer, as `eye.py` already does.
- If no `ping` arrives for 15 seconds the phone shows the offline badge and retries
  every few seconds.
- Unknown message types are ignored, so old and new versions can talk.
- The Mac never asks the phone for audio. Speech is turned into text on the phone
  and sent as `ask`.

## How this plugs into Stage A

`brain/phone_link.py` is the WebSocket server. It writes incoming frames to exactly
the same places `eye.py` uses today (the frame buffer, `latest.jpg`, `best.jpg`,
keyframes), so the watcher, the questions and the Claude Desktop tools keep working
unchanged. `eye.py` gains `--camera phone` to use the link instead of a camera
number, and its `speak()` sends `say` and `face` to the phone when one is connected.
