@echo off
REM build.cmd - compile zig-soulslike to zig-out\bin without launching. Type "build".
REM Zig static-links raylib into a single exe (no raylib.dll). Incremental rebuilds.
setlocal
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe"
"%ZIG%" build
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
echo BUILD OK: zig-out\bin\zig-soulslike.exe
