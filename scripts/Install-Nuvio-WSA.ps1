# =====================================================================
#  Nuvio Enhanced - Automated One-Click WSA & Nuvio Debug Installer
# =====================================================================
#  Repository : EduBolthey/Nuvio-WSA-Deployer
#  Purpose    : Fully automated zero-touch setup for Windows Subsystem for
#               Android (WSA), system prerequisites, ADB, environment PATH,
#               and deployment of Nuvio Debug ready to stream.
#  Security   : 100% portable, zero hardcoded credentials, zero personal paths.
# =====================================================================

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

# ---------------------------------------------------------------------
# 0. Console Configuration & Elevation Handler
# ---------------------------------------------------------------------
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$Host.UI.RawUI.WindowTitle = "Nuvio Debug - One-Click WSA Auto Deployer"

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
        $argList = "-NoProfile -ExecutionPolicy Bypass"
        if ($PSCommandPath) {
            $argList += " -File `"$PSCommandPath`""
            if ($ApkPath) { $argList += " -ApkPath `"$ApkPath`"" }
            if ($WsaPath) { $argList += " -WsaPath `"$WsaPath`"" }
            if ($PresetDir) { $argList += " -PresetDir `"$PresetDir`"" }
            if ($SkipWsaInstall) { $argList += " -SkipWsaInstall" }
            if ($SkipPresetConfig) { $argList += " -SkipPresetConfig" }
            if ($NoRebootPrompt) { $argList += " -NoRebootPrompt" }
            if ($NonInteractive) { $argList += " -NonInteractive" }
        } else {
            $oneLiner = "irm https://raw.githubusercontent.com/EduBolthey/Nuvio-WSA-Deployer/main/scripts/Install-Nuvio-WSA.ps1 | iex"
            $argList += " -Command `"$oneLiner`""
        }

        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        exit 0
    } catch {
        Write-Host "  [!] UAC Elevation prompt not available or skipped in current shell." -ForegroundColor Yellow
        Write-Host "  [!] Proceeding with existing session permissions..." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------
# UI Styling Functions
# ---------------------------------------------------------------------
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

# ---------------------------------------------------------------------
# STEP 1: Windows System Checks & Virtualization Prerequisites
# ---------------------------------------------------------------------
Write-Step 1 $TOTAL_STEPS "Checking Windows System Prerequisites & Virtualization..."

# 1.1 Architecture & OS Build Check
$os = Get-CimInstance Win32_OperatingSystem
$osBuild = [int]$os.BuildNumber
$is64Bit = [Environment]::Is64BitOperatingSystem

if (-not $is64Bit -or $osBuild -lt 19041) {
    Write-Err "Unsupported Windows version ($($os.Caption) Build $osBuild). WSA requires Windows 10 (Build 19041+) or Windows 11 (64-bit)."
    if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
    exit 1
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

# ---------------------------------------------------------------------
# STEP 2: Android Debug Bridge (ADB) & PATH Auto-Configuration
# ---------------------------------------------------------------------
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
        "$PSScriptRoot\tools\platform-tools\adb.exe",
        "$PSScriptRoot\..\tools\platform-tools\adb.exe",
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
        exit 1
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

# ---------------------------------------------------------------------
# STEP 3: Windows Subsystem for Android (WSA) Verification & Deployment
# ---------------------------------------------------------------------
Write-Step 3 $TOTAL_STEPS "Verifying Windows Subsystem for Android (WSA)..."

$wsaPackage = Get-AppxPackage -Name "*WindowsSubsystemForAndroid*" -ErrorAction SilentlyContinue

if ($wsaPackage) {
    Write-Success "WSA is already installed! (Version: $($wsaPackage.Version))"
} elseif ($SkipWsaInstall) {
    Write-Warn "WSA installation skipped by parameter."
} else {
    Write-Info "WSA is not installed. Searching for WSA package sources..."

    # Look for local WSA builds
    $possibleWsaDirs = @(
        $WsaPath,
        "$PSScriptRoot\WSA",
        "$PSScriptRoot\..\WSA",
        "$env:ProgramFiles\WindowsSubsystemForAndroid",
        "C:\WSA"
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
            Get-ChildItem -Path "$PSScriptRoot" -Filter "*WSA*.7z" -ErrorAction SilentlyContinue,
            Get-ChildItem -Path "$PSScriptRoot\.." -Filter "*WSA*.7z" -ErrorAction SilentlyContinue,
            Get-ChildItem -Path "C:\WSA" -Filter "*.7z" -ErrorAction SilentlyContinue
        ) | Select-Object -ExpandProperty FullName -First 1

        if ($archives -and (Test-Path $archives)) {
            Write-Info "Found local WSA archive: $archives. Extracting..."
            $extractTarget = "$env:ProgramFiles\WindowsSubsystemForAndroid"
            if (-not (Test-Path $extractTarget)) {
                New-Item -ItemType Directory -Path $extractTarget -Force | Out-Null
            }
            if (Get-Command "7z" -ErrorAction SilentlyContinue) {
                & 7z x "$archives" "-o$extractTarget" -y | Out-Null
            } else {
                tar -xf "$archives" -C "$extractTarget" 2>$null
            }
            if (Test-Path "$extractTarget\AppxManifest.xml") {
                $wsaDir = $extractTarget
            }
        }
    }

    # If still not found, provide download instructions
    if (-not $wsaDir) {
        Write-Err "No local WSA installation package found!"
        Write-Info "You can download a clean pre-built WSA release (x64 / arm64) from:"
        Write-Host "   https://github.com/Mustafacank/WSABuilds/releases" -ForegroundColor Cyan
        Write-Info "Extract the WSA archive into a folder named 'WSA' and re-run this script."
        if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
        exit 1
    }

    Write-Success "Found WSA package at: $wsaDir"

    # Install required Appx Dependencies if present
    Write-Info "Checking and registering MSIX/Appx dependencies..."
    $depFiles = Get-ChildItem -Path $wsaDir -Filter "*.appx" -ErrorAction SilentlyContinue
    foreach ($dep in $depFiles) {
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
        if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
        exit 1
    }
}

Write-Host ""

# ---------------------------------------------------------------------
# STEP 4: Boot WSA & Auto-Connect ADB (Port 58526)
# ---------------------------------------------------------------------
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
    Write-Warn "Please check:"
    Write-Warn "1. Is Developer Mode enabled in Windows Subsystem for Android Settings?"
    Write-Warn "2. If this is a fresh setup and Virtual Machine Platform was just enabled, a PC restart is required."
    if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
    exit 1
}

# Fetch Android specs from WSA
try {
    $androidModel = (& $adbExecutable -s $adbHost shell getprop ro.product.model).Trim()
    $androidVer   = (& $adbExecutable -s $adbHost shell getprop ro.build.version.release).Trim()
    Write-Success "WSA Android Environment: Model [$androidModel] - Android Version [$androidVer]"
} catch {}

Write-Host ""

# ---------------------------------------------------------------------
# STEP 5: Deploy Nuvio Debug APK
# ---------------------------------------------------------------------
Write-Step 5 $TOTAL_STEPS "Locating & Installing Nuvio Debug APK..."

$targetApk = $null

if ($ApkPath -and (Test-Path $ApkPath)) {
    $targetApk = (Resolve-Path $ApkPath).Path
} else {
    # Search local project locations
    $candidateApks = @(
        "$PSScriptRoot\..\apks\*.apk",
        "$PSScriptRoot\..\Nuvio-Debug.apk",
        "$PSScriptRoot\Nuvio-Debug.apk",
        "$PSScriptRoot\..\androidApp\build\outputs\apk\full\debug\androidApp-full-debug.apk"
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
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        $repoApi = "https://api.github.com/repos/EduBolthey/NuvioMobile-Enhanced/releases/latest"
        $release = Invoke-RestMethod -Uri $repoApi -Headers @{"User-Agent"="PowerShell"} -ErrorAction Stop
        $apkAsset = $release.assets | Where-Object { $_.name -like "*.apk" } | Select-Object -First 1
        
        if ($apkAsset) {
            $downloadTarget = "$env:TEMP\$($apkAsset.name)"
            Write-Info "Downloading $($apkAsset.name)..."
            Invoke-WebRequest -Uri $apkAsset.browser_download_url -OutFile $downloadTarget -UseBasicParsing
            $targetApk = $downloadTarget
            Write-Success "Downloaded release APK: $targetApk"
        }
    } catch {
        Write-Warn "Could not auto-download release asset: $_"
    }
}

if (-not $targetApk -or -not (Test-Path $targetApk)) {
    Write-Err "Nuvio APK not found locally or remotely!"
    Write-Info "Please place your 'Nuvio-Debug.apk' inside the 'apks/' folder and re-run."
    if ([Environment]::UserInteractive -and -not $NonInteractive) { pause }
    exit 1
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
        exit 1
    }
}

# Determine package ID dynamically
$packageId = "com.nuviodebug.com"
$pkgList = (& $adbExecutable -s $adbHost shell pm list packages) | Out-String
if ($pkgList -notmatch "com\.nuviodebug\.com" -and $pkgList -match "com\.nuvio\.enhanced") {
    $packageId = "com.nuvio.enhanced"
}
Write-Success "Active Package ID: $packageId"

# ---------------------------------------------------------------------
# 5.1 Auto-Configure Streaming Presets (Public Open-Source Cinemeta)
# ---------------------------------------------------------------------
if (-not $SkipPresetConfig) {
    Write-Info "Provisioning standard streaming catalog configuration..."
    try {
        # Check if user specified a custom preset directory
        $presetSourceDir = $null
        if ($PresetDir -and (Test-Path $PresetDir)) {
            $presetSourceDir = (Resolve-Path $PresetDir).Path
        } elseif (Test-Path "$PSScriptRoot\..\presets\$packageId") {
            $presetSourceDir = (Resolve-Path "$PSScriptRoot\..\presets\$packageId").Path
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
            # Generate clean, privacy-safe Cinemeta catalog preset on the fly
            $cleanAddonsXml = @"
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="installed_manifest_urls_1">https://v3-cinemeta.strem.io/manifest.json</string>
    <string name="installed_manifest_enabled_states_1">https://v3-cinemeta.strem.io/manifest.json&#9;true</string>
</map>
"@
            $cleanPlayerXml = @"
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="resize_mode_1">Auto</string>
</map>
"@
            $tempAddonsFile = "$env:TEMP\nuvio_addons_init.xml"
            $tempPlayerFile = "$env:TEMP\nuvio_player_init.xml"
            Set-Content -Path $tempAddonsFile -Value $cleanAddonsXml -Encoding UTF8
            Set-Content -Path $tempPlayerFile -Value $cleanPlayerXml -Encoding UTF8

            & $adbExecutable -s $adbHost push "$tempAddonsFile" "/data/local/tmp/nuvio_addons.xml" 2>$null | Out-Null
            & $adbExecutable -s $adbHost push "$tempPlayerFile" "/data/local/tmp/nuvio_player_settings.xml" 2>$null | Out-Null
            & $adbExecutable -s $adbHost shell "run-as $packageId cp /data/local/tmp/nuvio_addons.xml /data/data/$packageId/shared_prefs/nuvio_addons.xml && run-as $packageId cp /data/local/tmp/nuvio_player_settings.xml /data/data/$packageId/shared_prefs/nuvio_player_settings.xml" 2>$null | Out-Null
            & $adbExecutable -s $adbHost shell "rm /data/local/tmp/nuvio_addons.xml /data/local/tmp/nuvio_player_settings.xml" 2>$null | Out-Null

            Remove-Item -Path $tempAddonsFile, $tempPlayerFile -Force -ErrorAction SilentlyContinue
            Write-Success "Standard open-source catalog (Stremio Cinemeta) provisioned."
        }
    } catch {
        Write-Warn "Could not apply default catalog presets: $_ (App will start with defaults)"
    }
}

Write-Host ""

# ---------------------------------------------------------------------
# STEP 6: Desktop Shortcut Creation & Instant Launch
# ---------------------------------------------------------------------
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

if ([Environment]::UserInteractive -and -not $NonInteractive -and $Host.Name -notmatch "Default Host") {
    try {
        Write-Host "Press any key to close this installer..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } catch {}
}
