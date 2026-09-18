$ErrorActionPreference = 'Stop'
$BridgeDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ConfigPath = Join-Path $BridgeDir 'data/config.json'
$ConfigExample = Join-Path $BridgeDir 'data/config.example.json'
$Startup = [Environment]::GetFolderPath('Startup')
$ShortcutPath = Join-Path $Startup 'SaDesa POS Print Bridge.lnk'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js 22 atau yang lebih baru belum terpasang. Instal dari https://nodejs.org/ lalu jalankan script ini lagi.'
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw 'npm tidak ditemukan. Pastikan instalasi Node.js menambahkan npm ke PATH.'
}

New-Item -ItemType Directory -Force -Path (Join-Path $BridgeDir 'data') | Out-Null
if (-not (Test-Path $ConfigPath)) {
  Copy-Item $ConfigExample $ConfigPath
  Write-Host "Konfigurasi awal dibuat: $ConfigPath"
  Write-Host 'Edit host/port/path dan tandai satu printer dengan isDefault=true sebelum mencetak.'
}

Push-Location $BridgeDir
try {
  npm install --omit=dev
} finally {
  Pop-Location
}

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = (Get-Command node).Source
$Shortcut.Arguments = ('"' + (Join-Path $BridgeDir 'src/server.mjs') + '"')
$Shortcut.WorkingDirectory = $BridgeDir
$Shortcut.WindowStyle = 7
$Shortcut.Save()

Write-Host ''
Write-Host "Print Bridge auto-start terpasang: $ShortcutPath"
Write-Host 'Jalankan service sekarang dengan: npm --prefix print-bridge start'
Write-Host 'Lalu buka POS > Pengaturan > Printer dan lakukan Test Print.'
