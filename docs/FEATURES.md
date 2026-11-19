# Claudy Phone: feature list

Every feature has an ID. `docs/PHASES.md` says which IDs belong to each phase.
'Works without Mac' means it still works when the Mac brain is off.

## Stage A: Mac brain (built)

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| A1 | Brain | Always-watching eye | Mac watches the camera non-stop while awake, keeps the last minute and clear frames of each change | Mac | No | Done | eye.py window shows the phone's view and the motion bar moves |
| A2 | Brain | Speaks up on its own | When you finish an action, Claude checks and talks only if something looks wrong | Mac | No | Done | Plug a cable in the wrong place and it tells you |
| A3 | Brain | Typed questions, spoken answers | Type a question; Claude answers out loud from what it already saw | Mac | No | Done | Type 'what am I holding?' and hear the right answer |
| A4 | Brain | Claude Desktop tools | look, whats_happening and zoom tools so Claude Desktop sees through Claudy | Mac | No | Done | Ask Claude Desktop 'what is on my desk?' |

## B1: Face, touch, motion, haptics

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| F1 | Face | Eyes | Two rounded eyes that blink and drift slowly on a dark screen | Phone | Yes | Easy | Eyes blink on their own every few seconds |
| F2 | Face | Expressions | Idle, listening, thinking, happy, concerned, warning, sleeping, petted | Phone | Yes | Medium | A debug menu switches every expression smoothly |
| F3 | Face | Eye colour and mood colours | Pick Claudy's colour; amber when concerned, red for warnings, blue when listening | Phone | Yes | Easy | Change the colour in settings and it stays after restart |
| F4 | Touch | Tap to wake, swipe down to sleep | Basic wake and sleep by touch | Phone | Yes | Easy | Swipe down closes the eyes; tap opens them |
| F5 | Touch | Petting | Stroke the screen: happy squint and a purr buzz | Phone | Yes | Easy | Stroking makes it squint and purr |
| F6 | Motion | Shake to cancel | Shake means never mind: stops talking and cancels the request | Phone | Yes | Easy | Shaking shows a dizzy blink and cancels |
| F7 | Motion | Flip to privacy sleep | Face down turns camera and mic off at once | Phone | Yes | Easy | Face down: iOS green dot goes out within a second |
| F8 | Motion | Pick-up wake | Wakes when lifted or set on the stand | Phone | Yes | Easy | Lifting the sleeping phone opens the eyes |
| F9 | Haptics | Haptic vocabulary | Tap = heard you, click = photo, heartbeat = thinking, double pulse = look at me, long buzz = stop, purr = petted | Phone | Yes | Medium | Each pattern feels clearly different in the debug menu |
| F10 | Face | Widget carousel | Swipe left or right between face, light, timer, radar and crosshair | Phone | Yes | Medium | Swiping cycles the widgets and returns to the face |
| F11 | Light | Screen light | Whole screen glows white or any colour as a soft fill light | Phone | Yes | Easy | Light widget turns the screen full white, slider changes colour |
| F12 | Face | Screen care | Keeps the screen awake, dims when idle, moves the eyes slightly to avoid burn-in | Phone | Yes | Easy | After a minute idle the face dims; a tap restores it |
| F13 | App | Settings sheet | Two-finger long press: colour, voice, sensitivity, Mac address, debug menu | Phone | Yes | Easy | Two-finger hold opens settings |

## B2: Link to the brain and camera

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| L1 | Link | Find the Mac by itself | Discovers the brain on Wi-Fi with no typing; manual address as backup | Both | No | Medium | App shows 'brain connected' within a few seconds of eye.py starting |
| L2 | Link | Live frames to the brain | Phone camera replaces Continuity Camera as the brain's eye | Both | No | Medium | eye.py shows the phone app's view, about 3 frames a second |
| L3 | Privacy | Photo eyes | Eyes flash red whenever a frame is sent to Claude | Both | No | Easy | Ask a question: eyes flash red once |
| L4 | Link | Brain drives the face | Mac sets expression, speaks, buzzes and switches the light on the phone | Both | No | Medium | While Claude thinks, the phone shows the thinking face |
| L5 | Camera | Buddy and Inspect modes | Buddy: front camera, big face. Inspect: back camera on the work, face in a corner bubble | Phone | Yes | Medium | A mode button or turning the phone over switches camera and layout |
| L6 | Camera | Tap to point | In Inspect, tap a spot: Claude gets a close-up of it and says what it is | Both | No | Medium | Tap a chip on a board and hear its name |
| L7 | Camera | Zoom and lenses | Pinch to zoom; switch ultra-wide, main and telephoto | Phone | Yes | Medium | Pinch zooms smoothly across lenses |
| L8 | Link | Offline badge and reconnect | Shows when the brain is unreachable and reconnects by itself | Phone | Yes | Easy | Quit eye.py: badge appears; restart: badge clears |
| L9 | Camera | Full-detail still | Brain can ask for one full-resolution photo for fine detail | Both | No | Medium | 'Read the tiny print' returns a sharp crop |

## B3: Voice

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| V1 | Voice | Hold to talk | Hold the face, speak, let go to send | Both | No | Medium | Hold, ask, release: answer is spoken |
| V2 | Voice | Action button talk | Press the Action button to talk, even when asleep | Both | No | Medium | Action button opens Claudy listening |
| V3 | Voice | Hey Claudy | Wake word while the app is open, recognised on the phone | Both | Partly | Hard | Saying 'Hey Claudy' from across the desk starts listening |
| V4 | Voice | Phone speaks | Answers spoken by the phone; choose the voice and speed | Phone | Yes | Easy | Voice picker changes how it sounds |
| V5 | Voice | Captions and quiet mode | Shows what Claudy says as text; quiet mode uses text and haptics only | Phone | Yes | Easy | Quiet mode: no sound, caption plus buzz |
| V6 | Safety | Yes or no card | Before running anything on the Mac, shows and says the command and waits | Both | No | Medium | Nothing runs until you tap or say yes |
| V7 | Voice | Interrupt | Tap or shake stops Claudy mid-sentence | Phone | Yes | Easy | Tap while it talks: it stops at once |

## B4: Tracking and on-device vision

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| T1 | Tracking | Eyes follow you | Eyes look toward your hands or face, tracked on the phone | Phone | Yes | Medium | Move a hand side to side: eyes follow |
| T2 | Tracking | Hand gestures | Thumbs up takes a photo; open palm pauses watching; pointing marks 'this one' | Phone | Partly | Hard | Thumbs up triggers the photo click |
| T3 | Tracking | Digital follow | Crops the wide view to keep your hands centred, with no motors | Phone | Yes | Medium | Frames sent to the Mac stay centred on your hands |
| T4 | Vision | Instant text reading | Reads labels and part numbers on the phone, instantly and offline | Phone | Yes | Medium | Point at a label: text appears in under a second |
| T5 | Tracking | Presence | Wakes when you sit down, sleeps after you leave | Phone | Yes | Medium | Walk away for 2 minutes: it sleeps; return: it wakes |
| T6 | Tracking | ASL bridge | A hook for your ASL tracker so signs become commands | Both | Partly | Hard | A chosen sign triggers a chosen command |

## B5: LiDAR, light and photo quality

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| D1 | LiDAR | Distance and radar eyes | Shows the distance to what is in front; radar sweep widget | Phone | Yes | Medium | Radar shows about the right centimetres against a ruler |
| D2 | LiDAR | Drag to measure | Drag a box on the live view to get a size | Phone | Yes | Hard | A 50 mm part reads within a few millimetres |
| D3 | Light | Auto flashlight | Turns the torch on and sets its level when the picture is too dark | Phone | Yes | Medium | Cover the lamp: torch comes on by itself |
| D4 | Camera | Best-shot routine | Sets focus from LiDAR, checks blur and glare, retakes up to three times | Both | Partly | Medium | Photos of a close, dim part come back sharp with no help |
| D5 | Camera | Macro inspection | Close-up mode for solder joints and pins | Both | No | Medium | A solder joint photo fills the frame, in focus |
| D6 | Motion | Level and angle | Bubble level and angle readout | Phone | Yes | Easy | Level reads 0 on a flat desk |
| D7 | LiDAR | 3D scan | Scan an object into a 3D model for CAD or printing | Phone | Yes | Hard | A scanned mug exports as a model file |

## B6: Assistant features

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| H1 | Assistant | Step coach | Follows a guide and confirms each step from the camera | Both | No | Medium | It refuses to move on until the step looks done |
| H2 | Assistant | Desk memory | Answers where you left things from what it has seen | Both | No | Medium | 'Where is the screwdriver?' gets the right spot |
| H3 | Assistant | Build log | Saves best photos, a time-lapse and notes for each project | Both | Partly | Medium | A session produces a folder with photos and a summary |
| H4 | Assistant | Timers and breaks | Timer face with a buzz; break reminders based on how long you worked | Phone | Yes | Easy | 'Timer 5 minutes' shows a ring and buzzes at zero |
| H5 | Assistant | What changed | Compares the desk now with earlier | Both | No | Medium | Move one object: it names it |
| H6 | Assistant | Parts counter | Counts and names parts spread on the desk | Both | No | Medium | Ten screws are counted as ten |
| H7 | Safety | Safety watch | Warns about hot tools left on, liquids near electronics, loose metal on a board | Both | No | Medium | A cup beside the open PC triggers a warning |
| H8 | Assistant | Task presets | One tap sets the task: PC build, soldering, 3D print check, study | Phone | Yes | Easy | Choosing a preset changes what it watches for |
| H9 | Assistant | Paper and whiteboard helper | Captures a page or board and explains or checks it | Both | No | Medium | Point at a worksheet: it reads the question back |
| H10 | Assistant | Session summary | When put to sleep, saves a short summary of what you did | Both | No | Easy | Sleep after a session: a summary note is saved |

## B7: Connections

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| C1 | Connect | Remote page | A web page from the Mac with live view and controls for any device | Mac | No | Medium | Open the page on another device and see the feed |
| C2 | Connect | Pocket mode (experiment) | Without the Mac, sends a question through the Claude app's Ask Claude shortcut | Phone | Yes | Hard | With the Mac off, a typed question still gets an answer |
| C3 | Connect | Shortcuts actions | Siri and Shortcuts can wake, sleep, take a photo or set the task | Phone | Yes | Medium | 'Claudy sleep' in Shortcuts closes the eyes |
| C4 | Robotics | Arduino bridge | Mac drives an Arduino: lights, buzzer, later servos | Mac | No | Medium | Claude flashes an LED when it warns you |
| C5 | Connect | Run things on the Mac | Open an app, start a script or search, always behind the yes or no card | Both | No | Medium | 'Open my project folder' asks first, then does it |
| C6 | Connect | Claude mobile connector | Claude on your phone can use Claudy's tools through a secure tunnel | Mac | No | Hard | Claude mobile app answers 'what is on my desk?' |

## B8: First body

| ID | Area | Feature | What it does | Runs on | Works without Mac | Difficulty | You know it works when |
|---|---|---|---|---|---|---|---|
| R1 | Body | Phone Neck | Two servos on a printed MagSafe mount turn and tilt the phone | Both | No | Hard | 'Turn left' physically turns the phone |
| R2 | Body | Real follow | The Neck keeps your hands in view | Both | No | Hard | Slide your hands across the desk: the phone turns to follow |
| R3 | Body | Attachment handshake | A body announces what it can do and Claudy gains those tools | Both | No | Hard | Plug in the Neck: turn and tilt tools appear by themselves |
