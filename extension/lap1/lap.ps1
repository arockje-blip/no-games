Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'Lap Guard'
$script:Username = 'AJ_encoded'
$script:Password = '19782004'
$script:AllowedDurations = @(2, 5, 10, 15, 25, 35, 50, 60)
$script:DefaultBlockedDomains = @(
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
$script:StateDir = Join-Path $env:ProgramData 'LapGuard'
$script:StateFile = Join-Path $script:StateDir 'state.json'
$script:HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$script:StartupTaskName = 'LapGuard'
$script:MarkerStart = '# LapGuard-Start'
$script:MarkerEnd = '# LapGuard-End'
$script:IsAuthenticated = $false
$script:BlockedDomains = @()
$script:DisabledUntil = 0
$script:PermanentDisable = $false
$script:ResumeTimer = New-Object System.Windows.Forms.Timer
$script:ResumeTimer.Interval = 5000

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-StateDir {
  if (-not (Test-Path $script:StateDir)) {
    New-Item -ItemType Directory -Path $script:StateDir | Out-Null
  }
}

function Format-Domain {
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
    blockedDomains = $script:DefaultBlockedDomains
    disabledUntil = 0
    permanentDisable = $false
  }
}

function Read-State {
  Test-StateDir

  if (-not (Test-Path $script:StateFile)) {
    return Get-DefaultState
  }

  try {
    $raw = Get-Content -Path $script:StateFile -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
      return Get-DefaultState
    }

    $loaded = $raw | ConvertFrom-Json
    $domains = @()
    if ($null -ne $loaded.blockedDomains) {
      foreach ($item in $loaded.blockedDomains) {
        $normalized = Format-Domain -Domain ([string]$item)
        if ($normalized -and $domains -notcontains $normalized) {
          $domains += $normalized
        }
      }
    }

    if ($domains.Count -eq 0) {
      $domains = @($script:DefaultBlockedDomains)
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

  Test-StateDir

  $payload = [ordered]@{
    blockedDomains = @($BlockedDomains)
    disabledUntil = $DisabledUntil
    permanentDisable = $PermanentDisable
  }

  $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $script:StateFile -Encoding ASCII
}

function Get-HostSectionLines {
  param([string[]]$Domains)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add($script:MarkerStart)
  $lines.Add('# Managed by Lap Guard')
  $lines.Add('# Do not edit between markers manually.')

  foreach ($domain in $Domains) {
    $lines.Add("0.0.0.0 $domain")
    $lines.Add("0.0.0.0 www.$domain")
    $lines.Add("::1 $domain")
    $lines.Add("::1 www.$domain")
  }

  $lines.Add($script:MarkerEnd)
  return $lines.ToArray()
}

function Update-HostsFile {
  param([string[]]$Domains)

  $domains = @()
  foreach ($domain in $Domains) {
    $normalized = Format-Domain -Domain $domain
    if ($normalized -and $domains -notcontains $normalized) {
      $domains += $normalized
    }
  }

  if (-not (Test-Path $script:HostsPath)) {
    throw 'Hosts file not found.'
  }

  $hosts = Get-Content -Path $script:HostsPath -Raw -ErrorAction Stop
  $pattern = '(?ms)^# LapGuard-Start.*?# LapGuard-End\r?\n?'
  $hosts = [regex]::Replace($hosts, $pattern, '')
  if (-not $hosts.EndsWith([Environment]::NewLine)) {
    $hosts += [Environment]::NewLine
  }

  if ($domains.Count -gt 0) {
    $section = [string]::Join([Environment]::NewLine, (Get-HostSectionLines -Domains $domains))
    $hosts += $section + [Environment]::NewLine
  }

  Set-Content -Path $script:HostsPath -Value $hosts -Encoding ASCII
}

function Sync-Protection {
  $state = Read-State
  $script:BlockedDomains = @($state.blockedDomains)
  $script:DisabledUntil = [int64]$state.disabledUntil
  $script:PermanentDisable = [bool]$state.permanentDisable

  if ($script:PermanentDisable) {
    Update-HostsFile -Domains @()
    return
  }

  if ($script:DisabledUntil -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
    Update-HostsFile -Domains @()
  }
  else {
    if ($script:DisabledUntil -ne 0) {
      $script:DisabledUntil = 0
      Write-State -BlockedDomains $script:BlockedDomains -DisabledUntil 0
    }

    Update-HostsFile -Domains $script:BlockedDomains
  }
}

function Get-CurrentStatusText {
  if ($script:DisabledUntil -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
    return 'Paused'
  }

  return 'Active'
}

function Format-Timestamp {
  param([int64]$EpochSeconds)

  if ($EpochSeconds -le 0) {
    return 'Never'
  }

  $local = [DateTimeOffset]::FromUnixTimeSeconds($EpochSeconds).ToLocalTime()
  return $local.ToString('yyyy-MM-dd HH:mm:ss')
}

function Update-UiState {
  $statusLabel.Text = Get-CurrentStatusText
  $domainCountLabel.Text = $script:BlockedDomains.Count.ToString()
  $pausedUntilLabel.Text = Format-Timestamp -EpochSeconds $script:DisabledUntil
  $domainBox.Text = [string]::Join("`r`n", $script:BlockedDomains)
  $unlockStateLabel.Text = if ($script:IsAuthenticated) { 'Unlocked' } else { 'Locked' }
}

function Test-Authentication {
  if (-not $script:IsAuthenticated) {
    [System.Windows.Forms.MessageBox]::Show('Enter the correct username and password first.', $script:AppName, 'OK', 'Warning') | Out-Null
    return $false
  }

  return $true
}

function Stop-Protection {
  param([int]$Minutes)

  if (-not ($script:AllowedDurations -contains $Minutes)) {
    [System.Windows.Forms.MessageBox]::Show('Unsupported duration.', $script:AppName, 'OK', 'Warning') | Out-Null
    return
  }

  $script:DisabledUntil = [DateTimeOffset]::UtcNow.AddMinutes($Minutes).ToUnixTimeSeconds()
  $script:PermanentDisable = $false
  Write-State -BlockedDomains $script:BlockedDomains -DisabledUntil $script:DisabledUntil -PermanentDisable $script:PermanentDisable
  Update-HostsFile -Domains @()
  Update-UiState
}

function Resume-Protection {
  $script:DisabledUntil = 0
  $script:PermanentDisable = $false
  Write-State -BlockedDomains $script:BlockedDomains -DisabledUntil 0 -PermanentDisable $script:PermanentDisable
  Update-HostsFile -Domains $script:BlockedDomains
  Update-UiState
}

function Disable-Protection-Permanently {
  $confirmation = [System.Windows.Forms.MessageBox]::Show(
    'This will disable blocking until you re-enable it. Continue?',
    $script:AppName,
    'YesNo',
    'Warning'
  )

  if ($confirmation -ne 'Yes') {
    return
  }

  $script:DisabledUntil = 0
  $script:PermanentDisable = $true
  Write-State -BlockedDomains $script:BlockedDomains -DisabledUntil 0 -PermanentDisable $true
  Update-HostsFile -Domains @()

  try {
    Unregister-ScheduledTask -TaskName $script:StartupTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
  }
  catch {
  }

  Update-UiState
}

function Enable-Protection {
  $script:PermanentDisable = $false
  Write-State -BlockedDomains $script:BlockedDomains -DisabledUntil 0 -PermanentDisable $false
  Update-HostsFile -Domains $script:BlockedDomains
  Update-UiState
}

function Save-Domains {
  $items = @()
  foreach ($line in ($domainBox.Lines)) {
    $normalized = Format-Domain -Domain $line
    if ($normalized -and $items -notcontains $normalized) {
      $items += $normalized
    }
  }

  if ($items.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show('Add at least one valid domain.', $script:AppName, 'OK', 'Warning') | Out-Null
    return
  }

  $script:BlockedDomains = $items
  Write-State -BlockedDomains $script:BlockedDomains -DisabledUntil $script:DisabledUntil -PermanentDisable $script:PermanentDisable

  if (-not $script:PermanentDisable -and $script:DisabledUntil -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
    Update-HostsFile -Domains $script:BlockedDomains
  }

  Update-UiState
}

function Invoke-Unlock {
  if ($usernameBox.Text -ne $script:Username -or $passwordBox.Text -ne $script:Password) {
    [System.Windows.Forms.MessageBox]::Show('Invalid username or password.', $script:AppName, 'OK', 'Error') | Out-Null
    return
  }

  $script:IsAuthenticated = $true
  Update-UiState
  controlsPanel.Enabled = $true
}

function Invoke-ResumeTick {
  if ($script:PermanentDisable -or $script:DisabledUntil -le 0) {
    return
  }

  if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -ge $script:DisabledUntil) {
    Resume-Protection
  }
}

if (-not (Test-IsAdministrator)) {
  [System.Windows.Forms.MessageBox]::Show('Lap Guard must run as Administrator to edit the hosts file.', $script:AppName, 'OK', 'Warning') | Out-Null
  exit 1
}

Test-StateDir
$initialState = Read-State
$script:BlockedDomains = @($initialState.blockedDomains)
$script:DisabledUntil = [int64]$initialState.disabledUntil
$script:PermanentDisable = [bool]$initialState.permanentDisable

try {
  Sync-Protection
}
catch {
  [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Error') | Out-Null
  exit 1
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppName
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(920, 720)
$form.MinimumSize = New-Object System.Drawing.Size(860, 640)
$form.BackColor = [System.Drawing.Color]::FromArgb(14, 22, 35)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$header = New-Object System.Windows.Forms.Label
$header.Text = 'Lap Guard - system wide block'
$header.AutoSize = $true
$header.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$header.Location = New-Object System.Drawing.Point(20, 18)
$form.Controls.Add($header)

$subheader = New-Object System.Windows.Forms.Label
$subheader.Text = 'Blocks gaming and game download sites across the whole laptop by editing the hosts file.'
$subheader.AutoSize = $true
$subheader.Location = New-Object System.Drawing.Point(20, 56)
$form.Controls.Add($subheader)

$loginGroup = New-Object System.Windows.Forms.GroupBox
$loginGroup.Text = 'Unlock'
$loginGroup.Location = New-Object System.Drawing.Point(20, 92)
$loginGroup.Size = New-Object System.Drawing.Size(380, 170)
$form.Controls.Add($loginGroup)

$usernameLabel = New-Object System.Windows.Forms.Label
$usernameLabel.Text = 'Username'
$usernameLabel.AutoSize = $true
$usernameLabel.Location = New-Object System.Drawing.Point(18, 34)
$loginGroup.Controls.Add($usernameLabel)

$usernameBox = New-Object System.Windows.Forms.TextBox
$usernameBox.Location = New-Object System.Drawing.Point(18, 58)
$usernameBox.Width = 330
$usernameBox.Text = $script:Username
$loginGroup.Controls.Add($usernameBox)

$passwordLabel = New-Object System.Windows.Forms.Label
$passwordLabel.Text = 'Password'
$passwordLabel.AutoSize = $true
$passwordLabel.Location = New-Object System.Drawing.Point(18, 90)
$loginGroup.Controls.Add($passwordLabel)

$passwordBox = New-Object System.Windows.Forms.TextBox
$passwordBox.Location = New-Object System.Drawing.Point(18, 114)
$passwordBox.Width = 330
$passwordBox.UseSystemPasswordChar = $true
$passwordBox.Text = ''
$loginGroup.Controls.Add($passwordBox)

$unlockButton = New-Object System.Windows.Forms.Button
$unlockButton.Text = 'Unlock controls'
$unlockButton.Location = New-Object System.Drawing.Point(240, 140)
$unlockButton.Width = 108
$unlockButton.Add_Click({ Invoke-Unlock })
$loginGroup.Controls.Add($unlockButton)

$unlockStateLabel = New-Object System.Windows.Forms.Label
$unlockStateLabel.Text = 'Locked'
$unlockStateLabel.AutoSize = $true
$unlockStateLabel.Location = New-Object System.Drawing.Point(18, 145)
$loginGroup.Controls.Add($unlockStateLabel)

$controlsPanel = New-Object System.Windows.Forms.GroupBox
$controlsPanel.Text = 'Protection controls'
$controlsPanel.Location = New-Object System.Drawing.Point(20, 280)
$controlsPanel.Size = New-Object System.Drawing.Size(860, 380)
$controlsPanel.Enabled = $false
$form.Controls.Add($controlsPanel)

$statusTitle = New-Object System.Windows.Forms.Label
$statusTitle.Text = 'Status'
$statusTitle.AutoSize = $true
$statusTitle.Location = New-Object System.Drawing.Point(18, 32)
$controlsPanel.Controls.Add($statusTitle)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Active'
$statusLabel.AutoSize = $true
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$statusLabel.Location = New-Object System.Drawing.Point(18, 56)
$controlsPanel.Controls.Add($statusLabel)

$domainCountTitle = New-Object System.Windows.Forms.Label
$domainCountTitle.Text = 'Blocked domains'
$domainCountTitle.AutoSize = $true
$domainCountTitle.Location = New-Object System.Drawing.Point(18, 96)
$controlsPanel.Controls.Add($domainCountTitle)

$domainCountLabel = New-Object System.Windows.Forms.Label
$domainCountLabel.Text = '0'
$domainCountLabel.AutoSize = $true
$domainCountLabel.Location = New-Object System.Drawing.Point(18, 120)
$controlsPanel.Controls.Add($domainCountLabel)

$pausedTitle = New-Object System.Windows.Forms.Label
$pausedTitle.Text = 'Paused until'
$pausedTitle.AutoSize = $true
$pausedTitle.Location = New-Object System.Drawing.Point(18, 150)
$controlsPanel.Controls.Add($pausedTitle)

$pausedUntilLabel = New-Object System.Windows.Forms.Label
$pausedUntilLabel.Text = 'Never'
$pausedUntilLabel.AutoSize = $true
$pausedUntilLabel.Location = New-Object System.Drawing.Point(18, 174)
$controlsPanel.Controls.Add($pausedUntilLabel)

$durationsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$durationsPanel.Location = New-Object System.Drawing.Point(18, 208)
$durationsPanel.Size = New-Object System.Drawing.Size(810, 42)
$durationsPanel.AutoScroll = $true
$controlsPanel.Controls.Add($durationsPanel)

foreach ($minutes in $script:AllowedDurations) {
  $selectedMinutes = [int]$minutes
  $button = New-Object System.Windows.Forms.Button
  $button.Text = "$selectedMinutes min"
  $button.Width = 76
  $button.Add_Click({ Stop-Protection -Minutes $selectedMinutes })
  $button.Tag = $selectedMinutes
  $durationsPanel.Controls.Add($button)
}

$resumeButton = New-Object System.Windows.Forms.Button
$resumeButton.Text = 'Re-enable now'
$resumeButton.Width = 120
$resumeButton.Location = New-Object System.Drawing.Point(18, 264)
$resumeButton.Add_Click({ Resume-Protection })
$controlsPanel.Controls.Add($resumeButton)

$permanentDisableButton = New-Object System.Windows.Forms.Button
$permanentDisableButton.Text = 'Permanent disable'
$permanentDisableButton.Width = 130
$permanentDisableButton.Location = New-Object System.Drawing.Point(416, 264)
$permanentDisableButton.Add_Click({ Disable-Protection-Permanently })
$controlsPanel.Controls.Add($permanentDisableButton)

$enableButton = New-Object System.Windows.Forms.Button
$enableButton.Text = 'Enable protection'
$enableButton.Width = 130
$enableButton.Location = New-Object System.Drawing.Point(560, 264)
$enableButton.Add_Click({ Enable-Protection })
$controlsPanel.Controls.Add($enableButton)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = 'Save domains'
$saveButton.Width = 120
$saveButton.Location = New-Object System.Drawing.Point(152, 264)
$saveButton.Add_Click({ Save-Domains })
$controlsPanel.Controls.Add($saveButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = 'Refresh'
$refreshButton.Width = 120
$refreshButton.Location = New-Object System.Drawing.Point(286, 264)
$refreshButton.Add_Click({
  $current = Read-State
  $script:BlockedDomains = @($current.blockedDomains)
  $script:DisabledUntil = [int64]$current.disabledUntil
  Update-UiState
})
$controlsPanel.Controls.Add($refreshButton)

$domainBoxLabel = New-Object System.Windows.Forms.Label
$domainBoxLabel.Text = 'Domains, one per line'
$domainBoxLabel.AutoSize = $true
$domainBoxLabel.Location = New-Object System.Drawing.Point(18, 306)
$controlsPanel.Controls.Add($domainBoxLabel)

$domainBox = New-Object System.Windows.Forms.TextBox
$domainBox.Multiline = $true
$domainBox.ScrollBars = 'Vertical'
$domainBox.Location = New-Object System.Drawing.Point(18, 330)
$domainBox.Size = New-Object System.Drawing.Size(810, 36)
$domainBox.Text = [string]::Join("`r`n", $script:BlockedDomains)
$controlsPanel.Controls.Add($domainBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = 'Setup tip: run setup-startup.ps1 once as Administrator to register auto start and the local disable page.'
$footer.AutoSize = $true
$footer.Location = New-Object System.Drawing.Point(20, 672)
$form.Controls.Add($footer)

$script:ResumeTimer.Add_Tick({ Invoke-ResumeTick })
$script:ResumeTimer.Start()

Update-UiState
[void]$form.ShowDialog()
