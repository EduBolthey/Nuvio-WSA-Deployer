# Nuvio WSA Deployer

An automated, one-click Windows Subsystem for Android (WSA) provisioning and Nuvio Debug application installer.

## Features

- **Automated Virtualization Setup**: Checks BIOS virtualization and enables Windows Hypervisor Platform and Virtual Machine Platform.
- **Developer Settings**: Enables Windows Sideloading / Developer Mode and Long Paths.
- **ADB Automation**: Automatically configures Android Debug Bridge and updates persistent User PATH.
- **WSA Deployment**: Validates existing WSA installation or registers package manifests cleanly.
- **Streamlined Sideloading**: Installs Nuvio Debug with runtime permissions auto-granted (`-r -d -g`).
- **Data Preservation**: Automatically detects existing user setups, retaining personal watch progress and addons.
- **Desktop Shortcut**: Adds a direct desktop launcher for quick access.

## Quick Start

### Option 1: Direct PowerShell (Recommended)
Open PowerShell and run:
```powershell
irm https://raw.githubusercontent.com/EduBolthey/Nuvio-WSA-Deployer/main/scripts/Install-Nuvio-WSA.ps1 | iex
```

### Option 2: Run via Batch Launcher
1. Clone or download this repository.
2. Double-click `Install-Nuvio-WSA.bat`.
3. Follow the automated on-screen steps.

## Directory Structure

```text
├── Install-Nuvio-WSA.bat        # Double-click launcher with self-elevation
├── scripts/
│   └── Install-Nuvio-WSA.ps1    # Main installation and configuration script
├── apks/                        # Local folder for APK packages
├── presets/                     # Default application configuration presets
└── .gitignore                   # Excludes binaries, credentials, and temporary files
```

## Requirements

- Windows 10 (Build 19041+) or Windows 11 (64-bit)
- Hardware Virtualization enabled in BIOS/UEFI
