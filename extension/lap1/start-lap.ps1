$ErrorActionPreference = 'Stop'
$desktopScript = Join-Path $PSScriptRoot 'lap.ps1'
$webScript = Join-Path $PSScriptRoot 'web.ps1'

Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Normal', '-File', $desktopScript) | Out-Null
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $webScript) | Out-Null
