@echo off
:: ============================================================
:: bin/credo.bat — Elixir 静的解析（Credo）
::
:: 使い方:
::   bin\credo.bat           — mix credo --strict（全指摘を表示）
::   bin\credo.bat suggest   — mix credo（strict なし、提案のみ）
::   bin\credo.bat explain   — mix credo --strict --format oneline
:: ============================================================

set "ROOT=%~dp0.."
set "FILTER=%~1"

cd /d "%ROOT%"

echo.
echo ============================================================
echo  AlchemyEngine — Credo
if "%FILTER%"=="" (echo  Mode: strict) else (echo  Mode: %FILTER%)
echo ============================================================
echo.

if /i "%FILTER%"=="suggest" (
    mix credo
) else if /i "%FILTER%"=="explain" (
    mix credo --strict --format oneline
) else (
    mix credo --strict
)

if errorlevel 1 (
    echo.
    echo [FAIL] credo
    exit /b 1
) else (
    echo.
    echo [PASS] credo
    exit /b 0
)
