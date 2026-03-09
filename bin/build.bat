@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0.."
set "NATIVE=%ROOT%\native"
set "CLIENT=desktop"
set "PROFILE=debug"

:parse
if "%~1"=="" goto :build
if "%~1"=="--desktop"  (set "CLIENT=desktop"  & shift & goto parse)
if "%~1"=="--web"      (set "CLIENT=web"      & shift & goto parse)
if "%~1"=="--android"  (set "CLIENT=android"  & shift & goto parse)
if "%~1"=="--ios"      (set "CLIENT=ios"      & shift & goto parse)
if "%~1"=="--debug"    (set "PROFILE=debug"   & shift & goto parse)
if "%~1"=="--release"  (set "PROFILE=release" & shift & goto parse)
shift
goto parse

:build
cd /d "%ROOT%"

echo.
echo Building app (%PROFILE%)...
echo.

if "%PROFILE%"=="release" (
    cargo build --manifest-path "%NATIVE%\Cargo.toml" -p app --release
) else (
    cargo build --manifest-path "%NATIVE%\Cargo.toml" -p app
)
