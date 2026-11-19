# Claudy

Claudy is a desk robot assistant whose head is an iPhone. The phone shows Claudy's face
and handles touch, motion, haptics, the camera, LiDAR and voice. A small "brain" program
on the Mac watches through the phone and asks Claude for help (through Claude Code on a
Claude subscription, with no API keys).

By Farhan Amin.

## What's here

| Folder | What it is |
|---|---|
| `ClaudyPhone/` | The iPhone app (SwiftUI, Apple frameworks only) |
| `brain/` | The Mac brain (Python): camera watcher, phone link, assistant features, remote page |
| `docs/` | Feature list, phone and Mac message protocol, build phases |

## Features

- **Face:** blinking eyes, 9 moods, petting with a purr buzz, shake to cancel, face-down sleep
- **Follow me:** the eyes follow your face and hands, using the selfie camera on the phone only
- **Buddy and Inspect modes:** in Inspect, tap anything to ask what it is, pinch to zoom, read text, auto flashlight
- **LiDAR:** live distance, and drag a box to measure a part
- **Voice:** hold to talk, "Hey Claudy" (off until you turn it on), Action button and Siri actions, spoken answers with captions
- **Gestures:** thumbs up takes a photo, open palm pauses watching, pointing marks "this one"
- **Brain on the Mac:** speaks up when something looks wrong, desk memory, step coach, session summaries with a time-lapse, task presets, a local remote page, and Mac actions that always ask yes or no first

## Privacy

Camera and microphone are off while Claudy sleeps, and every camera feature has its own
switch. Speech is turned into text on the phone. Pictures go only to your own Mac on the
local network, and the eyes flash red whenever one is sent to Claude.

See `brain/README.md` to set up the Mac side.
