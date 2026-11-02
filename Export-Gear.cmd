@echo off
rem Tippenhauer Works - write each character's gear export (open the bank or click Gear, then /reload) to a text file.
rem Double-click this file. The files go to Documents\TippWorks Gear.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Export-Gear.ps1" %*
if "%~1"=="" pause
