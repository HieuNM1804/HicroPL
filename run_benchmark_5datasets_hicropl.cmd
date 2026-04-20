@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_benchmark_5datasets_hicropl.ps1" %*
exit /b %errorlevel%
