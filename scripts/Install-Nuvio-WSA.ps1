# =====================================================================
#  Nuvio Enhanced - Automated One-Click WSA & Nuvio Debug Installer
# =====================================================================
#  Repository : EduBolthey/Nuvio-WSA-Deployer
#  Purpose    : Fully automated zero-touch setup for Windows Subsystem for
#               Android (WSA), system prerequisites, ADB, environment PATH,
#               and deployment of Nuvio Debug ready to stream.
#  Security   : 100% portable, zero hardcoded credentials, zero personal paths.
#  Support    : Compatible with both direct script execution and irm | iex.
# =====================================================================

function Invoke-NuvioWsaDeployer {
    [CmdletBinding()]
    param (
        [string]$ApkPath = "",
        [string]$WsaPath = "",
        [string]$PresetDir = "",
        [switch]$SkipWsaInstall = $false,
        [switch]$SkipPresetConfig = $false,
        [switch]$NoRebootPrompt = $false,
        [switch]$NonInteractive = $false,
        [switch]$SkipElevation = $false
    )

    # -----------------------------------------------------------------
    # 0. Console Configuration & Elevation Handler
    # -----------------------------------------------------------------
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    } catch {}

    try {
        $Host.UI.RawUI.WindowTitle = "Nuvio Debug - One-Click WSA Auto Deployer"
    } catch {}

    function Test-Admin {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
        } catch {
            return $false
        }
    }

    if (-not (Test-Admin) -and -not $SkipElevation) {
        try {
            Write-Host "`n[*] Elevation required: Requesting Administrator privileges..." -ForegroundColor Yellow
            $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass")
            if ($PSCommandPath) {
                $argList += @("-File", $PSCommandPath)
                if ($ApkPath) { $argList += @("-ApkPath", $ApkPath) }
                if ($WsaPath) { $argList += @("-WsaPath", $WsaPath) }
                if ($PresetDir) { $argList += @("-PresetDir", $PresetDir) }
                if ($SkipWsaInstall) { $argList += "-SkipWsaInstall" }
                if ($SkipPresetConfig) { $argList += "-SkipPresetConfig" }
                if ($NoRebootPrompt) { $argList += "-NoRebootPrompt" }
                if ($NonInteractive) { $argList += "-NonInteractive" }
            } else {
                $oneLiner = "irm https://raw.githubusercontent.com/EduBolthey/Nuvio-WSA-Deployer/main/scripts/Install-Nuvio-WSA.ps1 | iex"
                $argList += @("-Command", $oneLiner)
            }

            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
            return
        } catch {
            Write-Host "  [!] UAC Elevation prompt not available or skipped in current shell." -ForegroundColor Yellow
            Write-Host "  [!] Proceeding with existing session permissions..." -ForegroundColor Yellow
        }
    }

    # Safe script base path (handles direct .ps1, batch file, or in-memory irm | iex)
    $scriptBase = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

    # -----------------------------------------------------------------
    # UI Styling Functions
    # -----------------------------------------------------------------
    function Write-Banner {
        Clear-Host
        Write-Host "======================================================================" -ForegroundColor Cyan
        Write-Host "           NUVIO DEBUG - 1-CLICK WSA STREAMING INSTALLER               " -ForegroundColor White
        Write-Host "               Windows Subsystem for Android Auto-Setup               " -ForegroundColor DarkGray
        Write-Host "======================================================================" -ForegroundColor Cyan
        Write-Host ""
    }

    function Write-Step ([int]$step, [int]$total, [string]$msg) {
        Write-Host "[$step/$total] " -ForegroundColor Cyan -NoNewline
        Write-Host "$msg" -ForegroundColor White
    }

    function Write-Success ([string]$msg) {
        Write-Host "  [✓] " -ForegroundColor Green -NoNewline
        Write-Host "$msg" -ForegroundColor Gray
    }

    function Write-Info ([string]$msg) {
        Write-Host "  [i] " -ForegroundColor Cyan -NoNewline
        Write-Host "$msg" -ForegroundColor DarkGray
    }

    function Write-Warn ([string]$msg) {
        Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
        Write-Host "$msg" -ForegroundColor Yellow
    }

    function Write-Err ([string]$msg) {
        Write-Host "  [✗] " -ForegroundColor Red -NoNewline
        Write-Host "$msg" -ForegroundColor Red
    }

    Write-Banner

    $TOTAL_STEPS = 6
    $needsReboot = $false

    # -----------------------------------------------------------------
    # STEP 1: Windows System Checks & Virtualization Prerequisites
    # -----------------------------------------------------------------
    Write-Step 1 $TOTAL_STEPS "Checking Windows System Prerequisites & Virtualization..."

    # 1.1 Architecture & OS Build Check
    $os = Get-CimInstance Win32_OperatingSystem
    $osBuild = [int]$os.BuildNumber
    $is64Bit = [Environment]::Is64BitOperatingSystem

    if (-not $is64Bit -or $osBuild -lt 19041) {
        Write-Err "Unsupported Windows version ($($os.Caption) Build $osBuild). WSA requires Windows 10 (Build 19041+) or Windows 11 (64-bit)."
        if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
        return
    }
    Write-Success "Windows Version: $($os.Caption) (Build $osBuild, 64-bit)"

    # 1.2 CPU Virtualization Hardware Check (BIOS)
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        if ($cpu.VirtualizationFirmwareEnabled -eq $false) {
            Write-Warn "Hardware Virtualization (VT-x / AMD-V) appears DISABLED in motherboard BIOS."
            Write-Warn "Please enable 'Intel Virtualization Technology' or 'AMD SVM' in your BIOS/UEFI if WSA fails to boot."
        } else {
            Write-Success "CPU Hardware Virtualization is enabled in BIOS."
        }
    } catch {
        Write-Info "Could not query BIOS virtualization status directly; continuing..."
    }

    # 1.3 Windows Features: VirtualMachinePlatform & HypervisorPlatform
    try {
        $vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
        if ($vmpFeature.State -ne "Enabled") {
            Write-Info "Enabling Windows Virtual Machine Platform feature..."
            Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
            
            # DISM Fallback
            if ((Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue).State -ne "Enabled") {
                dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
            }
            $needsReboot = $true
            Write-Success "Virtual Machine Platform enabled."
        } else {
            Write-Success "Virtual Machine Platform is already enabled."
        }
    } catch {
        Write-Warn "Could not verify/enable Virtual Machine Platform automatically: $_"
    }

    try {
        $hypFeature = Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -ErrorAction SilentlyContinue
        if ($hypFeature -and $hypFeature.State -ne "Enabled") {
            Write-Info "Enabling Windows Hypervisor Platform..."
            Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Success "Hypervisor Platform enabled."
        }
    } catch {}

    # 1.4 Windows Developer Mode & Sideloading
    try {
        $appModelKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
        if (-not (Test-Path $appModelKey)) {
            New-Item -Path $appModelKey -Force | Out-Null
        }
        Set-ItemProperty -Path $appModelKey -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $appModelKey -Name "AllowAllTrustedApps" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Success "Windows Developer Mode & App Sideloading enabled."
    } catch {
        Write-Warn "Could not set registry for Developer Mode: $_"
    }

    # 1.5 Enable Win32 Long Paths
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Success "Win32 Long Paths enabled."
    } catch {}

    Write-Host ""

    # -----------------------------------------------------------------
    # STEP 2: Android Debug Bridge (ADB) & PATH Auto-Configuration
    # -----------------------------------------------------------------
    Write-Step 2 $TOTAL_STEPS "Configuring Android Debug Bridge (ADB) & System PATH..."

    $adbExecutable = $null

    # Check if ADB is already present in PATH
    $adbInPath = Get-Command "adb.exe" -ErrorAction SilentlyContinue
    if ($adbInPath) {
        $adbExecutable = $adbInPath.Source
        Write-Success "Found ADB in system PATH: $adbExecutable"
    }

    # Search common standard installation paths
    if (-not $adbExecutable) {
        $commonAdbLocations = @(
            "$env:LOCALAPPDATA\Android\platform-tools\adb.exe",
            "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
            "$scriptBase\tools\platform-tools\adb.exe",
            "$scriptBase\..\tools\platform-tools\adb.exe",
            "$env:ProgramFiles\WSA PacMan\embedded-tools\adb.exe",
            "${env:ProgramFiles(x86)}\WSA PacMan\embedded-tools\adb.exe"
        )

        foreach ($loc in $commonAdbLocations) {
            if ($loc -and (Test-Path $loc)) {
                $adbExecutable = (Resolve-Path $loc).Path
                Write-Success "Found ADB at: $adbExecutable"
                break
            }
        }
    }

    # Auto-download Google platform-tools if ADB is missing
    if (-not $adbExecutable) {
        Write-Info "ADB not found. Downloading official Google Android Platform-Tools..."
        $platformToolsZip = "$env:TEMP\platform-tools-latest-windows.zip"
        $platformToolsUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
        $destDir = "$env:LOCALAPPDATA\Android"

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
            Invoke-WebRequest -Uri $platformToolsUrl -OutFile $platformToolsZip -UseBasicParsing
            Expand-Archive -Path $platformToolsZip -DestinationPath $destDir -Force
            Remove-Item -Path $platformToolsZip -Force -ErrorAction SilentlyContinue
            $adbExecutable = "$destDir\platform-tools\adb.exe"
            Write-Success "Google Platform-Tools installed to: $destDir\platform-tools"
        } catch {
            Write-Err "Failed to download ADB platform-tools: $_"
            if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
            return
        }
    }

    # Ensure ADB directory is persistently added to User PATH
    $adbDir = Split-Path -Parent $adbExecutable
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -split ';' -notcontains $adbDir) {
        $newUserPath = if ($userPath) { "$userPath;$adbDir" } else { $adbDir }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Success "Added ADB to User environment PATH persistently."
    }
    $env:PATH = "$adbDir;$env:PATH"

    # Test ADB execution
    $adbVer = (& $adbExecutable version 2>&1 | Select-Object -First 1)
    Write-Success "ADB Ready: $adbVer"

    Write-Host ""

    # -----------------------------------------------------------------
    # STEP 3: Windows Subsystem for Android (WSA) Verification & Deployment
    # -----------------------------------------------------------------
    Write-Step 3 $TOTAL_STEPS "Verifying Windows Subsystem for Android (WSA)..."

    # Pre-enable WSA Developer Mode (ADB debugging) in registry
    try {
        $wsaRegKey = "HKCU:\Software\Microsoft\WSA"
        if (-not (Test-Path $wsaRegKey)) {
            New-Item -Path $wsaRegKey -Force | Out-Null
        }
        Set-ItemProperty -Path $wsaRegKey -Name "DeveloperModeEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    } catch {}

    $wsaPackage = Get-AppxPackage -Name "*WindowsSubsystemForAndroid*" -ErrorAction SilentlyContinue

    if ($wsaPackage) {
        Write-Success "WSA is already installed! (Version: $($wsaPackage.Version))"
    } elseif ($SkipWsaInstall) {
        Write-Warn "WSA installation skipped by parameter."
    } else {
        Write-Info "WSA is not installed. Searching for local WSA builds..."

        # Look for local WSA builds
        $possibleWsaDirs = @(
            $WsaPath,
            "$scriptBase\WSA",
            "$scriptBase\..\WSA",
            "$env:ProgramFiles\WindowsSubsystemForAndroid",
            "$env:SystemDrive\WSA"
        )

        $wsaDir = $null
        foreach ($cand in $possibleWsaDirs) {
            if ($cand -and (Test-Path "$cand\AppxManifest.xml")) {
                $wsaDir = (Resolve-Path $cand).Path
                break
            }
        }

        # If no unpacked directory found, check for local 7z/zip archives
        if (-not $wsaDir) {
            $archives = @(
                (Get-ChildItem -Path "$scriptBase" -Filter "*WSA*.7z" -ErrorAction SilentlyContinue),
                (Get-ChildItem -Path "$scriptBase\.." -Filter "*WSA*.7z" -ErrorAction SilentlyContinue),
                (Get-ChildItem -Path "$env:SystemDrive\WSA" -Filter "*.7z" -ErrorAction SilentlyContinue)
            ) | Select-Object -ExpandProperty FullName -First 1

            if ($archives -and (Test-Path $archives)) {
                Write-Info "Found local WSA archive: $archives. Extracting..."
                $extractTarget = "$env:SystemDrive\WSA"
                if (-not (Test-Path $extractTarget)) {
                    New-Item -ItemType Directory -Path $extractTarget -Force | Out-Null
                }
                if (Get-Command "7z" -ErrorAction SilentlyContinue) {
                    & 7z x "$archives" "-o$extractTarget" -y | Out-Null
                } else {
                    tar -xf "$archives" -C "$extractTarget" 2>$null
                }
                $found = Get-ChildItem -Path $extractTarget -Filter "AppxManifest.xml" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $wsaDir = $found.DirectoryName
                }
            }
        }

        # Auto-download pre-built WSA release if not found locally
        if (-not $wsaDir) {
            Write-Info "No local WSA package detected. Auto-downloading optimized WSA build..."

            $arch = "x64"
            if ([Environment]::Is64BitOperatingSystem) {
                if ($env:PROCESSOR_ARCHITECTURE -match "ARM") { $arch = "arm64" }
            } else {
                $arch = "x86"
            }

            $wsaTargetDir = "$env:SystemDrive\WSA"
            if (-not (Test-Path $wsaTargetDir)) {
                New-Item -ItemType Directory -Path $wsaTargetDir -Force | Out-Null
            }

            $wsaArchiveTarget = "$env:TEMP\WSA_Build_$arch.7z"
            $wsaDownloadUrl = $null
            $wsaReleaseRepo = "MustardChef/WSABuilds"

            # 1. Query GitHub API for latest release assets
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                Write-Info "Querying $wsaReleaseRepo for latest $arch build..."
                $apiReleases = Invoke-RestMethod -Uri "https://api.github.com/repos/$wsaReleaseRepo/releases?per_page=5" -Headers @{"User-Agent"="PowerShell"} -ErrorAction Stop

                foreach ($rel in $apiReleases) {
                    $matchingAssets = $rel.assets | Where-Object { $_.name -like "*$arch*.7z" }
                    if ($matchingAssets) {
                        $best = $matchingAssets | Where-Object { $_.name -like "*NoGApps*NoAmazon*" } | Select-Object -First 1
                        if (-not $best) {
                            $best = $matchingAssets | Where-Object { $_.name -like "*NoAmazon*" } | Select-Object -First 1
                        }
                        if (-not $best) {
                            $best = $matchingAssets | Select-Object -First 1
                        }
                        if ($best) {
                            $wsaDownloadUrl = $best.browser_download_url
                            Write-Success "Found WSA release: $($best.name) ($([math]::Round($best.size/1MB, 1)) MB)"
                            break
                        }
                    }
                }
            } catch {
                Write-Warn "GitHub API query bypassed: $_"
            }

            # 2. Resilient verified fallback URL if API call is rate-limited
            if (-not $wsaDownloadUrl) {
                if ($arch -eq "arm64") {
                    $wsaDownloadUrl = "https://github.com/MustardChef/WSABuilds/releases/download/Windows_11_2407.40000.4.0_LTS_8_arm64/WSA_2407.40000.4.0_arm64_Release-Nightly-NoGApps-NoAmazon.7z"
                } else {
                    $wsaDownloadUrl = "https://github.com/MustardChef/WSABuilds/releases/download/Windows_11_2407.40000.4.0_LTS_8/WSA_2407.40000.4.0_x64_Release-Nightly-NoGApps-NoAmazon.7z"
                }
                Write-Info "Using verified direct WSA download endpoint: $wsaDownloadUrl"
            }

            # 3. High-speed download with curl.exe progress bar
            Write-Info "Downloading Windows Subsystem for Android (~500 MB)..."
            $downloadSuccess = $false
            if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                try {
                    & curl.exe -L -k --progress-bar -o "$wsaArchiveTarget" "$wsaDownloadUrl"
                    if ((Test-Path $wsaArchiveTarget) -and (Get-Item $wsaArchiveTarget).Length -gt 100MB) {
                        $downloadSuccess = $true
                    }
                } catch {}
            }

            if (-not $downloadSuccess) {
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.DownloadFile($wsaDownloadUrl, $wsaArchiveTarget)
                    if ((Test-Path $wsaArchiveTarget) -and (Get-Item $wsaArchiveTarget).Length -gt 100MB) {
                        $downloadSuccess = $true
                    }
                } catch {}
            }

            if (-not $downloadSuccess) {
                $oldProgress = $ProgressPreference
                $ProgressPreference = 'SilentlyContinue'
                try {
                    Invoke-WebRequest -Uri $wsaDownloadUrl -OutFile $wsaArchiveTarget -UseBasicParsing
                    if ((Test-Path $wsaArchiveTarget) -and (Get-Item $wsaArchiveTarget).Length -gt 100MB) {
                        $downloadSuccess = $true
                    }
                } finally {
                    $ProgressPreference = $oldProgress
                }
            }

            if (-not (Test-Path $wsaArchiveTarget) -or (Get-Item $wsaArchiveTarget).Length -lt 100MB) {
                Write-Err "Failed to download WSA archive from $wsaDownloadUrl"
                if ([Environment]::UserInteractive -and -not $isAutomated) { pause }
                return
            }

            $wsaArchiveSize = [math]::Round(((Get-Item $wsaArchiveTarget).Length / 1MB), 1)
            Write-Success "WSA package downloaded successfully ($wsaArchiveSize MB)."

            # 4. Extract archive using available tool or standalone 7zr.exe
            Write-Info "Extracting WSA into '$wsaTargetDir'..."
            $extractor = $null
            if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
                $extractor = (Get-Command "7z.exe").Source
            } elseif (Test-Path "$env:ProgramFiles\7-Zip\7z.exe") {
                $extractor = "$env:ProgramFiles\7-Zip\7z.exe"
            } elseif (Test-Path "${env:ProgramFiles(x86)}\7-Zip\7z.exe") {
                $extractor = "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
            }

            if ($extractor) {
                & $extractor x "$wsaArchiveTarget" "-o$wsaTargetDir" -y | Out-Null
            } else {
                $tarExtracted = $false
                if (Get-Command "tar.exe" -ErrorAction SilentlyContinue) {
                    try {
                        tar -xf "$wsaArchiveTarget" -C "$wsaTargetDir" 2>$null
                        if (Get-ChildItem -Path $wsaTargetDir -Filter "AppxManifest.xml" -Recurse -Depth 2 -ErrorAction SilentlyContinue) {
                            $tarExtracted = $true
                        }
                    } catch {}
                }

                if (-not $tarExtracted) {
                    Write-Info "Acquiring lightweight 7z unpacker..."
                    $7zrExe = "$env:TEMP\7zr.exe"
                    try {
                        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                            & curl.exe -L -s -k -o "$7zrExe" "https://www.7-zip.org/a/7zr.exe"
                        } else {
                            (New-Object System.Net.WebClient).DownloadFile("https://www.7-zip.org/a/7zr.exe", $7zrExe)
                        }
                        if (Test-Path $7zrExe) {
                            & $7zrExe x "$wsaArchiveTarget" "-o$wsaTargetDir" -y | Out-Null
                            Remove-Item $7zrExe -Force -ErrorAction SilentlyContinue
                        }
                    } catch {
                        Write-Warn "Could not auto-extract with 7zr: $_"
                    }
                }
            }

            Remove-Item $wsaArchiveTarget -Force -ErrorAction SilentlyContinue

            $foundManifest = Get-ChildItem -Path $wsaTargetDir -Filter "AppxManifest.xml" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundManifest) {
                $wsaDir = $foundManifest.DirectoryName
                Write-Success "Extracted WSA build package to: $wsaDir"
            } else {
                Write-Err "Could not find AppxManifest.xml in $wsaTargetDir after extraction!"
                if ([Environment]::UserInteractive -and -not $isAutomated) { pause }
                return
            }
        }

        Write-Success "Found WSA package at: $wsaDir"

        # Install required Appx / MSIX Dependencies recursively
        Write-Info "Checking and registering MSIX/Appx dependencies..."
        $depFiles = Get-ChildItem -Path $wsaDir -Filter "*.appx" -Recurse -ErrorAction SilentlyContinue
        foreach ($dep in $depFiles) {
            try {
                Add-AppxPackage -Path $dep.FullName -ForceApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction SilentlyContinue
                Write-Success "Installed dependency: $($dep.Name)"
            } catch {}
        }
        $msixFiles = Get-ChildItem -Path $wsaDir -Filter "*.msix" -Recurse -ErrorAction SilentlyContinue
        foreach ($dep in $msixFiles) {
            try {
                Add-AppxPackage -Path $dep.FullName -ForceApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction SilentlyContinue
                Write-Success "Installed dependency: $($dep.Name)"
            } catch {}
        }

        # Register WSA Appx Manifest
        Write-Info "Registering Windows Subsystem for Android package..."
        try {
            Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Register "$wsaDir\AppxManifest.xml"
            Start-Sleep -Seconds 3
            $wsaPackage = Get-AppxPackage -Name "*WindowsSubsystemForAndroid*"
            if ($wsaPackage) {
                Write-Success "WSA successfully registered into Windows! (Version: $($wsaPackage.Version))"
            } else {
                throw "WSA registration did not complete."
            }
        } catch {
            Write-Err "Failed to register WSA: $_"
            if ([Environment]::UserInteractive -and -not $isAutomated) { pause }
            return
        }
    }

    Write-Host ""

    # -----------------------------------------------------------------
    # STEP 4: Boot WSA & Auto-Connect ADB (Port 58526)
    # -----------------------------------------------------------------
    Write-Step 4 $TOTAL_STEPS "Starting WSA & Establishing ADB Connection (127.0.0.1:58526)..."

    # Ensure clean ADB server
    & $adbExecutable kill-server 2>$null
    & $adbExecutable start-server 2>$null

    # Trigger WSA VM startup
    Write-Info "Waking up Windows Subsystem for Android VM..."
    Start-Process "wsa://system" -ErrorAction SilentlyContinue

    $adbHost = "127.0.0.1:58526"
    $connected = $false
    $maxRetries = 25

    for ($i = 1; $i -le $maxRetries; $i++) {
        Write-Host "`r  [*] Waiting for Android VM initialization ($adbHost)... Attempt $i/$maxRetries" -NoNewline -ForegroundColor DarkGray
        
        $null = (& $adbExecutable connect $adbHost 2>&1)
        $devicesOut = (& $adbExecutable devices) | Out-String

        if ($devicesOut -match "127\.0\.0\.1:58526\s+device") {
            $connected = $true
            Write-Host ""
            Write-Success "Connected to WSA ADB instance ($adbHost)!"
            break
        }

        # If halfway through and still not connecting, prompt WSA Settings to ensure Developer mode is ON
        if ($i -eq 12) {
            Write-Host ""
            Write-Warn "WSA is still booting. Opening WSA Settings..."
            Write-Warn "IMPORTANT: In WSA Settings -> 'Developer' -> ensure 'Developer mode' is toggled ON."
            Start-Process "wsa-settings:" -ErrorAction SilentlyContinue
        }

        Start-Sleep -Seconds 2
    }

        if (-not $connected) { 
        Write-Host "" 
        Write-Err "Could not connect to WSA ADB on $adbHost within timeout." 
        if ($needsReboot) {
            Write-Host ""
            Write-Warn "======================================================================"
            Write-Warn "  ACTION REQUIRED: ONE-TIME PC RESTART"
            Write-Warn "  Windows Virtual Machine Platform was newly enabled on this machine."
            Write-Warn "  Windows requires a computer restart to load the virtualization hypervisor."
            Write-Warn "  After restarting, simply run the one-liner command again:"
            Write-Warn "    irm https://raw.githubusercontent.com/EduBolthey/Nuvio-WSA-Deployer/main/scripts/Install-Nuvio-WSA.ps1 | iex"
            Write-Warn "  WSA is already installed and ready; it will boot instantly after restart!"
            Write-Warn "======================================================================"
        } else {
            Write-Warn "Please check:" 
            Write-Warn "1. In WSA Settings -> 'Developer' -> ensure 'Developer mode' is toggled ON." 
            Write-Warn "2. If your motherboard has AMD SVM or Intel VT-x disabled in BIOS, please enable it." 
        }
        if ([Environment]::UserInteractive -and -not $isAutomated) { pause } 
        return 
    }

    # Fetch Android specs from WSA
    try {
        $androidModel = (& $adbExecutable -s $adbHost shell getprop ro.product.model).Trim()
        $androidVer   = (& $adbExecutable -s $adbHost shell getprop ro.build.version.release).Trim()
        Write-Success "WSA Android Environment: Model [$androidModel] - Android Version [$androidVer]"
    } catch {}

    Write-Host ""

    # -----------------------------------------------------------------
    # STEP 5: Deploy Nuvio Debug APK
    # -----------------------------------------------------------------
    Write-Step 5 $TOTAL_STEPS "Locating & Installing Nuvio Debug APK..."

    $targetApk = $null

    if ($ApkPath -and (Test-Path $ApkPath)) {
        $targetApk = (Resolve-Path $ApkPath).Path
    } else {
        # Search local project locations
        $candidateApks = @(
            "$scriptBase\..\apks\*.apk",
            "$scriptBase\apks\*.apk",
            "$scriptBase\..\Nuvio-Debug.apk",
            "$scriptBase\Nuvio-Debug.apk",
            "$scriptBase\..\androidApp\build\outputs\apk\full\debug\androidApp-full-debug.apk"
        )

        foreach ($cand in $candidateApks) {
            $found = Get-Item -Path $cand -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $targetApk = $found.FullName
                break
            }
        }
    }

    # If no local APK found, auto-download latest APK from official GitHub repository releases
    if (-not $targetApk -or -not (Test-Path $targetApk)) {
        Write-Info "No local APK found. Checking GitHub Releases..."
        $releaseRepos = @(
            "EduBolthey/Nuvio-WSA-Deployer",
            "EduBolthey/NuvioMobile-Enhanced"
        )
        
        foreach ($repo in $releaseRepos) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                $repoApi = "https://api.github.com/repos/$repo/releases/latest"
                $release = Invoke-RestMethod -Uri $repoApi -Headers @{"User-Agent"="PowerShell"} -ErrorAction Stop
                $apkAsset = $release.assets | Where-Object { $_.name -like "*.apk" } | Select-Object -First 1
                
                if ($apkAsset) {
                    $downloadTarget = "$env:TEMP\$($apkAsset.name)"
                    Write-Info "Downloading $($apkAsset.name) from $repo..."
                    $downloadSuccess = $false
                    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                        try {
                            & curl.exe -L -k --progress-bar -o "$downloadTarget" "$($apkAsset.browser_download_url)"
                            if ((Test-Path $downloadTarget) -and (Get-Item $downloadTarget).Length -gt 10MB) {
                                $downloadSuccess = $true
                            }
                        } catch {}
                    }
                    if (-not $downloadSuccess) {
                        try {
                            $wc = New-Object System.Net.WebClient
                            $wc.DownloadFile($apkAsset.browser_download_url, $downloadTarget)
                            if ((Test-Path $downloadTarget) -and (Get-Item $downloadTarget).Length -gt 10MB) {
                                $downloadSuccess = $true
                            }
                        } catch {}
                    }
                    if (-not $downloadSuccess) {
                        $oldProgress = $ProgressPreference
                        $ProgressPreference = 'SilentlyContinue'
                        try {
                            Invoke-WebRequest -Uri $apkAsset.browser_download_url -OutFile $downloadTarget -UseBasicParsing
                        } finally {
                            $ProgressPreference = $oldProgress
                        }
                    }
                    if (Test-Path $downloadTarget) {
                        $targetApk = $downloadTarget
                        Write-Success "Downloaded release APK: $targetApk"
                        break
                    }
                }
            } catch {}
        }
    }

    if (-not $targetApk -or -not (Test-Path $targetApk)) {
        Write-Err "Nuvio APK not found locally or remotely!"
        Write-Info "Please place your 'Nuvio-Debug.apk' inside the 'apks/' folder or project root."
        if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
        return
    }

    $apkSizeMB = [math]::Round(((Get-Item $targetApk).Length / 1MB), 2)
    Write-Success "Target APK: $(Split-Path -Leaf $targetApk) ($apkSizeMB MB)"
    Write-Info "Installing APK with auto-granted runtime permissions (-r -d -g)..."

    # Install APK via ADB
    $installResult = (& $adbExecutable -s $adbHost install -r -d -g "$targetApk" 2>&1) | Out-String

    if ($installResult -match "Success") {
        Write-Success "Nuvio Debug deployed successfully to WSA!"
    } else {
        Write-Err "APK installation returned: $installResult"
        Write-Warn "Retrying with standard install options..."
        $installResult2 = (& $adbExecutable -s $adbHost install -r "$targetApk" 2>&1) | Out-String
        if ($installResult2 -match "Success") {
            Write-Success "Nuvio Debug deployed successfully!"
        } else {
            Write-Err "Installation failed: $installResult2"
            if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
            return
        }
    }

    # Determine package ID dynamically
    $packageId = "com.nuviodebug.com"
    $pkgList = (& $adbExecutable -s $adbHost shell pm list packages) | Out-String
    if ($pkgList -notmatch "com\.nuviodebug\.com" -and $pkgList -match "com\.nuvio\.enhanced") {
        $packageId = "com.nuvio.enhanced"
    }
    Write-Success "Active Package ID: $packageId"

    # -----------------------------------------------------------------
    # 5.1 Streaming Configuration (Preserves Existing Data / Seeds Fresh Setup)
    # -----------------------------------------------------------------
    if (-not $SkipPresetConfig) {
        Write-Info "Checking streaming catalog configuration..."
        try {
            $hasExistingAddons = $false
            $checkAddons = (& $adbExecutable -s $adbHost shell "run-as $packageId ls /data/data/$packageId/shared_prefs/nuvio_addons.xml" 2>$null) | Out-String
            if ($checkAddons -match "nuvio_addons\.xml") {
                $hasExistingAddons = $true
            }

            if ($hasExistingAddons) {
                Write-Success "Existing streaming configuration detected. Preserving personal addons and watch history!"
            } else {
                Write-Info "Provisioning standard streaming catalog configuration..."
                $presetSourceDir = $null
                if ($PresetDir -and (Test-Path $PresetDir)) {
                    $presetSourceDir = (Resolve-Path $PresetDir).Path
                } elseif (Test-Path "$scriptBase\..\presets\$packageId") {
                    $presetSourceDir = (Resolve-Path "$scriptBase\..\presets\$packageId").Path
                } elseif (Test-Path "$scriptBase\presets\$packageId") {
                    $presetSourceDir = (Resolve-Path "$scriptBase\presets\$packageId").Path
                }

                if ($presetSourceDir) {
                    $xmlFiles = Get-ChildItem -Path $presetSourceDir -Filter "*.xml"
                    foreach ($xml in $xmlFiles) {
                        $tmpTarget = "/data/local/tmp/$($xml.Name)"
                        & $adbExecutable -s $adbHost push "$($xml.FullName)" "$tmpTarget" 2>$null | Out-Null
                        & $adbExecutable -s $adbHost shell "run-as $packageId cp $tmpTarget /data/data/$packageId/shared_prefs/$($xml.Name) && run-as $packageId chmod 660 /data/data/$packageId/shared_prefs/$($xml.Name)" 2>$null | Out-Null
                        & $adbExecutable -s $adbHost shell "rm $tmpTarget" 2>$null | Out-Null
                    }
                    Write-Success "Loaded streaming catalog presets from: $presetSourceDir"
                } else {
                    # Generate clean, privacy-safe Cinemeta catalog preset on the fly without BOM
                    $cleanAddonsXml = "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>`n<map>`n    <string name=`"installed_manifest_urls_1`">https://v3-cinemeta.strem.io/manifest.json</string>`n    <string name=`"installed_manifest_enabled_states_1`">https://v3-cinemeta.strem.io/manifest.json&#9;true</string>`n</map>`n"
                    $cleanPlayerXml = "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>`n<map>`n    <string name=`"resize_mode_1`">Auto</string>`n</map>`n"
                    $tempAddonsFile = "$env:TEMP\nuvio_addons_init.xml"
                    $tempPlayerFile = "$env:TEMP\nuvio_player_init.xml"
                    
                    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                    [System.IO.File]::WriteAllText($tempAddonsFile, $cleanAddonsXml, $utf8NoBom)
                    [System.IO.File]::WriteAllText($tempPlayerFile, $cleanPlayerXml, $utf8NoBom)

                    & $adbExecutable -s $adbHost push "$tempAddonsFile" "/data/local/tmp/nuvio_addons.xml" 2>$null | Out-Null
                    & $adbExecutable -s $adbHost push "$tempPlayerFile" "/data/local/tmp/nuvio_player_settings.xml" 2>$null | Out-Null
                    & $adbExecutable -s $adbHost shell "run-as $packageId cp /data/local/tmp/nuvio_addons.xml /data/data/$packageId/shared_prefs/nuvio_addons.xml && run-as $packageId cp /data/local/tmp/nuvio_player_settings.xml /data/data/$packageId/shared_prefs/nuvio_player_settings.xml && run-as $packageId chmod 660 /data/data/$packageId/shared_prefs/nuvio_addons.xml /data/data/$packageId/shared_prefs/nuvio_player_settings.xml" 2>$null | Out-Null
                    & $adbExecutable -s $adbHost shell "rm /data/local/tmp/nuvio_addons.xml /data/local/tmp/nuvio_player_settings.xml" 2>$null | Out-Null

                    Remove-Item -Path $tempAddonsFile, $tempPlayerFile -Force -ErrorAction SilentlyContinue
                    Write-Success "Standard open-source catalog (Stremio Cinemeta) provisioned."
                }
            }
        } catch {
            Write-Warn "Could not apply default catalog presets: $_ (App will start with defaults)"
        }
    }

    Write-Host ""

    # -----------------------------------------------------------------
    # STEP 6: Desktop Shortcut Creation & Instant Launch
    # -----------------------------------------------------------------
    Write-Step 6 $TOTAL_STEPS "Creating Desktop Shortcuts & Launching Nuvio Debug..."

    # Create Windows Desktop Shortcut
    try {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "Nuvio Debug (WSA).lnk"
        
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-WindowStyle Hidden -Command `"Start-Process 'wsa://$packageId'`""
        $shortcut.Description = "Launch Nuvio Enhanced on Windows Subsystem for Android"
        $shortcut.Save()
        Write-Success "Created Desktop Shortcut: 'Nuvio Debug (WSA)'"
    } catch {
        Write-Warn "Could not create Desktop shortcut: $_"
    }

    # Instant Auto-Launch App into Foreground
    Write-Info "Launching Nuvio Debug into foreground..."
    & $adbExecutable -s $adbHost shell monkey -p $packageId -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
    Start-Process "wsa://$packageId" -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "             ✨ NUVIO DEBUG IS READY TO STREAM! ✨                     " -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  * Windows Subsystem for Android : Active & Connected" -ForegroundColor Gray
    Write-Host "  * ADB Port                      : 127.0.0.1:58526" -ForegroundColor Gray
    Write-Host "  * App Package                   : $packageId" -ForegroundColor Gray
    Write-Host "  * Desktop Shortcut              : Created on Desktop" -ForegroundColor Gray
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host ""

    if ($needsReboot -and -not $NoRebootPrompt) {
        Write-Warn "SYSTEM NOTICE: Windows Virtual Machine Platform was newly enabled on this machine."
        Write-Warn "If video streaming exhibits playback stuttering, a one-time PC reboot will activate hardware acceleration."
    }

        $isAutomated = $NonInteractive -or $env:NON_INTERACTIVE -or $env:CI -or [Console]::IsInputRedirected
    if ([Environment]::UserInteractive -and -not $isAutomated -and $Host.Name -notmatch "Default Host") {
        try {
            Write-Host "Press any key to close this installer..." -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        } catch {}
    }
}

# Auto-execute entry point with passed arguments
Invoke-NuvioWsaDeployer @args
