@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: bin/ci.bat — ローカル CI 相当チェック
:: GitHub Actions の ci.yml と同等の検証をローカルで実行する
::
:: 使い方:
::   bin\ci.bat           — 全ジョブを実行
::   bin\ci.bat rust      — Rust ジョブのみ
::   bin\ci.bat elixir    — Elixir ジョブのみ
::   bin\ci.bat check     — フォーマット + Lint のみ（テストなし）
:: ============================================================

set "ROOT=%~dp0.."
set "NATIVE=%ROOT%\native"
set "FAILED="
set "FILTER=%~1"

cd /d "%ROOT%"

echo.
echo ============================================================
echo  AlchemyEngine — Local CI
if "%FILTER%"=="" (echo  Mode: ALL) else (echo  Mode: %FILTER%)
echo ============================================================

:: ────────────────────────────────────────────
:: [A] Rust — fmt & clippy
:: ────────────────────────────────────────────
:rust_check
if /i "%FILTER%"=="elixir" goto :rust_check_skip

echo.
echo ============================================================
echo  [A] Rust — fmt ^& clippy
echo ============================================================

echo.
echo [STEP] cargo fmt
cargo fmt --manifest-path "%NATIVE%\Cargo.toml" --all -- --check
if errorlevel 1 (set "FAILED=!FAILED! [cargo fmt]") else (echo [PASS] cargo fmt)

echo.
echo [STEP] cargo clippy
cargo clippy --manifest-path "%NATIVE%\Cargo.toml" --workspace -- -D warnings
if errorlevel 1 (set "FAILED=!FAILED! [cargo clippy]") else (echo [PASS] cargo clippy)

:rust_check_skip

:: ────────────────────────────────────────────
:: [B] Rust — unit tests
:: ────────────────────────────────────────────
:rust_test
if /i "%FILTER%"=="elixir" goto :rust_test_skip
if /i "%FILTER%"=="check"  goto :rust_test_skip

echo.
echo ============================================================
echo  [B] Rust — unit tests (game_physics)
echo ============================================================

echo.
echo [STEP] cargo test game_physics
cargo test --manifest-path "%NATIVE%\Cargo.toml" -p game_physics
if errorlevel 1 (set "FAILED=!FAILED! [cargo test]") else (echo [PASS] cargo test)

:rust_test_skip

:: ────────────────────────────────────────────
:: [C] Elixir — compile & credo
:: ────────────────────────────────────────────
:elixir_check
if /i "%FILTER%"=="rust" goto :elixir_check_skip

echo.
echo ============================================================
echo  [C] Elixir — compile ^& credo
echo ============================================================

echo.
echo [PREP] mix deps.get
mix deps.get

echo.
echo [STEP] mix compile
mix compile --warnings-as-errors
if errorlevel 1 (set "FAILED=!FAILED! [mix compile]") else (echo [PASS] mix compile)

echo.
echo [STEP] mix format --check-formatted
mix format --check-formatted
if errorlevel 1 (set "FAILED=!FAILED! [mix format]") else (echo [PASS] mix format)

echo.
echo [STEP] mix credo --strict
set MIX_ENV=dev
mix credo --strict
if errorlevel 1 (set "FAILED=!FAILED! [mix credo]") else (echo [PASS] mix credo)
set MIX_ENV=

:elixir_check_skip

:: ────────────────────────────────────────────
:: [D] Elixir — mix test (with NIF)
:: ────────────────────────────────────────────
:elixir_test
if /i "%FILTER%"=="rust"  goto :elixir_test_skip
if /i "%FILTER%"=="check" goto :elixir_test_skip

echo.
echo ============================================================
echo  [D] Elixir — mix test (with NIF)
echo ============================================================

set MIX_ENV=test
echo.
echo [STEP] mix test
mix test
if errorlevel 1 (set "FAILED=!FAILED! [mix test]") else (echo [PASS] mix test)
set MIX_ENV=

:elixir_test_skip

:: ────────────────────────────────────────────
:: サマリー
:: ────────────────────────────────────────────
echo.
echo ============================================================
if "%FAILED%"=="" (
    echo  RESULT: ALL PASSED
    echo ============================================================
    exit /b 0
) else (
    echo  RESULT: FAILED —%FAILED%
    echo ============================================================
    exit /b 1
)
