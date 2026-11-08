@echo off
rem Tippenhauer Works - write each character's gear export (saved on every logout or /reload) to a text file.
rem Double-click this file. The files go to Documents\TippWorks Gear.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Export-Gear.ps1" %*
rem Only stops when something went wrong, so the message can be read.
if errorlevel 1 pause
