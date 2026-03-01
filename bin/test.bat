@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: bin/test.bat — テスト実行
::
:: 使い方:
::   bin\test.bat           — Rust + Elixir を両方テスト
::   bin\test.bat rust      — Rust のみ（cargo test）
::   bin\test.bat elixir    — Elixir のみ（mix test）
::   bin\test.bat cover     — Elixir カバレッジ付き（mix test --cover）
:: ============================================================

set "ROOT=%~dp0.."
set "NATIVE=%ROOT%\native"
set "FAILED="
set "FILTER=%~1"

cd /d "%ROOT%"

echo.
echo ============================================================
echo  AlchemyEngine — Test
if "%FILTER%"=="" (echo  Mode: ALL) else (echo  Mode: %FILTER%)
echo ============================================================

:: ────────────────────────────────────────────
:: Rust — cargo test
:: ────────────────────────────────────────────
:rust_test
if /i "%FILTER%"=="elixir" goto :rust_test_skip
if /i "%FILTER%"=="cover"  goto :rust_test_skip

echo.
echo ============================================================
echo  [A] Rust — cargo test
echo ============================================================

echo.
echo [STEP] cargo test game_physics
cargo test --manifest-path "%NATIVE%\Cargo.toml" -p game_physics
if errorlevel 1 (
    set "FAILED=!FAILED! [cargo test]"
    echo [FAIL] cargo test
) else (
    echo [PASS] cargo test
)

:rust_test_skip

:: ────────────────────────────────────────────
:: Elixir — mix test
:: ────────────────────────────────────────────
:elixir_test
if /i "%FILTER%"=="rust" goto :elixir_test_skip

echo.
echo ============================================================
echo  [B] Elixir — mix test
echo ============================================================

set MIX_ENV=test
echo.
if /i "%FILTER%"=="cover" (
    echo [STEP] mix test --cover
    mix test --cover
) else (
    echo [STEP] mix test
    mix test
)
if errorlevel 1 (
    set "FAILED=!FAILED! [mix test]"
    echo [FAIL] mix test
) else (
    echo [PASS] mix test
)
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
