@echo off
REM shot.cmd - build then render headless walk-cycle PNGs into shots\ (window hidden).
setlocal
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe"
"%ZIG%" build
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
"%~dp0zig-out\bin\zig-soulslike.exe" --shot
echo SHOTS in shots\
