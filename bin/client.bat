@echo off
setlocal
rem Superproject wrapper: start Rust client (VRAlchemy) from client/
set "CL=%~dp0..\client"
if not exist "%CL%\Cargo.toml" (
  echo [error] client submodule not found.
  echo Run: git submodule update --init --recursive
  exit /b 1
)
cd /d "%CL%" || exit /b 1
cargo run -p app -- %*
exit /b %ERRORLEVEL%
