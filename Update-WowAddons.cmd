@echo off
rem Tippenhauer Works - pull the latest addons from GitHub and install them into WoW.
rem Double-click this file, or run it from a terminal (extra options: -NoPull -Force -DryRun -Only Name).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Update-WowAddons.ps1" %*
if "%~1"=="" pause
