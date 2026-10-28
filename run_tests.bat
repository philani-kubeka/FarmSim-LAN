@echo off
REM FarmSim - run the automated test suite.
REM Double-click this file. It finds Godot, runs every test headlessly and
REM leaves the results in test_out\test_results.json.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_farmsim.ps1" -Mode test
echo.
echo Exit code: %ERRORLEVEL%
echo Results:   %~dp0test_out\test_results.json
echo.
pause
