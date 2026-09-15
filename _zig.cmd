@echo off
REM _zig.cmd - THE ONE PLACE THE TOOLCHAIN IS NAMED. Not a command you type: build/check/run/shot
REM `call` it and then use %ZIG%. Spelled out per script, a version bump missed one and it kept compiling.
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe"
if not exist "%ZIG%" ( echo NO TOOLCHAIN: %ZIG% & exit /b 1 )
