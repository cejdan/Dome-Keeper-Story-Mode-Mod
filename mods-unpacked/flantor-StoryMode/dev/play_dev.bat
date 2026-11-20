@echo off
rem Double-click to start a dev playtest (#292): loadout with everything unlocked,
rem $100,000 at the start of each Story Mode run. Options as in play_dev.ps1,
rem e.g. play_dev.bat -Story -Gear -Money 1000000
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play_dev.ps1" %*
