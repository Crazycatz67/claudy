# Claudy Phone: build instructions for Claude Code

You are building **Claudy Phone**, an iPhone app that turns Farhan's iPhone 17 Pro
into the head of his robot assistant "Claudy", plus the additions to the Mac "brain"
that it talks to. Read this whole file before writing code. Then read
`docs/FEATURES.md` (what to build), `docs/PROTOCOL.md` (how phone and Mac talk) and
`docs/PHASES.md` (the order, with a ready-to-paste prompt and a test for each phase).

## Who you are working with

- Farhan is a first-year AI student. He is a beginner in Python and new to Swift,
  Xcode and electronics. He has made games and websites before.
- Explain in simple words. Give steps one at a time. After each phase, tell him
  exactly what to click or run to test it, and wait for his result before moving on.
- When something needs a human (Xcode signing, tapping "Trust" on the phone, granting
  camera permission), say so plainly and give the exact menu path.

## Hard rules

1. **Spend nothing.** No paid services, no paid libraries, no Apple Developer Program
   ($99). The app is installed with a free Apple account ("Personal Team"). Do not
   use capabilities that need a paid account. If a feature turns out to need one,
   stop and tell Farhan before going further.
2. **No API keys, ever.** Claude is reached only through Farhan's Claude subscription:
   on the Mac through Claude Code (`claude -p`), and on the phone through the Claude
   app's "Ask Claude" Shortcut action. Never add `ANTHROPIC_API_KEY`, never call
   `api.anthropic.com` directly, never embed any credential in the app.
3. **One phase at a time.** Build only the phase Farhan asks for. Each phase must
   compile, run on his phone and pass its test in `docs/PHASES.md` before the next.
   Do not scaffold future phases "to save time".
4. **Privacy is a feature.**
   - Camera and mic are off whenever Claudy is asleep. Flipping the phone face down
     sleeps it at once.
   - The eyes turn red for a moment every time a frame is sent off the phone for
     Claude to look at. No frame leaves the phone without that signal.
   - Frames go only to Farhan's own Mac on the local network. Nothing is uploaded
     anywhere else by our code.
   - Before Claudy runs any command on the Mac, it says the command and waits for
     a spoken or tapped "yes".
5. **Fail soft.** If the Mac brain is unreachable, the app keeps its face, touch,
   haptics, tracking, measuring and photo saving working, shows a small "brain
   offline" badge, and reconnects by itself.
6. **Stay small and readable.** Plain SwiftUI and Apple frameworks only. No
   third-party Swift packages unless Farhan agrees. Short files, clear names, a
   comment at the top of each file saying what it is for.
7. **Check, don't assume.** Apple APIs and Xcode change. Before using an API, check
   the SDK installed on this Mac (`xcodebuild -version`, `xcrun --show-sdk-version
   --sdk iphoneos`) and the current Apple documentation. If something in these docs
   no longer matches, tell Farhan and propose the nearest working option.

## Project layout

```
claudy/
  CLAUDE.md               this file
  docs/                   FEATURES.md, PROTOCOL.md, PHASES.md
  brain/                  the Mac side (Python). Stage A already exists here:
    eye.py                  watches a camera, keyframes, watcher, typed questions
    server.py               Claude Desktop connector (look, whats_happening, zoom)
    common.py, find_camera.py, requirements.txt
    phone_link.py           NEW in phase B2: WebSocket server the app connects to
  ClaudyPhone/            the Xcode project (Farhan creates the empty project)
    ClaudyPhone/
      App/                  ClaudyPhoneApp.swift, AppState.swift, Settings
      Face/                 FaceView, Eyes, Expression, widgets
      Input/                Touch gestures, MotionSensor (shake, flip, pickup), Haptics
      Camera/               CameraService, FrameSender, PhotoCapture, Torch
      Vision/               HandTracker, TextReader, FaceFinder
      Depth/                LidarService, Measure
      Voice/                Listener (speech to text), Speaker (text to speech)
      Link/                 BrainLink (WebSocket), Discovery (Bonjour), Messages
      Intents/              App Intents for Shortcuts and the Action button
```

## How the project gets created

Creating an `.xcodeproj` by hand is fragile, so Farhan creates the empty project
himself and you fill it:

1. Xcode, File, New, Project, iOS, App. Product name `ClaudyPhone`, Interface
   SwiftUI, Language Swift. Save it inside `claudy/`.
2. Signing & Capabilities: Team = his personal Apple account, a unique bundle id
   such as `com.farhan.claudyphone`.
3. From then on you add and edit Swift files inside `ClaudyPhone/ClaudyPhone/`.
   Recent Xcode projects sync that folder automatically. If a new file does not
   show up in Xcode, tell Farhan how to add it (right-click the folder, Add Files).

Check that it compiles from the terminal after every change:

```
xcodebuild -project ClaudyPhone/ClaudyPhone.xcodeproj -scheme ClaudyPhone \
  -destination 'generic/platform=iOS' -quiet build CODE_SIGNING_ALLOWED=NO
```

Camera, LiDAR, haptics and motion do not work in the Simulator. Real testing is
always on the iPhone, run from Xcode with the phone plugged in or on Wi-Fi.

## Technical choices (use these unless they prove impossible)

| Need | Use |
|---|---|
| UI and face | SwiftUI, with `Canvas` or shapes for the eyes; `TimelineView` for animation |
| Camera | AVFoundation `AVCaptureSession`. Try `AVCaptureMultiCamSession` for front and back together; fall back to one camera at a time |
| LiDAR depth | AVFoundation LiDAR depth camera, or ARKit scene depth if that is simpler for measuring |
| Hands, text, faces | Vision framework (hand pose, text recognition, face rectangles), all on-device |
| Haptics | Core Haptics, with a simple fallback to `UIImpactFeedbackGenerator` |
| Shake, flip, pick-up | Core Motion (device motion: gravity and user acceleration) |
| Speech to text | Speech framework with on-device recognition required |
| Text to speech | `AVSpeechSynthesizer` |
| Link to the Mac | `URLSessionWebSocketTask`; find the Mac with Bonjour (`NWBrowser`) |
| Shortcuts and Action button | App Intents |
| Keep screen on | `isIdleTimerDisabled = true` while awake |
| 3D scan (later) | RealityKit Object Capture |

Info.plist keys you will need as phases arrive: camera, microphone, speech
recognition, motion, local network usage descriptions, and the Bonjour service
type `_claudy._tcp`.

## Known limits to design around, not fight

- The app can use the camera only while it is open on screen. That is fine: the
  screen is the face. Keep the phone on a MagSafe charger for long sessions.
- A free Apple account's build stops opening after 7 days. Re-run from Xcode.
- Claude takes a few seconds to answer. Show the thinking face and the heartbeat
  haptic at once so the wait feels alive.
- Claude sees still frames, not video. The Mac picks the frames worth sending.
- The face is on the front; the best camera and LiDAR are on the back. Hence two
  modes, Buddy (front camera, face toward Farhan) and Inspect (back camera on the
  work, face shrunk to a corner bubble). See `docs/FEATURES.md`.
- There is no laser on a phone. "Pointing" is a crosshair on screen for now.

## Definition of done for any phase

- Compiles with no warnings you introduced.
- Runs on Farhan's iPhone and passes that phase's test in `docs/PHASES.md`.
- Sleeping really turns the camera and mic off (the iOS green and orange dots go out).
- You told Farhan in a few plain sentences what you built, how to try it, and
  anything that did not work.
