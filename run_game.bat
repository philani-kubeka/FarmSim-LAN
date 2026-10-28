@echo off
REM FarmSim - launch the prototype for play.
REM Double-click this file. Two players, one keyboard.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_farmsim.ps1" -Mode play -TimeoutSeconds 5400
echo.
echo Exit code: %ERRORLEVEL%
echo.
pause
