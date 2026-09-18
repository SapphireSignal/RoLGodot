@echo off
rem Launches the Godot port from source. Set GODOT to override the engine path.
if "%GODOT%"=="" set "GODOT=D:\Godot\Godot_v4.7.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot 4.7 not found at "%GODOT%". Set the GODOT environment variable to your Godot executable.
  pause
  exit /b 1
)
rem %~dp0 ends in a backslash, and \" would escape the closing quote: the trailing . keeps the path intact.
start "" "%GODOT%" --path "%~dp0."
