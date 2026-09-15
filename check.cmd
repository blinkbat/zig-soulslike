@echo off
REM check.cmd - type-check only, no codegen and no link. ~2.7s against ~10s for build.cmd. Type "check".
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build check
if errorlevel 1 ( echo CHECK FAILED & exit /b 1 )
echo CHECK OK
