@echo off
REM run.cmd - build (incremental) and launch zig-soulslike. Type "run" in cmd.exe.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
taskkill /IM zig-soulslike.exe /F >nul 2>&1
"%ZIG%" build run
