@echo off
setlocal EnableDelayedExpansion
title Nuvio Debug - One-Click WSA Installer

:: ===================================================================
:: Request Administrator Elevation
:: ===================================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Administrator privileges required. Requesting elevation...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Set current directory to the folder containing this batch script
cd /d "%~dp0"

:: Launch Master PowerShell Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-Nuvio-WSA.ps1"

if %errorlevel% neq 0 (
    echo.
    echo [!] Installer exited with code %errorlevel%
    pause
)
