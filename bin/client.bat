@echo off
setlocal
rem Superproject wrapper: start Rust client (VRAlchemy)
set "WS=%~dp0..\world-server"
if not exist "%WS%\mix.exs" (
  echo [error] world-server submodule not found.
  echo Run: git submodule update --init --recursive
  exit /b 1
)
cd /d "%WS%" || exit /b 1
call mix alchemy.client %*
exit /b %ERRORLEVEL%
