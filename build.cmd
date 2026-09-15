@echo off
REM build.cmd - compile zig-soulslike to zig-out\bin without launching. Type "build".
REM Zig static-links raylib into a single exe (no raylib.dll). Incremental rebuilds.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
echo BUILD OK: zig-out\bin\zig-soulslike.exe
