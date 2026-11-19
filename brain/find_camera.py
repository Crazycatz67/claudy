"""Finds which camera number is your iPhone.

Run:  python find_camera.py
It saves one picture per camera it finds (camera_0.jpg, camera_1.jpg, ...).
Open them: the one showing the iPhone's view is the number to use with eye.py.
"""
import platform

import cv2

backend = cv2.CAP_AVFOUNDATION if platform.system() == "Darwin" else cv2.CAP_ANY
found = 0
for i in range(6):
    cap = cv2.VideoCapture(i, backend)
    if not cap.isOpened():
        continue
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
    frame = None
    for _ in range(15):          # let the camera adjust its exposure first
        ok, f = cap.read()
        if ok:
            frame = f
    cap.release()
    if frame is not None:
        cv2.imwrite(f"camera_{i}.jpg", frame)
        print(f"Camera {i}: {frame.shape[1]} x {frame.shape[0]}  -> saved camera_{i}.jpg")
        found += 1
if not found:
    print("No cameras found. Check that Terminal is allowed to use the camera (System Settings > Privacy & Security > Camera).")
