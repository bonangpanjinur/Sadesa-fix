$ErrorActionPreference = 'Stop'
$BridgeDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Startup = [Environment]::GetFolderPath('Startup')
$ShortcutPath = Join-Path $Startup 'SaDesa POS Print Bridge.lnk'
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = 'node'
$Shortcut.Arguments = ('"' + (Join-Path $BridgeDir 'src/server.mjs') + '"')
$Shortcut.WorkingDirectory = $BridgeDir
$Shortcut.WindowStyle = 7
$Shortcut.Save()
Write-Host "Print Bridge auto-start terpasang: $ShortcutPath"
Write-Host "Pastikan data/config.json sudah dikonfigurasi sebelum menjalankan POS."
