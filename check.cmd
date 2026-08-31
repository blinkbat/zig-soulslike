@echo off
REM check.cmd - type-check only, no codegen and no link. ~2.7s against ~10s for build.cmd. Type "check".
setlocal
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe"
"%ZIG%" build check
if errorlevel 1 ( echo CHECK FAILED & exit /b 1 )
echo CHECK OK
