[CmdletBinding()]
param(
    [Alias("s")]
    [string]$DeviceId,

    [string]$GradleTask = ":app:installDebug",

    [string]$ApplicationId = "com.jsxposed.x",

    [string]$ActivityName = ".MainActivity",

    [string]$FlutterExecutable = "flutter",

    [int]$PostInstallDelaySeconds = 8,

    [bool]$ForceStopBeforeLaunch = $true,

    [string[]]$GradleArgs = @(
        "-Pandroid.injected.invoked.from.ide=true"
    ),

    [string[]]$AttachArgs = @(),

    [switch]$SkipInstall,

    [switch]$SkipLaunch,

    [switch]$SkipAttach
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$androidDir = Join-Path $repoRoot "android"
$gradlew = Join-Path $androidDir "gradlew.bat"
$workspaceXml = Join-Path $repoRoot ".idea\workspace.xml"
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$localPropertiesPath = Join-Path $androidDir "local.properties"

function Get-PubspecVersionInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PubspecFile
    )

    if (-not (Test-Path $PubspecFile)) {
        throw "pubspec.yaml not found: $PubspecFile"
    }

    $versionLine = Get-Content $PubspecFile -Encoding UTF8 |
        Where-Object { $_ -match '^\s*version\s*:\s*' } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($versionLine)) {
        throw "No version field found in pubspec.yaml"
    }

    $versionValue = ($versionLine -replace '^\s*version\s*:\s*', '').Trim()
    if ($versionValue -notmatch '^(?<name>[^+\s]+)\+(?<code>\d+)$') {
        throw "Unsupported pubspec version format: $versionValue"
    }

    return @{
        VersionName = $matches['name']
        VersionCode = $matches['code']
    }
}

function Sync-FlutterVersionToLocalProperties {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PubspecFile,

        [Parameter(Mandatory = $true)]
        [string]$LocalPropertiesFile
    )

    $versionInfo = Get-PubspecVersionInfo -PubspecFile $PubspecFile

    $lines = @()
    if (Test-Path $LocalPropertiesFile) {
        $lines = @(Get-Content $LocalPropertiesFile -Encoding UTF8)
    }

    $updatedVersionName = $false
    $updatedVersionCode = $false

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^flutter\.versionName=') {
            $lines[$index] = "flutter.versionName=$($versionInfo.VersionName)"
            $updatedVersionName = $true
            continue
        }

        if ($lines[$index] -match '^flutter\.versionCode=') {
            $lines[$index] = "flutter.versionCode=$($versionInfo.VersionCode)"
            $updatedVersionCode = $true
        }
    }

    if (-not $updatedVersionName) {
        $lines += "flutter.versionName=$($versionInfo.VersionName)"
    }

    if (-not $updatedVersionCode) {
        $lines += "flutter.versionCode=$($versionInfo.VersionCode)"
    }

    [System.IO.File]::WriteAllLines(
        $LocalPropertiesFile,
        $lines,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "Synced Flutter version to local.properties: versionName=$($versionInfo.VersionName), versionCode=$($versionInfo.VersionCode)" -ForegroundColor DarkGreen
}

function Resolve-LaunchComponent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResolvedApplicationId,

        [Parameter(Mandatory = $true)]
        [string]$ResolvedActivityName
    )

    if ($ResolvedActivityName.Contains("/")) {
        return $ResolvedActivityName
    }

    return "$ResolvedApplicationId/$ResolvedActivityName"
}

function Assert-ToolAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $CommandName"
    }
}

function Get-AndroidStudioSelectedDeviceId {
    if (-not (Test-Path $workspaceXml)) {
        return $null
    }

    try {
        [xml]$workspace = Get-Content $workspaceXml
        $component = $workspace.project.component | Where-Object { $_.name -eq "ExecutionTargetManager" } | Select-Object -First 1
        if ($null -eq $component) {
            return $null
        }

        $selectedTarget = [string]$component.SELECTED_TARGET
        if ([string]::IsNullOrWhiteSpace($selectedTarget)) {
            return $null
        }

        $match = [regex]::Match($selectedTarget, 'serial=([^\]]+)')
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-SingleConnectedAdbDeviceId {
    Assert-ToolAvailable -CommandName "adb"

    $adbOutput = & adb devices
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query adb devices."
    }

    $deviceIds = @(
        $adbOutput |
            Where-Object { $_ -match '^\s*([^\s]+)\s+device\s*$' -and $_ -notmatch '^List of devices attached' } |
            ForEach-Object {
                if ($_ -match '^\s*([^\s]+)\s+device\s*$') {
                    $matches[1]
                }
            }
    )

    if ($deviceIds.Count -eq 1) {
        return $deviceIds[0]
    }

    if ($deviceIds.Count -gt 1) {
        throw "Multiple adb devices detected. Select a device in Android Studio or pass -DeviceId explicitly."
    }

    throw "No adb device detected. Select a device in Android Studio or connect one manually."
}

function Get-ConnectedAdbDeviceIds {
    Assert-ToolAvailable -CommandName "adb"

    $adbOutput = & adb devices
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query adb devices."
    }

    return @(
        $adbOutput |
            Where-Object { $_ -match '^\s*([^\s]+)\s+device\s*$' -and $_ -notmatch '^List of devices attached' } |
            ForEach-Object {
                if ($_ -match '^\s*([^\s]+)\s+device\s*$') {
                    $matches[1]
                }
            }
    )
}

function Resolve-PreferredConnectedDeviceId {
    param(
        [string]$PreferredDeviceId
    )

    if ([string]::IsNullOrWhiteSpace($PreferredDeviceId)) {
        return $null
    }

    $deviceIds = Get-ConnectedAdbDeviceIds
    if ($deviceIds -contains $PreferredDeviceId) {
        return $PreferredDeviceId
    }

    return $null
}

function Resolve-DeviceId {
    $explicitDeviceId = Resolve-PreferredConnectedDeviceId -PreferredDeviceId $DeviceId
    if ($explicitDeviceId) {
        return $explicitDeviceId
    }

    if ($DeviceId) {
        return $DeviceId
    }

    $envDeviceId = Resolve-PreferredConnectedDeviceId -PreferredDeviceId $env:ANDROID_SERIAL
    if ($envDeviceId) {
        return $envDeviceId
    }

    if ($env:ANDROID_SERIAL) {
        return $env:ANDROID_SERIAL
    }

    $androidStudioDeviceId = Resolve-PreferredConnectedDeviceId -PreferredDeviceId (Get-AndroidStudioSelectedDeviceId)
    if ($androidStudioDeviceId) {
        return $androidStudioDeviceId
    }

    return Get-SingleConnectedAdbDeviceId
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [string]$WorkingDirectory = $repoRoot,

        [hashtable]$EnvironmentOverrides = @{}
    )

    Write-Host ""
    Write-Host "==> $Description" -ForegroundColor Cyan
    Write-Host "$FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray

    $previousEnv = @{}

    Push-Location $WorkingDirectory
    try {
        foreach ($key in $EnvironmentOverrides.Keys) {
            $previousEnv[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
            [Environment]::SetEnvironmentVariable($key, $EnvironmentOverrides[$key], "Process")
        }

        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$Description failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        foreach ($key in $EnvironmentOverrides.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previousEnv[$key], "Process")
        }
        Pop-Location
    }
}

if (-not (Test-Path $gradlew)) {
    throw "Gradle wrapper not found: $gradlew"
}

Sync-FlutterVersionToLocalProperties -PubspecFile $pubspecPath -LocalPropertiesFile $localPropertiesPath

$launchComponent = Resolve-LaunchComponent -ResolvedApplicationId $ApplicationId -ResolvedActivityName $ActivityName
$resolvedDeviceId = $null

if (-not ($SkipInstall -and $SkipLaunch -and $SkipAttach)) {
    $resolvedDeviceId = Resolve-DeviceId
    Write-Host "Using device: $resolvedDeviceId" -ForegroundColor Yellow
}

if (-not $SkipInstall) {
    $gradleEnv = @{}
    if ($resolvedDeviceId) {
        $gradleEnv["ANDROID_SERIAL"] = $resolvedDeviceId
    }

    Invoke-CheckedCommand `
        -Description "Installing app with Android Studio style Gradle task $GradleTask" `
        -FilePath $gradlew `
        -Arguments (@($GradleTask) + $GradleArgs) `
        -WorkingDirectory $androidDir `
        -EnvironmentOverrides $gradleEnv

    if ($PostInstallDelaySeconds -gt 0) {
        Write-Host ""
        Write-Host "==> Waiting $PostInstallDelaySeconds second(s) for package replacement broadcasts and LSPosed rescan" -ForegroundColor Cyan
        Start-Sleep -Seconds $PostInstallDelaySeconds
    }
}

if (-not $SkipLaunch) {
    Assert-ToolAvailable -CommandName "adb"

    if ($ForceStopBeforeLaunch -and $ApplicationId) {
        $forceStopArgs = @()
        if ($resolvedDeviceId) {
            $forceStopArgs += @("-s", $resolvedDeviceId)
        }
        $forceStopArgs += @(
            "shell",
            "am",
            "force-stop",
            $ApplicationId
        )

        Invoke-CheckedCommand `
            -Description "Force-stopping $ApplicationId before cold launch" `
            -FilePath "adb" `
            -Arguments $forceStopArgs `
            -WorkingDirectory $repoRoot
    }

    $adbArgs = @()
    if ($resolvedDeviceId) {
        $adbArgs += @("-s", $resolvedDeviceId)
    }
    $adbArgs += @(
        "shell",
        "am",
        "start",
        "-a",
        "android.intent.action.MAIN",
        "-c",
        "android.intent.category.LAUNCHER",
        "-n",
        $launchComponent
    )

    Invoke-CheckedCommand `
        -Description "Launching $launchComponent" `
        -FilePath "adb" `
        -Arguments $adbArgs `
        -WorkingDirectory $repoRoot
}

if (-not $SkipAttach) {
    Assert-ToolAvailable -CommandName $FlutterExecutable

    $flutterArgs = @("attach")
    if ($resolvedDeviceId) {
        $flutterArgs += @("-d", $resolvedDeviceId)
    }
    $flutterArgs += $AttachArgs

    Invoke-CheckedCommand `
        -Description "Attaching Flutter debugger" `
        -FilePath $FlutterExecutable `
        -Arguments $flutterArgs `
        -WorkingDirectory $repoRoot
}

Write-Host ""
if ($SkipAttach) {
    Write-Host "Tip: use Android Studio's Flutter Attach to get the Flutter tool window and hot reload buttons." -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "==> Finished." -ForegroundColor Green
