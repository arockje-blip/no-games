param(
  [int]$Port = 17820
)

$ErrorActionPreference = 'Stop'
$AppName = 'Lap Guard Web'
$Username = 'AJ_encoded'
$Password = '19782004'
$StateDir = Join-Path $env:ProgramData 'LapGuard'
$StateFile = Join-Path $StateDir 'state.json'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$StartupTaskName = 'LapGuard'
$script:Authenticated = $false
$DefaultBlockedDomains = @(
  'roblox.com',
  'rbxcdn.com',
  'epicgames.com',
  'store.epicgames.com',
  'steamcommunity.com',
  'store.steampowered.com',
  'steampowered.com',
  'battle.net',
  'blizzard.com',
  'riotgames.com',
  'playvalorant.com',
  'ea.com',
  'origin.com',
  'ubisoft.com',
  'ubisoftconnect.com',
  'nintendo.com',
  'playstation.com',
  'xbox.com',
  'minecraft.net',
  'mojang.com',
  'gog.com',
  'itch.io',
  'crazygames.com',
  'poki.com',
  'miniclip.com',
  'friv.com',
  'kongregate.com',
  'armorgames.com',
  'newgrounds.com',
  'mediafire.com',
  'mega.nz',
  'uptodown.com',
  'softonic.com',
  'filehippo.com',
  'sourceforge.net',
  'download.cnet.com',
  'apkcombo.com',
  'apkpure.com',
  'filehorse.com',
  'getintopc.com',
  'steamunlocked.net',
  'fitgirl-repacks.site'
)

function Ensure-StateDir {
  if (-not (Test-Path $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir | Out-Null
  }
}

function Normalize-Domain {
  param([string]$Domain)

  if ([string]::IsNullOrWhiteSpace($Domain)) {
    return $null
  }

  $value = $Domain.Trim().ToLowerInvariant()
  $value = $value -replace '^https?://', ''
  $value = $value -replace '^\*\.', ''
  $value = $value.Split(@('/', '?', '#'))[0]
  $value = $value.Trim('.')

  if ($value -notmatch '^[a-z0-9.-]+$' -or $value -notmatch '\.') {
    return $null
  }

  return $value
}

function Get-DefaultState {
  return [ordered]@{
    blockedDomains = $DefaultBlockedDomains
    disabledUntil = 0
    permanentDisable = $false
  }
}

function Read-State {
  Ensure-StateDir
  if (-not (Test-Path $StateFile)) {
    return Get-DefaultState
  }

  try {
    $raw = Get-Content -Path $StateFile -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
      return Get-DefaultState
    }

    $loaded = $raw | ConvertFrom-Json
    $domains = @()
    if ($null -ne $loaded.blockedDomains) {
      foreach ($item in $loaded.blockedDomains) {
        $normalized = Normalize-Domain -Domain ([string]$item)
        if ($normalized -and $domains -notcontains $normalized) {
          $domains += $normalized
        }
      }
    }

    if ($domains.Count -eq 0) {
      $domains = @($DefaultBlockedDomains)
    }

    return [ordered]@{
      blockedDomains = $domains
      disabledUntil = [int64]($loaded.disabledUntil | ForEach-Object { $_ })
      permanentDisable = [bool]($loaded.permanentDisable | ForEach-Object { $_ })
    }
  }
  catch {
    return Get-DefaultState
  }
}

function Write-State {
  param(
    [string[]]$BlockedDomains,
    [int64]$DisabledUntil,
    [bool]$PermanentDisable = $false
  )

  Ensure-StateDir
  $payload = [ordered]@{
    blockedDomains = @($BlockedDomains)
    disabledUntil = $DisabledUntil
    permanentDisable = $PermanentDisable
  }

  $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $StateFile -Encoding ASCII
}

function Update-HostsFile {
  param([string[]]$Domains)

  $domains = @()
  foreach ($domain in $Domains) {
    $normalized = Normalize-Domain -Domain $domain
    if ($normalized -and $domains -notcontains $normalized) {
      $domains += $normalized
    }
  }

  $pattern = '(?ms)^# LapGuard-Start.*?# LapGuard-End\r?\n?'
  $hosts = Get-Content -Path $HostsPath -Raw -ErrorAction Stop
  $hosts = [regex]::Replace($hosts, $pattern, '')
  if (-not $hosts.EndsWith([Environment]::NewLine)) {
    $hosts += [Environment]::NewLine
  }

  if ($domains.Count -gt 0) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# LapGuard-Start')
    $lines.Add('# Managed by Lap Guard web dashboard')
    $lines.Add('# Do not edit between markers manually.')
    foreach ($domain in $domains) {
      $lines.Add("0.0.0.0 $domain")
      $lines.Add("0.0.0.0 www.$domain")
      $lines.Add("::1 $domain")
      $lines.Add("::1 www.$domain")
    }
    $lines.Add('# LapGuard-End')
    $hosts += [string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine
  }

  Set-Content -Path $HostsPath -Value $hosts -Encoding ASCII
}

function Sync-Protection {
  $state = Read-State
  if ($state.permanentDisable) {
    Update-HostsFile -Domains @()
    return $state
  }

  if ([int64]$state.disabledUntil -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
    Update-HostsFile -Domains @()
    return $state
  }

  if ([int64]$state.disabledUntil -ne 0) {
    $state.disabledUntil = 0
    Write-State -BlockedDomains $state.blockedDomains -DisabledUntil 0 -PermanentDisable $false
  }

  Update-HostsFile -Domains $state.blockedDomains
  return $state
}

function Test-Credentials {
  param([string]$UserName, [string]$UserPassword)
  return ($UserName -eq $Username -and $UserPassword -eq $Password)
}

function Parse-RequestBody {
  param($Context)

  $reader = New-Object System.IO.StreamReader($Context.Request.InputStream, $Context.Request.ContentEncoding)
  $raw = $reader.ReadToEnd()
  $reader.Close()

  if ([string]::IsNullOrWhiteSpace($raw)) {
    return @{}
  }

  return $raw | ConvertFrom-Json
}

function Send-Json {
  param($Context, [hashtable]$Body, [int]$StatusCode = 200)

  $json = $Body | ConvertTo-Json -Depth 10
  $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = 'application/json; charset=utf-8'
  $Context.Response.ContentLength64 = $buffer.Length
  $Context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
  $Context.Response.OutputStream.Close()
}

function Send-Html {
  param($Context, [string]$Html)

  $buffer = [System.Text.Encoding]::UTF8.GetBytes($Html)
  $Context.Response.ContentType = 'text/html; charset=utf-8'
  $Context.Response.ContentLength64 = $buffer.Length
  $Context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
  $Context.Response.OutputStream.Close()
}

function Remove-StartupTask {
  try {
    Unregister-ScheduledTask -TaskName $StartupTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
  }
  catch {
  }
}

function Handle-Action {
  param($Context, [string]$Action, [hashtable]$Payload)

  $state = Sync-Protection
  $user = [string]$Payload.username
  $pass = [string]$Payload.password

  if ($Action -ne 'state' -and -not (Test-Credentials -UserName $user -UserPassword $pass)) {
    Send-Json -Context $Context -Body @{ ok = $false; error = 'Invalid username or password' }
    return
  }

  switch ($Action) {
    'state' {
      Send-Json -Context $Context -Body @{
        ok = $true
        authenticated = $script:Authenticated
        blockedDomains = $state.blockedDomains
        disabledUntil = $state.disabledUntil
        paused = ($state.permanentDisable -or ([int64]$state.disabledUntil -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()))
        permanentDisable = [bool]$state.permanentDisable
      }
    }
    'auth' {
      $script:Authenticated = $true
      Send-Json -Context $Context -Body @{
        ok = $true
        authenticated = $true
        blockedDomains = $state.blockedDomains
        disabledUntil = $state.disabledUntil
        paused = ($state.permanentDisable -or ([int64]$state.disabledUntil -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()))
        permanentDisable = [bool]$state.permanentDisable
      }
    }
    'pause' {
      $minutes = [int]$Payload.minutes
      if ($minutes -notin @(2, 5, 10, 15, 25, 35, 50, 60)) {
        Send-Json -Context $Context -Body @{ ok = $false; error = 'Unsupported duration' }
        return
      }

      $state.disabledUntil = [DateTimeOffset]::UtcNow.AddMinutes($minutes).ToUnixTimeSeconds()
      $state.permanentDisable = $false
      Write-State -BlockedDomains $state.blockedDomains -DisabledUntil $state.disabledUntil -PermanentDisable $false
      Update-HostsFile -Domains @()
      Send-Json -Context $Context -Body @{ ok = $true }
    }
    'resume' {
      $script:Authenticated = $true
      $state.disabledUntil = 0
      $state.permanentDisable = $false
      Write-State -BlockedDomains $state.blockedDomains -DisabledUntil 0 -PermanentDisable $false
      Update-HostsFile -Domains $state.blockedDomains
      Send-Json -Context $Context -Body @{ ok = $true }
    }
    'permanent-disable' {
      $script:Authenticated = $true
      $state.disabledUntil = 0
      $state.permanentDisable = $true
      Write-State -BlockedDomains $state.blockedDomains -DisabledUntil 0 -PermanentDisable $true
      Update-HostsFile -Domains @()
      Remove-StartupTask
      Send-Json -Context $Context -Body @{ ok = $true }
    }
    'enable' {
      $script:Authenticated = $true
      $state.disabledUntil = 0
      $state.permanentDisable = $false
      Write-State -BlockedDomains $state.blockedDomains -DisabledUntil 0 -PermanentDisable $false
      Update-HostsFile -Domains $state.blockedDomains
      Send-Json -Context $Context -Body @{ ok = $true }
    }
    'domains' {
      $script:Authenticated = $true
      $blockedDomains = @()
      foreach ($line in ([string]$Payload.blockedDomains -split "`r?`n")) {
        $normalized = Normalize-Domain -Domain $line
        if ($normalized -and $blockedDomains -notcontains $normalized) {
          $blockedDomains += $normalized
        }
      }

      if ($blockedDomains.Count -eq 0) {
        Send-Json -Context $Context -Body @{ ok = $false; error = 'Add at least one valid domain' }
        return
      }

      $state.blockedDomains = $blockedDomains
      Write-State -BlockedDomains $blockedDomains -DisabledUntil $state.disabledUntil -PermanentDisable $state.permanentDisable
      if (-not $state.permanentDisable -and [int64]$state.disabledUntil -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
        Update-HostsFile -Domains $blockedDomains
      }
      Send-Json -Context $Context -Body @{ ok = $true }
    }
  }
}

if (-not (Test-Path $HostsPath)) {
  throw 'Hosts file not found.'
}

try {
  Sync-Protection | Out-Null
}
catch {
  throw
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "Lap Guard web dashboard running at $prefix"

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $path = $context.Request.Url.AbsolutePath.TrimEnd('/')

  try {
    if ($context.Request.HttpMethod -eq 'GET' -and ($path -eq '' -or $path -eq '/index.html')) {
      $html = Get-Content -Path (Join-Path $PSScriptRoot 'web\index.html') -Raw -Encoding UTF8
      Send-Html -Context $context -Html $html
      continue
    }

    if ($context.Request.HttpMethod -eq 'GET' -and $path -eq '/api/state') {
      $state = Sync-Protection
      Send-Json -Context $context -Body @{
        ok = $true
        authenticated = $script:Authenticated
        blockedDomains = $state.blockedDomains
        disabledUntil = $state.disabledUntil
        paused = ($state.permanentDisable -or ([int64]$state.disabledUntil -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()))
        permanentDisable = [bool]$state.permanentDisable
      }
      continue
    }

    if ($context.Request.HttpMethod -eq 'POST' -and $path -like '/api/*') {
      $payload = Parse-RequestBody -Context $context
      switch ($path) {
        '/api/auth' { Handle-Action -Context $context -Action 'auth' -Payload $payload }
        '/api/pause' { Handle-Action -Context $context -Action 'pause' -Payload $payload }
        '/api/resume' { Handle-Action -Context $context -Action 'resume' -Payload $payload }
        '/api/permanent-disable' { Handle-Action -Context $context -Action 'permanent-disable' -Payload $payload }
        '/api/enable' { Handle-Action -Context $context -Action 'enable' -Payload $payload }
        '/api/domains' { Handle-Action -Context $context -Action 'domains' -Payload $payload }
        default { Send-Json -Context $context -Body @{ ok = $false; error = 'Unknown endpoint' } -StatusCode 404 }
      }
      continue
    }

    Send-Json -Context $context -Body @{ ok = $false; error = 'Not found' } -StatusCode 404
  }
  catch {
    try {
      Send-Json -Context $context -Body @{ ok = $false; error = $_.Exception.Message } -StatusCode 500
    }
    catch {
    }
  }
}
