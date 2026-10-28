@echo off
REM FarmSim - try the phone version on this computer.
REM Opens a normal window (host here) and a phone-shaped window that uses the
REM mobile layout and touch controls. The mouse acts as a finger: hold the left
REM half to steer, click the round tool buttons to use a tool.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_farmsim.ps1" -Mode phone
