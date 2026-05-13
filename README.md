# SpaceSwitcher

A macOS menu-bar app that switches Spaces and remaps a mouse button + swipe gesture to Space/Mission Control navigation.

[中文说明](README.zh.md)

---

## Requirements

- macOS 12 Monterey or later
- **Accessibility** permission (System Settings → Privacy & Security → Accessibility)
- **Input Monitoring** permission (required for the mouse button test window)

---

## Installation

```bash
bash build.sh
open SpaceSwitcher.app
```

On first launch macOS will prompt for Accessibility permission. Grant it, then relaunch the app.

---

## Menu bar

Click the cursor-arrow icon (↖) in the menu bar to open the menu.

| Item | Action |
|------|--------|
| Space Left | Switch to the Space on the left (Ctrl+←) |
| Space Right | Switch to the Space on the right (Ctrl+→) |
| Gesture Remap… | Open gesture settings |
| Test Mouse Buttons… | Open the button debug window |
| Quit | Quit the app |

---

## Gesture remap

Open **Gesture Remap…** from the menu bar.

### Setup

1. **Enable gesture remap** — check the box to activate.
2. **Mouse** — choose a specific mouse, or leave on *Any Mouse* to match all devices.
3. **Button** — the button you hold while swiping (default: Button 4 / Back).
4. **Ring button** — the button that shows the action ring overlay (default: Button 5 / Forward). Hold it to display the Space picker ring; release over a slot to jump directly to that Space.

### Sensitivity

| Slider | What it controls |
|--------|-----------------|
| Distance | How far (px) you must drag before a space switch fires. Higher = less sensitive. |
| Speed | How fast (px/s) a flick must travel to fire early, before the distance is reached. Higher = less sensitive. || Space delay | Gap (ms) between arrow presses when jumping multiple Spaces at once (e.g. via the ring). Must exceed the Space animation (~280 ms). |
### Gestures

Hold the **gesture button** and move the mouse:

| Direction | Action |
|-----------|--------|
| Swipe left | Space Left (Ctrl+←) |
| Swipe right | Space Right (Ctrl+→) |
| Swipe up | Mission Control / Space up (Ctrl+↑) |
| Swipe down | App Exposé / Space down (Ctrl+↓) |

**Short click** (hold < 0.3 s with no swipe): the original button click is passed through unchanged.

Hold the **ring button** to show the action ring overlay around the cursor. While held, move to a numbered Space slot and release to jump directly to that Space.

Settings are saved automatically and restored on next launch.

---

## Mouse button test window

Open **Test Mouse Buttons…** to see raw HID events from your mice. Useful for identifying which button number corresponds to a physical button.

---

## Permissions explained

| Permission | Why it's needed |
|-----------|----------------|
| Accessibility | Allows the app to send key events (Ctrl+Arrow) to switch Spaces, and to intercept/suppress mouse buttons via CGEventTap. |
| Input Monitoring | Allows the app to read raw HID events from mice for the test window and device identification. |

---

## Build from source

```bash
# Requires Xcode command-line tools
bash build.sh        # produces SpaceSwitcher.app in the project root
open SpaceSwitcher.app
```
