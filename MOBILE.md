# FarmSim on a phone

The phone version is the same project, not a copy. On Android (or a computer
started with `-- --mobile`) the game switches to a phone layout and gets
BombSquad-style touch controls. Phones and computers play together over the
same Wi-Fi, so one PC can host and a phone can join, or two phones can play.

## How it plays

* **Left thumb - joystick.** Put your thumb anywhere on the left side of the
  screen and the stick appears under it. Drag to walk.
* **Right thumb - tool buttons.** One big round button per tool, in a diamond.
  Tapping a button picks that tool up *and* uses it on the tile you are
  standing on, so there is no "change tool" step. The tool in your hand has a
  white ring.
* **Pause** - the II button top-right, or the phone's back gesture.
* **Solo** - *Play solo* gives one farmer both roles' six tools. The planter's
  four stay in the diamond; **Scout** (purple) and **Treat** (teal) sit as two
  extra buttons above it, top right.

The main menu offers *Play with a friend* and *Play solo* (the one-keyboard
session is a computer thing). Every quiz has **< Back** and **Exit**; the back
gesture goes back a question, and on any other screen asks whether to leave.

## What changes on a phone

| | Computer | Phone |
| --- | --- | --- |
| Window | 16:9, letterboxed (`aspect = keep`) | Fills the screen (`aspect = expand`); the farm centres itself |
| Menus | 1:1 | Drawn 1.5x larger (1.15x on tablets), then fitted to the phone - see below |
| Quizzes | One column | Two columns: question and feedback left, answers right |
| Farm HUD | Both player panels | Only your panel, bigger text, room left for the thumbs and pause |
| Controls | Keyboard | Joystick + tool buttons (keyboard still works) |

All of this lives in `Config.is_mobile()` (scripts/autoload/config.gd),
`scripts/ui/touch_controls.gd`, `FarmHud.apply_mobile_layout()` and
`Farm._prepare_mobile()`. The joystick presses the same input actions the
keyboard does, so the LAN code and the research log see no difference.

## Fitting every phone

Phones run from 16:9 to 21:9 and vary in size, so no single scale fits them all.
Each screen starts at the phone scale and is drawn a step smaller until it fits
the height without scrolling, never below 1.1x so the text stays readable
(`Config` - "fit to screen"). Quizzes re-fit on every question. Every quiz
question, with its feedback showing, fits without scrolling at full size on
16:9, 18:9, 19.5:9, 20:9 and 21:9 phones; `tests/cases/test_mobile.gd` checks
it, so a new, longer question that would not fit fails the test suite.

## Try it on your PC first

Double-click `run_mobile_preview.bat`. It opens a normal window and a
phone-shaped one. The mouse acts as a finger in the phone window: hold the left
half to steer, click the round buttons to use a tool. Host in the normal
window, then *Play with a friend > Find games* in the phone window.

## Building the APK (once per computer)

1. In Godot: **Editor > Manage Export Templates > Download and Install**.
2. Install Android Studio (or just the command-line tools) and an OpenJDK 17.
   In **Editor > Editor Settings > Export > Android** set the *Java SDK Path*
   and *Android SDK Path*.
3. **Project > Export**. The *Android* preset is already set up
   (`export_presets.cfg`: package `za.ac.nwu.farmsim`, landscape, internet and
   Wi-Fi permissions, tests and dev tools excluded).
4. Press **Export Project** and pick `build/FarmSim.apk`. For a debug build
   Godot signs it with its own debug key; for a release build add a keystore
   under the preset's *Keystore* section.
5. Copy the APK to the phone and open it (allow "install unknown apps"), or
   use the one-click deploy button (the Android icon top-right) with the phone
   plugged in and USB debugging on.

## Network notes

* Both devices on the same Wi-Fi. A phone hotspot works well; campus and guest
  Wi-Fi often hide devices from each other.
* If *Find games* stays empty, some phones filter broadcast traffic. Use
  *Join by address* with the address shown in the host's lobby.
* The first time a PC hosts, Windows Firewall asks to let Godot through - allow
  it on private networks, or the phone can't connect.
