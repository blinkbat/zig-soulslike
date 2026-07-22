@echo off
REM run.cmd - build (incremental) and launch zig-soulslike. Type "run" in cmd.exe.
setlocal
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe"
taskkill /IM zig-soulslike.exe /F >nul 2>&1
"%ZIG%" build run
