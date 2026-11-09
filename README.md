# Nightfall Cleanup

A PowerShell utility for cleaning temporary Windows files and running Disk Cleanup at sign-in.

## What It Does

The script requests administrator access, then attempts to remove the contents of:

- `C:\Windows\Temp`
- The signed-in user's `%TEMP%` directory
- `C:\Windows\Prefetch`
- `C:\Windows\SoftwareDistribution`

Before clearing SoftwareDistribution, it stops Windows Update (`wuauserv`) and Background Intelligent Transfer Service (`bits`), then restarts the services that were running. It does not change file permissions. Files that are locked or cannot be removed are recorded in the log and skipped.

It then runs Windows Disk Cleanup twice, first elevated and then as the signed-in user. Both runs use Disk Cleanup's default settings without confirmation prompts. Depending on Windows configuration, those defaults may include Recycle Bin contents and other cleanup categories.

## Install At Sign-In

From the project directory, run this once in PowerShell as the signed-in user:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\nightfall-cleanup.ps1 -Install
```

This creates a visible PowerShell shortcut in the current user's Startup folder. At each sign-in, the script requests UAC approval for the administrator phase. If approval is declined, the administrator cleanup is skipped. Disk Cleanup runs after the administrator phase finishes.

To remove the sign-in shortcut, run:

```powershell
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Nightfall Cleanup.lnk')
```

## Run Manually

Run the script without administrator rights so it can start the elevated phase and then run Disk Cleanup as the signed-in user:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\nightfall-cleanup.ps1
```

## Logs

Progress and errors are written to:

```text
%LOCALAPPDATA%\Nightfall\cleanup.log
```

## Notes

- Windows recreates temporary, Prefetch, and Windows Update cache data as needed. Clearing the update cache can reset cached update downloads and may affect the update history displayed by Windows.
- Locked files are expected while applications are running; close applications and rerun the script if you want it to retry them.
- This script is intended for Windows 11 and uses the built-in Windows PowerShell and Disk Cleanup utilities.
