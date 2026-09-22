@echo off
setlocal
rem Superproject wrapper: run Mix inside world-server submodule.
set "WS=%~dp0..\world-server"
if not exist "%WS%\mix.exs" (
  echo [error] world-server submodule not found.
  echo Run: git submodule update --init --recursive
  exit /b 1
)
cd /d "%WS%" || exit /b 1
call mix deps.get %*
exit /b %ERRORLEVEL%
