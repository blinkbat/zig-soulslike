@echo off
REM shot.cmd - build then render headless walk-cycle PNGs into shots\ (window hidden).
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
"%~dp0zig-out\bin\zig-soulslike.exe" --shot
echo SHOTS in shots\
