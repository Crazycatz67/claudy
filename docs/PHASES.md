# Claudy Phone: build phases

Build these in order. Each phase lists the feature IDs from `FEATURES.md`, a prompt
Farhan pastes into Claude Code, and the test that must pass before the next phase.

How to start a session: open Terminal, `cd ~/Developer/claudy`, run `claude`, choose
the Opus 5.5 model with `/model`, then paste the phase prompt.

---

## Phase 0: set up (once)

Farhan does this, with Claude Code's help if needed.

1. Finish Stage A first: `brain/README.md`. Claude must be able to see through the
   phone using Continuity Camera before any app work starts.
2. Install Xcode from the Mac App Store (free, large download).
3. Xcode, Settings, Accounts: add your Apple account.
4. Create the empty project as described in `CLAUDE.md`.
5. Plug the iPhone in. On the phone: Settings, Privacy & Security, Developer Mode, on.
   Run the empty app once from Xcode. On the phone: Settings, General, VPN & Device
   Management, trust your developer certificate.

**Test:** the empty "Hello, world" app opens on the iPhone.

---

## Phase B1: the face (features F1 to F13)

No camera and no Mac yet. This is Claudy's personality.

**Prompt to paste:**

> Read CLAUDE.md and the docs folder. Build phase B1 only: features F1 to F13. The
> app opens straight to Claudy's face, full screen, landscape and portrait. Include
> a debug menu in settings that triggers every expression and every haptic pattern.
> Explain what each new file does in one line, then tell me how to test.

**Test:** every row F1 to F13 in `FEATURES.md` passes on the phone. Most important:
stroking purrs, shaking cancels, face down closes the eyes.

---

## Phase B2: link and camera (L1 to L9)

The app replaces Continuity Camera as the brain's eye.

**Prompt to paste:**

> Build phase B2: features L1 to L9. On the Mac, add brain/phone_link.py and the
> `--camera phone` option exactly as docs/PROTOCOL.md describes, keeping Stage A
> working with a normal camera number too. On the phone, add the camera, Buddy and
> Inspect modes, the link, photo eyes and tap to point. Add the Info.plist entries
> needed and tell me which permission pop-ups to accept.

**Test:** with `python eye.py --camera phone` running, the Mac window shows the app's
camera. Typing a question on the Mac flashes the photo eyes and the phone shows the
thinking face. Tapping a part in Inspect mode gets its name. Sleeping the phone puts
out the iOS green dot.

---

## Phase B3: voice (V1 to V7)

**Prompt to paste:**

> Build phase B3: features V1 to V7. Speech to text must run on the phone with
> on-device recognition. Build hold-to-talk first and get it passing, then the
> Action button intent, then the "Hey Claudy" wake word last, because it is the
> hardest. If continuous listening is unreliable, tell me and keep hold-to-talk as
> the main way.

**Test:** hold the face, ask "what am I holding?", let go, hear the answer from the
phone. Tap while it talks and it stops. The yes or no card blocks a test command
until answered.

---

## Phase B4: tracking (T1 to T6)

**Prompt to paste:**

> Build phase B4: features T1 to T5, all on-device with the Vision framework. Send
> hand boxes in the frame message as PROTOCOL.md describes. Keep the phone cool:
> run tracking at a modest rate and measure the frame rate. Leave T6 (ASL bridge) as
> a clearly marked hook and ask me about my ASL tracker before building it.

**Test:** the eyes follow a moving hand. Thumbs up takes a photo. Pointing the phone
at a label shows its text almost instantly with the Mac switched off.

---

## Phase B5: LiDAR, light and photo quality (D1 to D7)

**Prompt to paste:**

> Build phase B5: features D1 to D6. Check the measuring against a ruler with me and
> tell me honestly how accurate it is. Then describe what D7 (3D scan) would take
> and wait for my go-ahead.

**Test:** radar distance is close to a ruler's. Dragging a box over a known part
gives a believable size. Covering the lamp turns the torch on by itself.

---

## Phase B6: assistant features (H1 to H10)

Mostly Mac-side prompts and memory, with small phone screens.

**Prompt to paste:**

> Build phase B6: features H1 to H10. Most of this is on the Mac: prompts, notes
> and saved photos under ~/.claudy/sessions. Keep automatic checks on the small
> fast model and limited to one every 25 seconds, as in Stage A. Show me the watcher
> prompt for each task preset so I can edit the wording.

**Test:** a 10-minute build session produces a folder with photos, a time-lapse and
a summary. "Where did I put the screwdriver?" gets the right answer.

---

## Phase B7: connections (C1 to C6)

**Prompt to paste:**

> Build phase B7 one feature at a time, in this order: C3, C1, C4, C5, C2, C6. C2
> (pocket mode) is an experiment: first test with me whether the Claude app's Ask
> Claude shortcut action accepts a photo, and report what you find before building
> on it. For C6, explain the security of the tunnel before turning anything on.

**Test:** each row C1 to C6 in `FEATURES.md`.

---

## Phase B8: first body (R1 to R3)

Needs two small servos, a printed MagSafe mount and an Arduino or Pico.

**Prompt to paste:**

> Plan phase B8 with me before writing code: the parts, the wiring and the printed
> mount. Then build R1, then R2, then R3.

**Test:** "turn left" physically turns the phone, and it follows your hands across
the desk.
