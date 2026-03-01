@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: bin/format.bat — コードフォーマット
::
:: 使い方:
::   bin\format.bat           — Rust + Elixir を両方フォーマット
::   bin\format.bat rust      — Rust のみ（cargo fmt）
::   bin\format.bat elixir    — Elixir のみ（mix format）
::   bin\format.bat check     — フォーマット差分チェックのみ（変更なし）
:: ============================================================

set "ROOT=%~dp0.."
set "NATIVE=%ROOT%\native"
set "FAILED="
set "FILTER=%~1"

cd /d "%ROOT%"

echo.
echo ============================================================
echo  AlchemyEngine — Format
if "%FILTER%"=="" (echo  Mode: ALL) else (echo  Mode: %FILTER%)
echo ============================================================

:: ────────────────────────────────────────────
:: Rust — cargo fmt
:: ────────────────────────────────────────────
:rust_fmt
if /i "%FILTER%"=="elixir" goto :rust_fmt_skip

echo.
if /i "%FILTER%"=="check" (
    echo [STEP] cargo fmt --check
    cargo fmt --manifest-path "%NATIVE%\Cargo.toml" --all -- --check
) else (
    echo [STEP] cargo fmt
    cargo fmt --manifest-path "%NATIVE%\Cargo.toml" --all
)
if errorlevel 1 (
    set "FAILED=!FAILED! [cargo fmt]"
    echo [FAIL] cargo fmt
) else (
    echo [PASS] cargo fmt
)

:rust_fmt_skip

:: ────────────────────────────────────────────
:: Elixir — mix format
:: ────────────────────────────────────────────
:elixir_fmt
if /i "%FILTER%"=="rust" goto :elixir_fmt_skip

echo.
if /i "%FILTER%"=="check" (
    echo [STEP] mix format --check-formatted
    mix format --check-formatted
) else (
    echo [STEP] mix format
    mix format
)
if errorlevel 1 (
    set "FAILED=!FAILED! [mix format]"
    echo [FAIL] mix format
) else (
    echo [PASS] mix format
)

:elixir_fmt_skip

:: ────────────────────────────────────────────
:: サマリー
:: ────────────────────────────────────────────
echo.
echo ============================================================
if "%FAILED%"=="" (
    if /i "%FILTER%"=="check" (
        echo  RESULT: ALL FORMATTED
    ) else (
        echo  RESULT: ALL DONE
    )
    echo ============================================================
    exit /b 0
) else (
    echo  RESULT: FAILED —%FAILED%
    echo ============================================================
    exit /b 1
)
