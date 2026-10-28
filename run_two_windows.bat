@echo off
REM FarmSim LAN port - opens two game windows on this computer, so you can try
REM Multiplayer without a second PC. In one: Multiplayer (LAN) > Host game.
REM In the other: Multiplayer (LAN) > Join, pick the game (or join 127.0.0.1).
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_farmsim.ps1" -Mode pair
