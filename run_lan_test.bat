@echo off
REM FarmSim LAN port - network test. Starts a host and a client on this computer,
REM lets them play a whole session against each other, and reports the checks.
REM Windows Firewall may ask once to allow Godot on private networks: allow it.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_farmsim.ps1" -Mode lan -TimeoutSeconds 300
echo.
echo Exit code: %ERRORLEVEL%   (0 = every check passed)
echo Logs:      %~dp0test_out\lan_host.log and lan_client.log
echo.
pause
