@echo off
REM FarmSim LAN port - reconnect test. Like run_lan_test.bat, but in the middle
REM of the first season Player 2 loses the connection (as a phone leaving Wi-Fi
REM range would), reconnects by itself, and the pair finish the whole session.
REM Then the same again with the HOST losing the connection.
setlocal
echo --- Player 2 drops and comes back ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_farmsim.ps1" -Mode lan -LanCase "--blip" -TimeoutSeconds 300
set P2=%ERRORLEVEL%
echo --- The host drops and comes back ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_farmsim.ps1" -Mode lan -LanCase "--host-blip" -TimeoutSeconds 300
set H=%ERRORLEVEL%
echo.
echo Player 2 reconnect: exit %P2%   Host reconnect: exit %H%   (0 = every check passed)
echo Logs: %~dp0test_out\lan_host.log and lan_client.log (last run)
echo.
pause
