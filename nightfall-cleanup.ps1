[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$AdminPhase
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $env:LOCALAPPDATA 'Nightfall\cleanup.log'
$logDirectory = Split-Path -Parent $logPath
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

function Write-Log {
    param([string]$Message)

    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -LiteralPath $logPath -Value $entry
    Write-Host $entry
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-FolderContents {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Log "Not found, skipped: $Path"
        return
    }

    Write-Log "Cleaning: $Path"
    try {
        $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    }
    catch {
        Write-Log "Could not list '$Path': $($_.Exception.Message)"
        return
    }

    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            Write-Log "Removed: $($item.FullName)"
        }
        catch {
            Write-Log "Could not remove '$($item.FullName)': $($_.Exception.Message)"
        }
    }
}

function Invoke-DiskCleanup {
    param([string]$RunAs)

    $cleanmgr = Join-Path $env:SystemRoot 'System32\cleanmgr.exe'
    if (-not (Test-Path -LiteralPath $cleanmgr -PathType Leaf)) {
        Write-Log "Disk Cleanup was not found at '$cleanmgr'."
        return
    }

    Write-Log "Running Disk Cleanup for $env:SystemDrive as $RunAs with default settings and no prompts."
    try {
        Start-Process -FilePath $cleanmgr -ArgumentList "/d $env:SystemDrive /VERYLOWDISK" -Wait -ErrorAction Stop
        Write-Log "Disk Cleanup closed ($RunAs)."
    }
    catch {
        Write-Log "Could not run Disk Cleanup ($RunAs): $($_.Exception.Message)"
    }
}

if ($Install) {
    $startupFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    $shortcutPath = Join-Path $startupFolder 'Nightfall Cleanup.lnk'
    $powershellPath = Join-Path $PSHOME 'powershell.exe'
    $shortcutArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershellPath
    $shortcut.Arguments = $shortcutArguments
    $shortcut.WorkingDirectory = Split-Path -Parent $PSCommandPath
    $shortcut.Description = 'Run Nightfall cleanup at sign-in'
    $shortcut.WindowStyle = 1
    $shortcut.Save()
    Write-Log "Installed sign-in shortcut: $shortcutPath"
    exit 0
}

if ($AdminPhase) {
    if (-not (Test-IsAdministrator)) {
        Write-Log 'The elevated cleanup phase did not receive administrator access.'
        exit 1
    }

    Remove-FolderContents -Path (Join-Path $env:SystemRoot 'Temp')
    Remove-FolderContents -Path $env:TEMP
    Remove-FolderContents -Path (Join-Path $env:SystemRoot 'Prefetch')

    $serviceStates = @{}
    foreach ($serviceName in @('wuauserv', 'bits')) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($null -ne $service) {
            $serviceStates[$serviceName] = ($service.Status -eq 'Running')
            if ($service.Status -eq 'Running') {
                try {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    (Get-Service -Name $serviceName).WaitForStatus(
                        [System.ServiceProcess.ServiceControllerStatus]::Stopped,
                        [TimeSpan]::FromSeconds(30)
                    )
                    Write-Log "Stopped service: $serviceName"
                }
                catch {
                    Write-Log "Could not stop service '$serviceName': $($_.Exception.Message)"
                }
            }
        }
    }

    try {
        Remove-FolderContents -Path (Join-Path $env:SystemRoot 'SoftwareDistribution')
    }
    finally {
        foreach ($serviceName in $serviceStates.Keys) {
            if ($serviceStates[$serviceName]) {
                try {
                    Start-Service -Name $serviceName -ErrorAction Stop
                    Write-Log "Started service: $serviceName"
                }
                catch {
                    Write-Log "Could not restart service '$serviceName': $($_.Exception.Message)"
                }
            }
        }
    }

    Invoke-DiskCleanup -RunAs 'administrator'
    exit 0
}

if (Test-IsAdministrator) {
    Write-Log 'Start this script without administrator rights so the final Disk Cleanup run can remain a user process.'
    exit 1
}

$elevatedArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -AdminPhase"
try {
    Write-Log 'Requesting administrator access for Windows-wide cleanup.'
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
        -ArgumentList $elevatedArguments -Verb RunAs -Wait -WindowStyle Normal -ErrorAction Stop
}
catch {
    Write-Log "Administrator phase was not completed: $($_.Exception.Message)"
}

Invoke-DiskCleanup -RunAs 'the signed-in user'
Write-Log "Nightfall cleanup finished. Log: $logPath"
