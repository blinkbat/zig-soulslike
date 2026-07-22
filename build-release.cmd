@echo off
REM build-release.cmd - optimized ReleaseFast build. Type "build-release".
setlocal
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe"
"%ZIG%" build -Doptimize=ReleaseFast
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
echo BUILD OK (ReleaseFast): zig-out\bin\zig-soulslike.exe
