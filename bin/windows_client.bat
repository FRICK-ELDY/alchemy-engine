@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: bin/windows_client.bat - app (desktop client) only (minimal)
::
:: Prerequisites: run zenohd and mix run in separate terminals first.
::
:: Usage:
::   bin\windows_client.bat              - default tcp/127.0.0.1:7447, room main
::   bin\windows_client.bat CONNECT      - specify connect
::   bin\windows_client.bat CONNECT ROOM - specify both
:: ============================================================

set "ROOT=%~dp0.."
set "NATIVE=%ROOT%\native"
set "CONNECT=%~1"
set "ROOM=%~2"

if "%CONNECT%"=="" set "CONNECT=tcp/127.0.0.1:7447"
if "%ROOM%"=="" set "ROOM=main"

set "CARGO_BIN=%USERPROFILE%\.cargo\bin"
if exist "%CARGO_BIN%" set "PATH=%CARGO_BIN%;%PATH%"

cd /d "%ROOT%"

echo.
echo Alchemy Client - connect=%CONNECT% room=%ROOM%
echo (Ensure zenohd and mix run are running first)
echo.

cargo run --manifest-path "%NATIVE%\Cargo.toml" -p app -- --connect %CONNECT% --room %ROOM%
