@echo off
rem DiskCheck 3.0 launcher - runs the PowerShell utility
rem Keep this file next to DiskCheck.ps1
title DiskCheck 3.0
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DiskCheck.ps1"
if errorlevel 1 (
    echo.
    echo Something went wrong. Press any key to close.
    pause >nul
)
