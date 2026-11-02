# FTECU Standalone

FTECU is motorcycle ECU tuning software for viewing and editing fuel maps, ignition maps and other engine-control settings. FTM files contain tuning data and settings for supported motorcycles.

This standalone package keeps the original FTECU interface and includes 1,053 local FTM files. Browse, open, edit, save and reopen files without an FTECU installation, account or internet connection. It is an offline file editor; ECU flashing is not included. The complete package is approximately 1.05 GB.

## Run

Requires Windows and the [.NET Framework 4.8 runtime](https://dotnet.microsoft.com/en-us/download/dotnet-framework/net48), or a compatible newer .NET Framework runtime.

Download using [Git LFS](https://git-lfs.com/) so the executable and library files are included:

```powershell
git lfs install
git -c core.longpaths=true clone https://github.com/terrafirma2021/ftecu-unlocked.git
cd ftecu-unlocked
git lfs pull
& '.\FTECU Tuning Suite.exe'
```

No application installer is needed. Keep the EXE, DLL, configuration and `data` folder together in a writable folder. Save edited files separately from the bundled originals.

## Windows Sandbox

Tested successfully in [Windows Sandbox](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/) with networking disabled and no original FTECU installation. Copy the complete package into a writable folder inside the sandbox. Export saved files and their keys before closing it; sandbox storage is temporary.

## Limitations

ECU flashing is not included. It requires a compatible FTDI interface and harness, ECU-specific programming code/loaders (the flashing bytes), integration and hardware testing. The separately extracted flashing components are not bundled; connecting an FTDI cable alone does not enable Read/Write ECU.

Live View Data, ActiveTune and Diagnostics are not enabled. Some model-specific editing modules remain unsupported.

## Saved-file keys

Bundled files include their offline keys. New saved-file keys are stored in `local-data` and protected by your Windows account. Use `Backup-OfflineKeys.ps1` with [PowerShell 7.2 or later](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows) to export or restore a password-protected backup:

```powershell
pwsh -File .\Backup-OfflineKeys.ps1 -Mode Export -BackupFile D:\ftecu-keys.backup
pwsh -File .\Backup-OfflineKeys.ps1 -Mode Restore -BackupFile D:\ftecu-keys.backup
```

Keep this backup with your saved FTMs when moving to another computer or Windows account.
