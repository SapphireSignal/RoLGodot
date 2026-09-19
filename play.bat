@echo off
rem Launches the Godot port from source. Set GODOT to override the engine path.
if "%GODOT%"=="" set "GODOT=D:\Godot\Godot_v4.7.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot 4.7 not found at "%GODOT%". Set the GODOT environment variable to your Godot executable.
  pause
  exit /b 1
)
rem %~dp0 ends in a backslash, and \" would escape the closing quote: the trailing . keeps the path intact.
rem First a quick headless import (about 2 s when nothing changed): it refreshes Godot's class cache, so scripts
rem added since the last run are found (a stale cache made the viewers fail to compile: a black window).
if not exist "%~dp0logs" mkdir "%~dp0logs"
rem The C++ core: rebuilt only when its sources changed (a few seconds), the first time a few minutes.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_native.ps1" > "%~dp0logs\play_build.log" 2>&1
if errorlevel 1 (
  echo The C++ core failed to build, see logs\play_build.log
  pause
  exit /b 1
)
"%GODOT%" --headless --path "%~dp0." --import --log-file "%~dp0logs\play_import.log" >nul 2>&1
rem Extra arguments go to Godot (tools/run_tests.ps1 passes -- --smoke-test=<file>).
start "" "%GODOT%" --path "%~dp0." %*
