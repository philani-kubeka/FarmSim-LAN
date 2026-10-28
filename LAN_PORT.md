# FarmSim LAN - how the multiplayer port works

## Playing

1. Both computers on the same network (same Wi-Fi or switch).
2. **Computer A:** Main menu > **Play on your network** > **Host a game** >
   *Host game*. This computer is Player 1. Its address is shown in the lobby.
3. **Computer B (or a phone):** **Play on your network** (*Play with a friend*
   on a phone) > **Find games**. The farm appears within a second or two; tap
   it to join. If nothing appears, use **Join by address** with A's address.
4. Both seats in A's lobby light up. Press **Start session**. Both devices move
   through the session together.

Phones can join too - see [MOBILE.md](MOBILE.md).

Windows Firewall will ask once to let Godot through. Allow it on **private**
networks. Campus/guest Wi-Fi often blocks both broadcast and device-to-device
traffic; a phone hotspot or a home router works.

Controls, on each computer: **WASD or arrow keys** to move, **E or Space** to
use, **Q or Shift** to change tool. **Esc** pauses both computers.

To try it on one PC, run `run_two_windows.bat`, host in one window and join the
other (it finds itself, or use `127.0.0.1`).

## What changed from the original

| Part | File | What it does |
| --- | --- | --- |
| Network | `scripts/autoload/net.gd` (autoload `Net`) | ENet host/join on UDP 7777, max 2 players. Every RPC goes through this node. Offline by default, so the original game is untouched until someone hosts or joins. |
| Discovery | `scripts/net/lan_discovery.gd` | The host broadcasts a small JSON beacon on UDP 7778 once a second; the Join tab listens and lists hosts heard in the last 4 seconds. |
| Lobby ("Play Together") | `scenes/ui/multiplayer_menu.tscn` + `scripts/ui/multiplayer_menu.gd`, `scenes/ui/components/player_slot.tscn` | Tab rail (Host / Find games / Join by address), one tappable row per discovered farm, and a lobby with two player seats, Start and Leave. |
| Phone build | `scripts/ui/touch_controls.gd`, `Config.is_mobile()`, `export_presets.cfg` | Joystick + tool buttons, phone layout, Android export. See MOBILE.md. |
| Main menu | `scenes/ui/main_menu.tscn` | New *Multiplayer (LAN)* button. |
| Session flow | `scripts/autoload/session_controller.gd` | The host drives it. Every screen change is mirrored to the client with a copy of the session state. Finishing or abandoning returns both to the lobby, still connected. |
| Farm | `scripts/farm/farm.gd`, `scripts/farm/player.gd` | The host runs the whole simulation. Each computer moves its own player and sends its position 30x a second; Player 2's tool use is sent to the host, which applies the normal rules. The host sends the field (~350 bytes) 10x a second, plus messages, events and pause. |
| Knowledge checks, usability | `scripts/ui/assessment_screen.gd`, `scripts/ui/usability_screen.gd` | Each player answers on their own computer (no hand-over step). The host waits for both, then records them exactly as the one-keyboard version does. |
| Research log | `scripts/autoload/gameplay_logger.gd` | Player 2's events are sent to the host (tagged `"via": "player_2"`). Only the host writes a session file. |
| Disconnects | `net.gd`, `session_controller.gd`, `reconnect_overlay.gd` | A drop mid-session pauses the game on both devices and the dropped device reconnects by itself (see below). Leaving on purpose still ends the session. |
| Backup | `gameplay_logger.gd` | While a session runs, the host rewrites `session_<id>_autosave.json` at every screen change, so a killed host app loses nothing. It is removed when the real (or `_partial`) file is written. |

The client never decides anything about the farm. That keeps one copy of the
rules, one set of numbers and one session file - the same guarantees the
original build gives for the research data.

## Tests

* `run_tests.bat` - the original suite plus `test_lan` (beacons, hosting,
  state hand-over, bindings).
* `run_lan_test.bat` - starts a headless host and client on this computer and
  lets them play a full three-season session through the real screens:
  discovery, joining, both pre/post tests answered separately, farming on both
  computers, usability, final results, session file. Logs go to
  `test_out/lan_host.log` and `test_out/lan_client.log`.

## When a device drops out

| What happens | What the players see |
| --- | --- |
| Player 2's link drops mid-session (Wi-Fi, screen lock, app switched) | Both devices pause behind "Connection lost". Player 2's device redials every 2 s and, once back, lands on the same screen - mid-season at the same moment, standing where it was, holding the same tool. |
| Player 2's app is closed or crashes | The host keeps waiting and advertises the game as **Rejoin** under Find games. Reopen FarmSim, Play with a friend > Find games > Rejoin. |
| The host's link drops and comes back | Same as above from the other side: Player 2 shows "Reconnecting...", gets back in when the host is reachable. |
| The host's app is closed or crashes | Player 2 keeps trying ("Reconnecting... attempt N") and can press *Leave the session*. The host's research data so far is in `session_<id>_autosave.json`. If the host opens a new lobby, Player 2 lands in it, still connected, with a note that the session ended. |
| The host stops waiting ("Stop waiting and save") | `_partial` file written, host back in the lobby. If Player 2 turns up later it lands in that lobby too. |
| Someone presses Leave / Back / Quit / Abandon | A goodbye is sent first, so this ends the session exactly as before - no waiting. |

Every reconnect is logged in the session file (`player_2_disconnected`,
`player_2_reconnected` with the seconds away).

Tests: `run_lan_test.bat` (a normal session, Player 2 on the phone layout) and
`run_reconnect_test.bat` (Player 2 drops mid-season and comes back, then the
host does). `tests/lan/lan_smoke.gd` also has `--drop`, `--host-quit`,
`--expect-host-gone`, `--lobby-only`, `--expect-lobby`, `--wait-long` and
`--rejoin` for the other rows of the table above.

## Limits

* LAN only - no relay server. To play across the internet, put both devices on
  Tailscale (free) and use Join by address with the host's 100.x.x.x address.
* Two players. A third computer that tries to join is turned away.
* If the host's app is closed for good, the session cannot continue; its data up to that point is in the autosave file.
* Discovery assumes /24 home-style networks for the subnet broadcast; the
  global broadcast and manual address cover everything else.
