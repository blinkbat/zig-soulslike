@echo off
REM build-release.cmd - optimized ReleaseFast build. Type "build-release".
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build -Doptimize=ReleaseFast
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
echo BUILD OK (ReleaseFast): zig-out\bin\zig-soulslike.exe
