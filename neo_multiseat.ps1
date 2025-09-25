function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "[neo_multiseat] Not elevated. Relaunching as Administrator..." -ForegroundColor Yellow
    $thisScript = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if (-not $thisScript) {
      Write-Host "Cannot determine script path for elevation. Please run this script from a file." -ForegroundColor Red
      Read-Host "Press ENTER to close"
      exit 1
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$thisScript`""
    $psi.Verb      = "runas"
    try { [Diagnostics.Process]::Start($psi) | Out-Null } catch {
      Write-Host "Elevation was cancelled." -ForegroundColor Red
      Read-Host "Press ENTER to close"
    }
    exit
  }
}
Ensure-Admin

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

# --- Logging ----------------------------------------------------------
$script:LogDir  = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null }
$script:LogFile = Join-Path $LogDir ("neo_multiseat_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Force | Out-Null
# Rotate: keep last 25 logs
try {
  Get-ChildItem -Path $script:LogDir -Filter 'neo_multiseat_*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 25 |
    Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}
$host.UI.RawUI.WindowTitle = "neo_multiseat - $(Get-Date -Format 'HH:mm:ss') - logging to $LogFile"
Write-Host "Logging to $LogFile`n"

# Keep window open and show full errors
trap {
  Write-Host "`n==================== UNHANDLED ERROR ====================" -ForegroundColor Red
  Write-Host ("Message: " + $_.Exception.Message) -ForegroundColor Red
  if ($_.InvocationInfo) {
    Write-Host "`nLocation:" -ForegroundColor DarkYellow
    Write-Host ($_.InvocationInfo.PositionMessage)
  }
  Write-Host "`nDetails:" -ForegroundColor DarkYellow
  $_ | Out-String | Write-Host
  Write-Host "=========================================================`n" -ForegroundColor Red
  Read-Host "Press ENTER to return to menu"
  continue
}

# --- Download locations (your mirrors) --------------------------------
$DL = @{
  RDPWrapZip = 'https://github.com/neo0oen619/neo_multiseat_rdpwrap_backup/releases/download/backup/RDPWrap-v1.6.2.1.zip'
  AutoZip    = 'https://github.com/neo0oen619/neo_multiseat_rdpwrap_backup/raw/refs/heads/master/autoupdate_v1.2.zip'
  FreeRdpZip = 'https://github.com/FreeRDP/FreeRDP/releases/download/3.5.0/FreeRDP-3.5.0-x64.zip'
  FreeRdpHash = 'https://github.com/FreeRDP/FreeRDP/releases/download/3.5.0/FreeRDP-3.5.0-x64.zip.sha256'
}

# --- Paths / constants -------------------------------------------------
$ConfigPath = Join-Path $PSScriptRoot 'neo_multiseat.net.json'
$RuleLAN    = 'neo_multiseat_RDP_LAN'
$RuleWAN    = 'neo_multiseat_RDP_WAN'
$RuleTS     = 'neo_multiseat_RDP_Tailscale'
$RuleTSBlock= 'neo_multiseat_RDP_Block_Tailscale'
$RuleBlockAll='neo_multiseat_RDP_Block_All'
$RdpKey     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

# Consent mode (null = not chosen yet; 'Auto' runs without prompts; 'Manual' confirms)
$script:ConsentMode = $null

# --- Visual helpers (credits + banners) --------------------------------
$script:Esc = [char]27

function Show-ImportantBanner {
  param([string]$Text, [ConsoleColor]$Fg='Black', [ConsoleColor]$Bg='Yellow')
  $line = ('=' * 72)
  Write-Host $line -ForegroundColor $Fg -BackgroundColor $Bg
  $boldStart = "$Esc[1m"; $boldEnd = "$Esc[22m"
  Write-Host ("{0}{1}{2}" -f $boldStart, ("  " + $Text), $boldEnd) -ForegroundColor $Fg -BackgroundColor $Bg
  Write-Host $line -ForegroundColor $Fg -BackgroundColor $Bg
}

# 3-line deep-purple gradient that sweeps left->right; ANSI-safe fallback
function Show-MakerBannerAnimated {
  param(
    [string]$Text = "made with <3 by neo0oen",
    [int]$Lines = 3,
    [int]$DurationMs = 1200,
    [int]$FrameMs = 80
  )
  $esc = $script:Esc
  $useAnsi = $true
  try { $null = "$esc[0m" } catch { $useAnsi = $false }

  if (-not $useAnsi) {
    for ($i=0; $i -lt $Lines; $i++) { Write-Host ("  " + $Text) -ForegroundColor DarkMagenta }
    return
  }

  # Deep purple palette (no pink)
  $palette = @(
    @{r=110; g=0;  b=150},
    @{r=125; g=0;  b=170},
    @{r=140; g=0;  b=185},
    @{r=160; g=10; b=200},
    @{r=175; g=12; b=210},
    @{r=160; g=10; b=200},
    @{r=140; g=0;  b=185},
    @{r=125; g=0;  b=170}
  )
  $seg = $palette.Count

  $chars = $Text.ToCharArray()
  $n = $chars.Count
  if ($n -lt 1) { $n = 1 }

  for ($ln=0; $ln -lt $Lines; $ln++) { Write-Host ("  " + $Text) }
  $hide = "$esc[?25l"; $show = "$esc[?25h"
  Write-Host $hide -NoNewline

  $frames = [Math]::Max(1, [int]($DurationMs / $FrameMs))
  try {
    for ($f=0; $f -lt $frames; $f++) {
      Write-Host ("$esc[{0}A" -f $Lines) -NoNewline
      for ($ln=0; $ln -lt $Lines; $ln++) {
        $phase = ($f * 2) + ($ln * 3)
        $out = "  "
        for ($i=0; $i -lt $n; $i++) {
          $idx = ($i + $phase) % $seg
          $c = $palette[$idx]
          $r = $c.r; $g = $c.g; $b = $c.b
          $ch = $chars[$i]
          $out += ("$esc[1m$esc[38;2;{0};{1};{2}m{3}$esc[0m" -f $r,$g,$b,$ch)
        }
        Write-Host "$esc[2K$out"
      }
      Start-Sleep -Milliseconds $FrameMs
    }
  } finally {
    Write-Host "$esc[0m$show" -NoNewline
    Write-Host ""
  }
}

function Show-CreditLinks {
  $rows = @(
    @{ Label = "Original (Stas'M RDP Wrapper)"; Url = "https://github.com/stascorp/rdpwrap" },
    @{ Label = "Autoupdate (asmtron)";          Url = "https://github.com/asmtron/rdpwrap"  },
    @{ Label = "Mirror (core ZIP)";             Url = $DL.RDPWrapZip                         },
    @{ Label = "Mirror (autoupdate v1.2)";      Url = $DL.AutoZip                            }
  )
  $indent = 2
  foreach ($r in $rows) {
    Write-Host ((" " * $indent) + $r.Label) -ForegroundColor Yellow
    Write-Host ((" " * ($indent + 2)) + $r.Url) -ForegroundColor Yellow
    Write-Host ""
  }
}

function Show-Credits {
  param([switch]$Intro)
  $line = ('=' * 72)
  Write-Host ""
  Write-Host $line -ForegroundColor White -BackgroundColor DarkBlue
  Show-MakerBannerAnimated -Text "made with <3 by neo0oen" -Lines 3 -DurationMs 1200 -FrameMs 80
  Show-CreditLinks
  Write-Host $line -ForegroundColor White -BackgroundColor DarkBlue
  if ($Intro) { Write-Host "" }
}

# Show credits at START
Show-Credits -Intro

# --- Consent helpers ---------------------------------------------------
function Choose-ConsentMode {
  if ($script:ConsentMode) { return }
  Write-Host ""
  Write-Host "Consent mode for system changes:" -ForegroundColor Cyan
  Write-Host "  [A] Apply automatically (no confirmations during this session)"
  Write-Host "  [M] Manual: show steps, confirm each change"
  do {
    $m = Read-Host "Choose A or M"
    if ($m -match '^(?i)A$') { $script:ConsentMode = 'Auto'; break }
    if ($m -match '^(?i)M$') { $script:ConsentMode = 'Manual'; break }
  } while ($true)
}

function Confirm-Apply {
  param(
    [string]$Title,
    [string[]]$PreviewLines,
    [string]$ManualGui = "",
    [string[]]$ManualCli = @(),
    [scriptblock]$Action
  )
  Choose-ConsentMode
  if ($script:ConsentMode -eq 'Auto') {
    & $Action
    return
  }
  Write-Host ""
  Show-ImportantBanner -Text $Title -Fg Black -Bg Yellow
  foreach ($l in $PreviewLines) { Write-Host "  $l" -ForegroundColor DarkYellow }
  Write-Host ""
  Write-Host "[A] Apply automatically   [M] Show manual steps   [C] Cancel" -ForegroundColor Cyan
  do {
    $ans = Read-Host "Choose A / M / C"
    if ($ans -match '^(?i)A$') { & $Action; return }
    if ($ans -match '^(?i)M$') {
      if ($ManualGui) {
        Write-Host "`nGUI path:" -ForegroundColor Yellow
        Write-Host ("  " + $ManualGui)
      }
      if ($ManualCli.Count) {
        Write-Host "`nCLI commands:" -ForegroundColor Yellow
        $ManualCli | ForEach-Object { Write-Host ("  " + $_) }
      }
      Read-Host "`nPerform the manual steps above, then press ENTER to continue"
      return
    }
    if ($ans -match '^(?i)C$') { Write-Host "Cancelled." -ForegroundColor DarkGray; return }
  } while ($true)
}

# --- FAST auth counters (24h, capped, FilterXml) -----------------------
function Get-AuthCounts {
  param([int]$Hours = 24, [int]$Cap = 200)
  $ok = 0; $fail = 0
  try {
    $ms = [int][Math]::Round([TimeSpan]::FromHours([Math]::Abs($Hours)).TotalMilliseconds)
    $q4624 = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4624) and TimeCreated[timediff(@SystemTime) &lt;= $ms]]]
      [EventData[Data[@Name='LogonType']='10']]
    </Select>
  </Query>
</QueryList>
"@
    $ok = @(Get-WinEvent -FilterXml $q4624 -MaxEvents $Cap -ErrorAction SilentlyContinue).Count

    $q4625 = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4625) and TimeCreated[timediff(@SystemTime) &lt;= $ms]]]
    </Select>
  </Query>
</QueryList>
"@
    $fail = @(Get-WinEvent -FilterXml $q4625 -MaxEvents $Cap -ErrorAction SilentlyContinue).Count
  } catch {}
  [PSCustomObject]@{ OK=$ok; FAIL=$fail }
}

# --- Health summary ----------------------------------------------------
function Get-HealthSummary {
  # Service + port
  $svc = Get-Service TermService -ErrorAction SilentlyContinue
  $svcStatus = if ($svc -and $svc.Status -eq 'Running') { 'Running' } else { 'Stopped' }
  $port = 3389
  try {
    $pn = (Get-ItemProperty -Path $RdpKey -Name PortNumber -ErrorAction SilentlyContinue).PortNumber
    if ($pn) { $port = [int]$pn }
  } catch {}

  # Robust wrapper detection (STRICT)
  $wrapDir = "${env:ProgramFiles}\RDP Wrapper"
  $f_RDPWInst = Test-Path (Join-Path $wrapDir 'RDPWInst.exe')
  $f_RDPConf  = Test-Path (Join-Path $wrapDir 'RDPConf.exe')
  $f_RDPCheck = Test-Path (Join-Path $wrapDir 'RDPCheck.exe')
  $f_DLL      = Test-Path (Join-Path $wrapDir 'rdpwrap.dll')
  $f_INI      = Test-Path (Join-Path $wrapDir 'rdpwrap.ini')
  $f_AUTO     = Test-Path (Join-Path $wrapDir 'autoupdate.bat')

  $wrapperCoreOk = ($f_RDPWInst -and $f_RDPConf -and $f_RDPCheck)
  $wrapperCfgOk  = ($f_DLL -and $f_INI)
  $autoOk        = $f_AUTO

  $wrapperStatus = if ($wrapperCoreOk -and $wrapperCfgOk -and $autoOk) {
    'OK'
  } elseif ($wrapperCoreOk -or $wrapperCfgOk -or $autoOk) {
    'Partial'
  } else {
    'Missing'
  }
  $iniStatus = $(if ($f_INI) { 'Present' } else { 'Missing' })

  # NLA / TLS
  $nla = (Get-ItemProperty -Path $RdpKey -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
  $nlaEnabled = if ($nla -eq 1) { 'On' } else { 'Off' }
  $secLayer = (Get-ItemProperty -Path $RdpKey -Name SecurityLayer -ErrorAction SilentlyContinue).SecurityLayer
  $tlsStr = switch ($secLayer) { 2 {'TLS'} 1 {'Negotiate'} 0 {'RDP'} default {'Unknown'} }

  # Firewall rules
  $lanRule  = Get-NetFirewallRule -DisplayName $RuleLAN -ErrorAction SilentlyContinue
  $wanRule  = Get-NetFirewallRule -DisplayName $RuleWAN -ErrorAction SilentlyContinue
  $tsRule   = Get-NetFirewallRule -DisplayName $RuleTS  -ErrorAction SilentlyContinue

  $auth = Get-AuthCounts -Hours 24 -Cap 200

  [PSCustomObject]@{
    TermService = $svcStatus
    Port        = $port
    Wrapper     = $wrapperStatus
    INI         = $iniStatus
    LANRule     = $lanRule
    WANRule     = $wanRule
    TSRule      = $tsRule
    NLA         = $nlaEnabled
    TLSMode     = $tlsStr
    OK          = $auth.OK
    FAIL        = $auth.FAIL
  }
}

function Get-TailscaleStatus {
  $adapter = Get-NetAdapter -Name "Tailscale*" -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
  $has100 = $false
  if ($adapter) {
    $ip = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.IPAddress -like '100.*' } | Select-Object -First 1
    $has100 = [bool]$ip
  }
  [PSCustomObject]@{
    Adapter = $adapter
    Has100  = $has100
  }
}

function Show-HealthStrip {
  $h = Get-HealthSummary

  $lanEnabled = $false; if ($h.LANRule) { $lanEnabled = ($h.LANRule.Enabled -eq 'True') }
  $wanEnabled = $false; if ($h.WANRule) { $wanEnabled = ($h.WANRule.Enabled -eq 'True') }
  $tsEnabled  = $false; if ($h.TSRule)  { $tsEnabled  = ($h.TSRule.Enabled  -eq 'True') }

  $lanLabel = if ($lanEnabled) { 'On (working)' } else { 'Off (disconnected)' }
  $wanLabel = if ($wanEnabled) { 'On (working)' } else { 'Off (disconnected)' }

  $ts = Get-TailscaleStatus
  $tsWorking = $tsEnabled -and $ts.Adapter -and $ts.Has100
  $tsLabel = if ($tsEnabled) { if ($tsWorking) { 'On (working)' } else { 'On (disconnected)' } } else { 'Off (disconnected)' }

  # Color map per item (Green good, Yellow attention, Red problem)
  $svcColor = if ($h.TermService -eq 'Running') { 'Green' } else { 'Red' }
  # Wrapper: Partial is a problem (Red), OK is Green
  $wrapColor = switch ($h.Wrapper) { 'OK' { 'Green' } 'Partial' { 'Red' } default { 'Red' } }
  $iniColor  = if ($h.INI -eq 'Present') { 'Green' } else { 'Red' }
  $nlaColor  = if ($h.NLA -eq 'On') { 'Green' } else { 'Yellow' }
  $tlsColor  = switch ($h.TLSMode) { 'TLS' { 'Green' } 'Negotiate' { 'Yellow' } 'RDP' { 'Red' } default { 'Yellow' } }
  $lanColor  = if ($lanLabel -eq 'On (working)') { 'Green' } else { 'Yellow' }
  # WAN: Off (disconnected) is desired (Green). On (enabled) is risky (Red).
  $wanColor  = if ($wanEnabled) { 'Red' } else { 'Green' }
  $tsColor   = if ($tsLabel  -eq 'On (working)') { 'Green' } else { 'Yellow' }
  # Fail logons: any non-zero is Red to draw attention
  $failColor = if ($h.FAIL -gt 0) { 'Red' } else { 'Green' }

  Write-Host ""
  Write-Host 'STATUS  ' -NoNewline
  $print = {
    param($label,$value,$color)
    $txt = ("{0}:{1}  " -f $label,$value)
    if ($color) { Write-Host $txt -ForegroundColor $color -NoNewline } else { Write-Host $txt -NoNewline }
  }
  & $print 'TermService' $h.TermService $svcColor
  & $print 'Port'        $h.Port       $null
  & $print 'Wrapper'     $h.Wrapper    $wrapColor
  & $print 'INI'         $h.INI        $iniColor
  & $print 'NLA'         $h.NLA        $nlaColor
  & $print 'TLS'         $h.TLSMode    $tlsColor
  & $print 'LAN'         $lanLabel     $lanColor
  & $print 'WAN'         $wanLabel     $wanColor
  & $print 'TS'          $tsLabel      $tsColor
  & $print 'Auth OK'     $h.OK         'Green'
  & $print 'FAIL'        $h.FAIL       $failColor
  Write-Host '(~24h)'
}

# --- RDP file helper (exact username filename) ------------------------
function New-NeoRdpFile {
  param([Parameter(Mandatory=$true)][string]$TargetUser)
  $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
         Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
         Select-Object -ExpandProperty IPAddress
  $primary = if ($ips) { $ips | Select-Object -First 1 } else { $env:COMPUTERNAME }
  $port = Get-RdpPort

  $rdpLines = @(
    ("full address:s:{0}" -f $primary),
    ("username:s:{0}" -f $TargetUser),
    "prompt for credentials:i:1",
    "screen mode id:i:2",
    "authentication level:i:2",
    "compression:i:1"
  )
  $content = ($rdpLines -join "`r`n") + "`r`n"

  $fileName = "$TargetUser.rdp"
  $outScript = Join-Path $PSScriptRoot $fileName
  $outPublic = Join-Path $env:Public ("Desktop\" + $fileName)

  try {
    $ascii = [System.Text.Encoding]::ASCII
    [System.IO.File]::WriteAllText($outScript, $content, $ascii)
    [System.IO.File]::WriteAllText($outPublic, $content, $ascii)
    Write-Host "Created RDP file(s):" -ForegroundColor Green
    Write-Host "  $outScript"
    Write-Host "  $outPublic"
  } catch {
    Write-Warning "Could not write .RDP file(s): $($_.Exception.Message)"
  }

  try {
    $clientExe = Ensure-FreeRdpClient
    if ($clientExe) {
      New-FreeRdpLauncher -TargetUser $TargetUser -Host $primary -Port $port -ClientExe $clientExe
    }
  } catch {
    Write-Warning "FreeRDP launcher generation failed: $($_.Exception.Message)"
  }
}

function Ensure-FreeRdpClient {
  $version = '3.5.0'
  $clientRoot = Join-Path $PSScriptRoot 'clients'
  $versionDir = Join-Path $clientRoot ("FreeRDP-$version")

  $existing = Get-ChildItem -Path $versionDir -Filter 'wfreerdp.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($existing) { return $existing.FullName }

  if (-not (Test-Path $versionDir)) { New-Item -ItemType Directory -Path $versionDir -Force | Out-Null }

  $zipPath = Join-Path $env:TEMP ("FreeRDP_{0}_{1}.zip" -f $version, [Guid]::NewGuid().ToString('N'))
  $hashPath = "$zipPath.sha256"

  if (-not (Get-WebFile -Uri $DL.FreeRdpZip -OutFile $zipPath)) { throw "Could not download FreeRDP zip." }

  if ($DL.FreeRdpHash) {
    if (-not (Get-WebFile -Uri $DL.FreeRdpHash -OutFile $hashPath)) { throw "Could not download FreeRDP hash." }
    $expected = (Get-Content -Path $hashPath -ErrorAction Stop | Select-Object -First 1)
    if ($expected) {
      $expected = ($expected -split '\s+')[0].Trim().ToLower()
      $actual = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLower()
      if ($expected -and $actual -ne $expected) {
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $hashPath -Force -ErrorAction SilentlyContinue
        throw "FreeRDP zip hash mismatch."
      }
    }
  }

  if (-not (Extract-Zip -ZipPath $zipPath -Dest $versionDir)) { throw "Failed to extract FreeRDP zip." }

  Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
  if (Test-Path $hashPath) { Remove-Item -Path $hashPath -Force -ErrorAction SilentlyContinue }

  $exe = Get-ChildItem -Path $versionDir -Filter 'wfreerdp.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $exe) { throw "wfreerdp.exe not found after extraction." }

  return $exe.FullName
}

function New-FreeRdpLauncher {
  param(
    [Parameter(Mandatory=$true)][string]$TargetUser,
    [Parameter(Mandatory=$true)][string]$Host,
    [Parameter(Mandatory=$true)][int]$Port,
    [Parameter(Mandatory=$true)][string]$ClientExe
  )

  $clientDir = Split-Path -Path $ClientExe -Parent
  $cmdName = "Connect - $TargetUser (FreeRDP).cmd"
  $destinations = @(
    Join-Path $PSScriptRoot $cmdName,
    Join-Path $env:Public ("Desktop\" + $cmdName)
  )

  $cmdLines = @(
    '@echo off',
    'setlocal',
    ("set \"CLIENT_DIR={0}\"" -f $clientDir),
    'set "CLIENT=%CLIENT_DIR%\wfreerdp.exe"',
    'if not exist "%CLIENT%" (',
    '  echo FreeRDP client is missing. Please rerun neo_multiseat.ps1.',
    '  pause',
    '  exit /b 1',
    ')',
    'pushd "%CLIENT_DIR%"',
    ("\"%CLIENT%\" /v:{0}:{1} /u:{2} ^" -f $Host,$Port,$TargetUser),
    '  /gfx-h264:avc444 +gfx-progressive /network:auto ^',
    '  /dynamic-resolution /bpp:32 /rfx ^',
    '  /mouse:relative:on /grab:keyboard ^',
    '  /scale:100 /kbd:0x409',
    'set "EXITCODE=%ERRORLEVEL%"',
    'popd',
    'endlocal & exit /b %EXITCODE%'
  )

  $content = ($cmdLines -join "`r`n") + "`r`n"
  $encoding = [System.Text.Encoding]::ASCII

  foreach ($dest in $destinations) {
    try {
      $dir = Split-Path -Path $dest -Parent
      if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      [System.IO.File]::WriteAllText($dest, $content, $encoding)
    } catch {
      Write-Warning "Failed to create FreeRDP launcher at $dest: $($_.Exception.Message)"
    }
  }

  Write-Host "Created FreeRDP launcher(s):" -ForegroundColor Green
  foreach ($dest in $destinations) { Write-Host "  $dest" }
}

# --- Networking + zip helpers -----------------------------------------
function Get-WebFile {
  param([string]$Uri, [string]$OutFile)
  Write-Host ("Downloading " + $Uri)
  try {
    Invoke-WebRequest -Uri $Uri -UseBasicParsing -OutFile $OutFile -ErrorAction Stop
    return $true
  } catch {
    Write-Warning ("Failed to download: {0}  ->  {1}" -f $Uri, $_.Exception.Message)
    return $false
  }
}

function Extract-Zip {
  param([string]$ZipPath, [string]$Dest)
  try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Dest -Force
    return $true
  } catch {
    try {
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
      $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
      foreach ($entry in $zip.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        $target = Join-Path $Dest $entry.FullName
        $dir = Split-Path $target -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $entryStream = $entry.Open()
        $fileStream  = [System.IO.File]::Open($target,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
        $entryStream.CopyTo($fileStream)
        $fileStream.Close(); $entryStream.Close()
      }
      $zip.Dispose()
      return $true
    } catch {
      Write-Warning "Zip extract failed: $($_.Exception.Message)"
      return $false
    }
  }
}

# --- Installer download / layout (your mirrors) -----------------------
function Ensure-UpstreamBinaries {
  $prog = "${env:ProgramFiles}\RDP Wrapper"
  if (-not (Test-Path $prog)) { New-Item -ItemType Directory -Path $prog -Force | Out-Null }

  $rdpZip = Join-Path $env:TEMP ("RDPWrap_{0}.zip" -f (Get-Date -Format 'yyyyMMddHHmmss'))
  $needCore = @('RDPWInst.exe','RDPConf.exe','RDPCheck.exe') | ForEach-Object { -not (Test-Path (Join-Path $prog $_)) }
  if ($needCore -contains $true) {
    if (-not (Get-WebFile -Uri $DL.RDPWrapZip -OutFile $rdpZip)) { throw "Could not download RDPWrap release zip." }
    if (-not (Extract-Zip -ZipPath $rdpZip -Dest $prog)) { throw "Failed to extract RDPWrap release zip." }
    Remove-Item $rdpZip -Force -ErrorAction SilentlyContinue

    # If files ended up inside a subfolder, move them up
    foreach ($name in @('RDPWInst.exe','RDPConf.exe','RDPCheck.exe','rdpwrap.dll','rdpwrap.ini','autoupdate.bat')) {
      $dst = Join-Path $prog $name
      if (-not (Test-Path $dst)) {
        $cand = Get-ChildItem -Path $prog -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cand) { Copy-Item $cand.FullName $dst -Force }
      }
    }
  }

  if (-not (Test-Path (Join-Path $prog 'autoupdate.bat'))) {
    $autoZip = Join-Path $env:TEMP ("autoupdate_{0}.zip" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    if (-not (Get-WebFile -Uri $DL.AutoZip -OutFile $autoZip)) { throw "Could not download autoupdate_v1.2.zip." }
    if (-not (Extract-Zip -ZipPath $autoZip -Dest $prog)) { throw "Failed to extract autoupdate_v1.2.zip." }
    Remove-Item $autoZip -Force -ErrorAction SilentlyContinue
  }
}

# --- User helpers ------------------------------------------------------
function Read-ConfirmedPassword {
  param([string]$PromptUser = "user")
  while ($true) {
    $p1 = Read-Host "Enter password for $PromptUser" -AsSecureString
    $p2 = Read-Host "Confirm password" -AsSecureString
    $b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1)
    $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2)
    try {
      $s1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b1)
      $s2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b2)
    } finally {
      if ($b1) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1) }
      if ($b2) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) }
    }
    if ($s1 -ne $s2) { Write-Warning "Passwords do not match. Try again." ; continue }
    if ([string]::IsNullOrWhiteSpace($s1)) { Write-Warning "Password cannot be empty." ; continue }
    return (ConvertTo-SecureString $s1 -AsPlainText -Force)
  }
}

function Get-RealLocalUsers {
  $builtIns = @('Administrator','DefaultAccount','WDAGUtilityAccount','Guest')
  try {
    Get-LocalUser | Where-Object { $_.Enabled -and ($builtIns -notcontains $_.Name) } | Sort-Object Name
  } catch {
    net user | Select-Object -Skip 4 | ForEach-Object {
      ($_ -split ' {2,}') | Where-Object { $_ -and ($_ -notin $builtIns) }
    } | Where-Object { $_ -and ($_ -notmatch 'The command completed successfully') } |
    ForEach-Object { [PSCustomObject]@{ Name = $_ ; Enabled = $true } }
  }
}

function Ensure-User {
  Write-Host "=== Choose or Create neo_multiseat User ===`n"
  $users = Get-RealLocalUsers
  if ($users.Count) {
    $i=1; foreach ($u in $users) { Write-Host ("[{0}] {1}" -f $i, $u.Name) ; $i++ }
  } else {
    Write-Host "(No existing enabled local users were found.)"
  }
  Write-Host "[N] New user"
  do {
    $sel = Read-Host "Select number or press N for new user"
    if ($sel -match '^(?i)N$') {
      do { $newName = Read-Host "Enter new username (must not be empty)" } until (-not [string]::IsNullOrWhiteSpace($newName))
      $pw = Read-ConfirmedPassword -PromptUser $newName
      if (Get-LocalUser -Name $newName -ErrorAction SilentlyContinue) {
        Write-Warning "User '$newName' already exists. Will update password and membership."
        Set-LocalUser -Name $newName -Password $pw
      } else {
        New-LocalUser -Name $newName -Password $pw -FullName $newName -AccountNeverExpires:$true | Out-Null
      }
      if (-not (Get-LocalGroupMember -Group 'Remote Desktop Users' -Member $newName -ErrorAction SilentlyContinue)) {
        Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $newName
      }
      return $newName
    }
    elseif ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $users.Count) {
      $chosen = $users[[int]$sel - 1].Name
      Write-Host "Selected existing user: $chosen" -ForegroundColor Cyan
      $pw = Read-ConfirmedPassword -PromptUser $chosen
      Set-LocalUser -Name $chosen -Password $pw
      if (-not (Get-LocalGroupMember -Group 'Remote Desktop Users' -Member $chosen -ErrorAction SilentlyContinue)) {
        Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $chosen
      }
      return $chosen
    } else {
      Write-Warning "Invalid selection. Try again."
    }
  } while ($true)
}

function Remove-neoUser {
  Write-Host "=== Delete a local user ===`n"
  $users = Get-RealLocalUsers
  if (-not $users.Count) { Write-Warning "No deletable local users found." ; return }
  $i=1; foreach ($u in $users) { Write-Host ("[{0}] {1}" -f $i, $u.Name) ; $i++ }
  Write-Host "[C] Cancel"
  do {
    $sel = Read-Host "Select a user number to delete, or C to cancel"
    if ($sel -match '^(?i)C$') { return }
    elseif ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $users.Count) {
      $chosen = $users[[int]$sel - 1].Name
      if ($chosen -eq $env:USERNAME) { Write-Warning "Refusing to delete the currently logged-in user ($chosen)." ; return }
      $confirm = Read-Host "Type DELETE to remove local user '$chosen'"
      if ($confirm -ne 'DELETE') { Write-Host "Cancelled." ; return }
      try {
        Remove-LocalGroupMember -Group 'Remote Desktop Users' -Member $chosen -ErrorAction SilentlyContinue
        Remove-LocalUser -Name $chosen -ErrorAction Stop
        Write-Host "User '$chosen' deleted."
      } catch {
        Write-Error "Failed to delete '$chosen': $($_.Exception.Message)"
      }
      return
    } else {
      Write-Warning "Invalid selection. Try again."
    }
  } while ($true)
}

function Open-RDP-Folder {
  $prog = "${env:ProgramFiles}\RDP Wrapper"
  if (Test-Path $prog) { Start-Process explorer.exe $prog } else { Write-Warning "RDP Wrapper folder not found at: $prog" }
}

# --- RDP setup ---------------------------------------------------------
function Enable-RDP-And-Firewall {
  $preview = @(
    "Registry flip: Enable RDP connections",
    "Policy keys: allow multiple sessions / raise instance cap",
    "Firewall: disable Windows 'Remote Desktop' group; use neo rules",
    "Firewall: enable neo_multiseat LAN rule by default (LocalSubnet)"
  )
  $gui = "Settings > System > Remote Desktop > Enable"
  $cli = @(
    'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f',
    'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f',
    'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f',
    'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxInstanceCount /t REG_DWORD /d 999999 /f',
    'netsh advfirewall firewall set rule group="remote desktop" new enable=no'
  )
  Confirm-Apply -Title "Enable RDP & policy keys" -PreviewLines $preview -ManualGui $gui -ManualCli $cli -Action {
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxInstanceCount /t REG_DWORD /d 999999 /f | Out-Null
    # Always disable Windows built-in RDP group; we manage access via neo rules
    try { Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop | Out-Null }
    catch { netsh advfirewall firewall set rule group="remote desktop" new enable=no | Out-Null }

    # Ensure our rules exist, use the current RDP port, and default to LAN On (LocalSubnet)
    Align-NeoFirewallRules
    Sync-BlockRules
    try { Enable-NetFirewallRule -DisplayName $RuleLAN -ErrorAction Stop | Out-Null } catch {}
  }

  $svc = 'TermService'
  for ($n=1; $n -le 2; $n++) {
    try {
      Start-Service -Name $svc -ErrorAction Stop
      Start-Sleep -Seconds 2
      if ((Get-Service $svc).Status -eq 'Running') {
        Write-Host "RDP services started successfully." -ForegroundColor Green
        return $true
      }
    } catch {
      Write-Warning ("Attempt {0} of {1}: Failed to start RDP services. Retrying in 2 seconds... {2}" -f $n, 2, $_.Exception.Message)
      Start-Sleep -Seconds 2
    }
  }
  return $false
}

function Install-Or-Update-RDPWrapper {
  $preview = @("Install/Update RDP Wrapper core", "Refresh INI via RDPWInst -w", "Run autoupdate.bat (if present)")
  $cli = @(
    '"C:\Program Files\RDP Wrapper\RDPWInst.exe" -i',
    '"C:\Program Files\RDP Wrapper\RDPWInst.exe" -w',
    '"C:\Program Files\RDP Wrapper\autoupdate.bat"'
  )
  Confirm-Apply -Title "Install/Update RDP Wrapper" -PreviewLines $preview -ManualCli $cli -Action {
    $prog = "${env:ProgramFiles}\RDP Wrapper"
    Ensure-UpstreamBinaries

    $inst = Join-Path $prog 'RDPWInst.exe'
    $conf = Join-Path $prog 'RDPConf.exe'
    $auto = Join-Path $prog 'autoupdate.bat'

    & $inst -i | Write-Host
    & $inst -w | Write-Host
    if (Test-Path $auto) {
      Start-Process -FilePath $auto -Verb RunAs -Wait
    } else {
      Write-Warning "autoupdate.bat not found."
    }
    if (-not (Test-Path $conf)) { throw "RDPConf.exe not found after install." }
  }
}

function Open-RDPConf-ShortGuidance {
  $conf = Join-Path "${env:ProgramFiles}\RDP Wrapper" 'RDPConf.exe'
  Write-Host "`n=== RDP Wrapper diagnostics ==="
  if (Test-Path $conf) {
    Start-Process -FilePath $conf
    Show-ImportantBanner -Text "If anything is RED in RDPConf, you can run the FIX below." -Fg Black -Bg Cyan
  } else {
    Write-Warning "RDPConf.exe not found. Skipping UI check."
  }
}

function Open-RDPConf-And-Guide {
  $conf = Join-Path "${env:ProgramFiles}\RDP Wrapper" 'RDPConf.exe'
  Write-Host "`n=== RDP Wrapper diagnostics ==="
  if (Test-Path $conf) {
    Start-Process -FilePath $conf
    Write-Host "Check that all indicators are GREEN (Supported/Running/Listening, etc.)."
    Read-Host "Press ENTER to continue"
  } else {
    Write-Warning "RDPConf.exe not found. Skipping UI check."
  }
}

# --- FIX ---------------------------------------------------------------
function Fix-RDP-Service {
  $preview = @("Stop RDP services", "Uninstall wrapper via uninstall.bat (if exists)", "Reset termsrv.dll path", "Restart services")
  $cli = @(
    'net stop TermService',
    '"C:\Program Files\RDP Wrapper\uninstall.bat"',
    'reg add HKLM\SYSTEM\CurrentControlSet\Services\TermService\Parameters /v ServiceDll /t REG_EXPAND_SZ /d %SystemRoot%\System32\termsrv.dll /f',
    'net start TermService'
  )
  Confirm-Apply -Title "Fix RDP services (reset to inbox termsrv.dll)" -PreviewLines $preview -ManualCli $cli -Action {
    try {
      Stop-Service TermService -ErrorAction SilentlyContinue
      Stop-Service UmRdpService -ErrorAction SilentlyContinue
      $uninst = "C:\Program Files\RDP Wrapper\uninstall.bat"
      if (Test-Path $uninst) { Start-Process -FilePath $uninst -Verb RunAs -Wait }

      $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters'
      $desired = '%SystemRoot%\System32\termsrv.dll'
      New-ItemProperty -Path $k -Name ServiceDll -PropertyType ExpandString -Value $desired -Force | Out-Null

      try { Set-Service -Name TermService -StartupType Automatic } catch {}
      try { Set-Service -Name UmRdpService -StartupType Manual } catch {}
      Start-Service TermService
      Start-Service UmRdpService
      Get-Service TermService,UmRdpService,SessionEnv | Format-Table Name,Status,StartType -AutoSize
    } catch {
      Write-Error $_.Exception.Message
      throw
    }
  }
}

# --- Net config (JSON) + reconciliation with OS -----------------------
function Load-NetConfig {
  if (Test-Path $ConfigPath) {
    try { return Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch {}
  }
  # Defaults: all off
  return [PSCustomObject]@{
    LAN = @{ Enabled = $false; Allowlist = @("LocalSubnet") }
    WAN = @{ Enabled = $false; Allowlist = @() }
    TS  = @{ Enabled = $false }
    Security = @{ 
      NLA = $false; NTLMv1Disabled = $false; LockoutPolicy = $false;
      MonitorSilent = $false; MonitorThreshold = 5; MonitorWindowSec = 60;
      AlertOnBurst = $true; AlertOnLockout = $true; AutoPopMonitor = $true 
    }
  }
}
function Save-NetConfig($cfg) { $cfg | ConvertTo-Json -Depth 6 | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force }

function Ensure-NeoFirewallRules {
  if (-not (Get-NetFirewallRule -DisplayName $RuleLAN -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $RuleLAN -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow `
      -RemoteAddress LocalSubnet -Service TermService -Profile Any -Enabled False | Out-Null
  }
  if (-not (Get-NetFirewallRule -DisplayName $RuleWAN -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $RuleWAN -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow `
      -RemoteAddress "0.0.0.0/32" -Service TermService -Profile Any -Enabled False | Out-Null
  }
  if (-not (Get-NetFirewallRule -DisplayName $RuleTS -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $RuleTS -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow `
      -InterfaceAlias "Tailscale*" -Service TermService -Profile Any -Enabled False | Out-Null
  }
  # Block rules (disabled by default)
  if (-not (Get-NetFirewallRule -DisplayName $RuleTSBlock -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $RuleTSBlock -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Block `
      -InterfaceAlias "Tailscale*" -Profile Any -Enabled False | Out-Null
  }
  if (-not (Get-NetFirewallRule -DisplayName $RuleBlockAll -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $RuleBlockAll -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Block `
      -RemoteAddress Any -Profile Any -Enabled False | Out-Null
  }
}

# Disable the built-in Windows firewall group for RDP so our rules control access
function Disable-BaseRdpFirewallRules {
  try { Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop | Out-Null }
  catch { netsh advfirewall firewall set rule group="remote desktop" new enable=no | Out-Null }
}

# Ensure neo rules use the active RDP port and correct profiles
function Get-RdpPort {
  $port = 3389
  try {
    $pn = (Get-ItemProperty -Path $RdpKey -Name PortNumber -ErrorAction SilentlyContinue).PortNumber
    if ($pn) { $port = [int]$pn }
  } catch {}
  return $port
}

function Ensure-NeoRuleProfiles {
  try { Set-NetFirewallRule -DisplayName $RuleLAN -Profile Any | Out-Null } catch {}
  try { Set-NetFirewallRule -DisplayName $RuleWAN -Profile Any | Out-Null } catch {}
  try { Set-NetFirewallRule -DisplayName $RuleTS  -Profile Any | Out-Null } catch {}
}

function Ensure-NeoRulePorts {
  $p = Get-RdpPort
  try { Set-NetFirewallRule -DisplayName $RuleLAN | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $p | Out-Null } catch {}
  try { Set-NetFirewallRule -DisplayName $RuleWAN | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $p | Out-Null } catch {}
  try { Set-NetFirewallRule -DisplayName $RuleTS  | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $p | Out-Null } catch {}
  try { Set-NetFirewallRule -DisplayName $RuleTSBlock | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $p | Out-Null } catch {}
  try { Set-NetFirewallRule -DisplayName $RuleBlockAll | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $p | Out-Null } catch {}
}

function Align-NeoFirewallRules {
  Ensure-NeoFirewallRules
  Ensure-NeoRuleProfiles
  Ensure-NeoRulePorts
}

# Enable/disable block rules based on current desired state
function Sync-BlockRules {
  $cfg = Load-NetConfig
  # Tailscale block is enabled when TS is Off
  try {
    if ($cfg.TS.Enabled) { Disable-NetFirewallRule -DisplayName $RuleTSBlock -ErrorAction SilentlyContinue | Out-Null }
    else { Enable-NetFirewallRule -DisplayName $RuleTSBlock -ErrorAction SilentlyContinue | Out-Null }
  } catch {}
  # Global block-all is enabled when all three are Off
  $anyOn = ($cfg.LAN.Enabled -or $cfg.WAN.Enabled -or $cfg.TS.Enabled)
  try {
    if ($anyOn) { Disable-NetFirewallRule -DisplayName $RuleBlockAll -ErrorAction SilentlyContinue | Out-Null }
    else { Enable-NetFirewallRule -DisplayName $RuleBlockAll -ErrorAction SilentlyContinue | Out-Null }
  } catch {}
}

# Find any other inbound allow rules that would permit RDP (TCP 3389 or TermService)
function Get-NonNeoRdpAllowRules {
  $ours = @($RuleLAN,$RuleWAN,$RuleTS)
  $candidates = @()
  try {
    $rules = Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue
    foreach ($r in $rules) {
      if ($r.DisplayName -in $ours) { continue }
      $isRdp = $false
      try {
        $pf = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
        if ($pf) {
          $proto = $pf.Protocol
          $lport = $pf.LocalPort
          if ($proto -eq 'TCP' -and $lport) {
            if ($lport -is [array]) { if ($lport -contains 3389 -or $lport -contains '3389') { $isRdp = $true } }
            else { if ($lport -eq 3389 -or $lport -eq '3389') { $isRdp = $true } }
          }
        }
      } catch {}
      if (-not $isRdp) {
        try {
          $sf = Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
          if ($sf -and ($sf.Service -match 'TermService')) { $isRdp = $true }
        } catch {}
      }
      if (-not $isRdp) {
        # As a fallback, treat any rule in the built-in group as RDP
        if ($r.DisplayGroup -eq 'Remote Desktop') { $isRdp = $true }
      }
      if ($isRdp) { $candidates += $r }
    }
  } catch {}
  return $candidates
}

function Quarantine-ConflictingRdpRules {
  $others = Get-NonNeoRdpAllowRules
  foreach ($r in $others) {
    try { Disable-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue | Out-Null } catch {}
  }
}

# Sync JSON to actual firewall state (persists across runs/reboots)
function Reconcile-NetConfig {
  $cfg = Load-NetConfig

  $lanR = Get-NetFirewallRule -DisplayName $RuleLAN -ErrorAction SilentlyContinue
  if ($lanR) {
    $cfg.LAN.Enabled = ($lanR.Enabled -eq 'True')
    try {
      $lanAddr = (Get-NetFirewallRule -DisplayName $RuleLAN | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue).RemoteAddress
      if ($lanAddr) { $cfg.LAN.Allowlist = @($lanAddr) }
    } catch {}
  }

  $wanR = Get-NetFirewallRule -DisplayName $RuleWAN -ErrorAction SilentlyContinue
  if ($wanR) {
    $cfg.WAN.Enabled = ($wanR.Enabled -eq 'True')
    try {
      $wanAddr = (Get-NetFirewallRule -DisplayName $RuleWAN | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue).RemoteAddress
      if ($wanAddr) { $cfg.WAN.Allowlist = @($wanAddr) }
    } catch {}
  }

  $tsR = Get-NetFirewallRule -DisplayName $RuleTS -ErrorAction SilentlyContinue
  if ($tsR) { $cfg.TS.Enabled = ($tsR.Enabled -eq 'True') }

  Save-NetConfig $cfg
}

function Show-NetModesStatus {
  Ensure-NeoFirewallRules
  # Fast, cached status rendering
  Show-NetModesStatusCached
}

function Set-WAN-Allowlist { param([string[]]$Cidrs)
  if (-not $Cidrs -or -not $Cidrs.Count) { throw "WAN allowlist cannot be empty." }
  if (-not (Test-WAN-AllowlistSafe $Cidrs)) { throw "WAN allowlist too broad. Avoid Any/0.0.0.0/0." }
  Set-NetFirewallRule -DisplayName $RuleWAN | Set-NetFirewallAddressFilter -RemoteAddress ($Cidrs -join ",") | Out-Null
  $cfg = Load-NetConfig; $cfg.WAN.Allowlist = $Cidrs; Save-NetConfig $cfg
  Refresh-NetModesCache -Force
}
function Set-LAN-Allowlist { param([string[]]$Cidrs)
  if (-not $Cidrs -or -not $Cidrs.Count) { throw "LAN allowlist cannot be empty." }
  Set-NetFirewallRule -DisplayName $RuleLAN | Set-NetFirewallAddressFilter -RemoteAddress ($Cidrs -join ",") | Out-Null
  $cfg = Load-NetConfig; $cfg.LAN.Allowlist = $Cidrs; Save-NetConfig $cfg
  Refresh-NetModesCache -Force
}

function Toggle-Mode {
  param([ValidateSet('LAN','WAN','TS')][string]$Mode, [bool]$Enabled)
  # Ensure Windows built-in RDP group is disabled so toggles are authoritative
  Disable-BaseRdpFirewallRules
  Align-NeoFirewallRules
  Quarantine-ConflictingRdpRules
  if ($Mode -eq 'WAN' -and $Enabled) {
    $cfg = Load-NetConfig
    if (-not (Test-WAN-AllowlistSafe $cfg.WAN.Allowlist)) {
      Write-Host 'Refusing to enable WAN: allowlist must contain specific CIDR/IP (not Any/0.0.0.0/0).' -ForegroundColor Red
      Write-Host 'Set a WAN allowlist first (menu 5 -> option 5).' -ForegroundColor Yellow
      return
    }
  }
  $name = switch($Mode){ 'LAN'{$RuleLAN} 'WAN'{$RuleWAN} 'TS'{$RuleTS} }
  if ($Enabled) { Enable-NetFirewallRule -DisplayName $name | Out-Null } else { Disable-NetFirewallRule -DisplayName $name | Out-Null }
  $cfg = Load-NetConfig
  switch($Mode){ 'LAN' { $cfg.LAN.Enabled = $Enabled } 'WAN' { $cfg.WAN.Enabled = $Enabled } 'TS' { $cfg.TS.Enabled = $Enabled } }
  Save-NetConfig $cfg
  Refresh-NetModesCache -Force
  Sync-BlockRules
}

function Input-CIDRs { param([string]$Prompt)
  $raw = Read-Host $Prompt
  $arr = @()
  foreach ($p in ($raw -split ',')) { $t = $p.Trim(); if ($t) { $arr += $t } }
  return $arr
}

function Test-WAN-AllowlistSafe { param([string[]]$Cidrs)
  if (-not $Cidrs -or -not $Cidrs.Count) { return $false }
  $unsafe = @('any','*','0.0.0.0','0.0.0.0/0','::/0')
  foreach ($c in $Cidrs) {
    $norm = ($c.Trim()).ToLower()
    if ($unsafe -contains $norm) { return $false }
  }
  return $true
}

# Live monitor and security tools --------------------------------------
# --- Cached status for faster menu 5 -----------------------------------
$script:NeoNetCache = [PSCustomObject]@{
  LastRefreshed = Get-Date '2000-01-01'
  BaseOn = $false
  Conflicts = 0
  LAN = @{ Enabled=$false; Allowlist='LocalSubnet' }
  WAN = @{ Enabled=$false; Allowlist='' }
  TS  = @{ Enabled=$false; Adapter='not detected'; Has100=$false }
}

function Refresh-NetModesCache { param([switch]$Force)
  $minInterval = [TimeSpan]::FromSeconds(2)
  $now = Get-Date
  if (-not $Force -and ($now - $script:NeoNetCache.LastRefreshed) -lt $minInterval) { return }

  $cfg = Load-NetConfig
  $lanR = Get-NetFirewallRule -DisplayName $RuleLAN -ErrorAction SilentlyContinue
  $wanR = Get-NetFirewallRule -DisplayName $RuleWAN -ErrorAction SilentlyContinue
  $tsR  = Get-NetFirewallRule -DisplayName $RuleTS  -ErrorAction SilentlyContinue

  $script:NeoNetCache.LAN.Enabled = ($lanR -and $lanR.Enabled -eq 'True')
  $script:NeoNetCache.WAN.Enabled = ($wanR -and $wanR.Enabled -eq 'True')
  $script:NeoNetCache.TS.Enabled  = ($tsR  -and $tsR.Enabled  -eq 'True')

  # Use our JSON config as the source of truth for allowlists (fast)
  $script:NeoNetCache.LAN.Allowlist = if ($cfg.LAN.Allowlist -and $cfg.LAN.Allowlist.Count) { ($cfg.LAN.Allowlist -join ', ') } else { 'LocalSubnet' }
  $script:NeoNetCache.WAN.Allowlist = if ($cfg.WAN.Allowlist -and $cfg.WAN.Allowlist.Count) { ($cfg.WAN.Allowlist -join ', ') } else { '<empty>' }

  # Base Windows group state
  $baseOn = $false
  try { $baseOn = (Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq 'True' }).Count -gt 0 } catch {}
  $script:NeoNetCache.BaseOn = $baseOn

  # Conflicts check skipped by default for speed; quarantined on toggles
  $script:NeoNetCache.Conflicts = 0

  # Tailscale status (quick)
  $ts = Get-TailscaleStatus
  $script:NeoNetCache.TS.Adapter = if ($ts.Adapter) { $ts.Adapter.Name } else { 'not detected' }
  $script:NeoNetCache.TS.Has100  = $ts.Has100

  $script:NeoNetCache.LastRefreshed = $now
}

function Show-NetModesStatusCached {
  Refresh-NetModesCache
  $lanEnabled = $script:NeoNetCache.LAN.Enabled
  $wanEnabled = $script:NeoNetCache.WAN.Enabled
  $tsEnabled  = $script:NeoNetCache.TS.Enabled
  $lanAllow = $script:NeoNetCache.LAN.Allowlist
  $wanAllow = $script:NeoNetCache.WAN.Allowlist
  $tsAdapterName = $script:NeoNetCache.TS.Adapter
  $tsHas100 = $script:NeoNetCache.TS.Has100

  $lanLabel = if ($lanEnabled) { 'On (working)' } else { 'Off (disconnected)' }
  $wanLabel = if ($wanEnabled) { 'On (working)' } else { 'Off (disconnected)' }
  $lanColor = if ($lanEnabled) { 'Green' } else { 'DarkGray' }
  $wanColor = if ($wanEnabled) { 'Green' } else { 'DarkGray' }
  $tsWorking = $tsEnabled -and ($tsAdapterName -ne 'not detected') -and $tsHas100
  $tsLabel = if ($tsEnabled) { if ($tsWorking) { 'On (working)' } else { 'On (disconnected)' } } else { 'Off (disconnected)' }
  $tsColor = if ($tsEnabled -and $tsWorking) { 'Green' } else { 'DarkGray' }

  Write-Host ''
  Write-Host '=== Network access modes ===' -ForegroundColor Cyan
  if ($script:NeoNetCache.BaseOn) { Write-Host 'Windows RDP group: Enabled (overrides neo rules)' -ForegroundColor Red } else { Write-Host 'Windows RDP group: Disabled (neo rules in control)' -ForegroundColor DarkGray }
  # Conflicts are quarantined automatically when toggles run; full scan omitted for speed
  Write-Host ("LAN:       {0}    allowlist: {1}" -f $lanLabel, $lanAllow) -ForegroundColor $lanColor
  Write-Host ("WAN:       {0}    allowlist: {1}" -f $wanLabel, $wanAllow) -ForegroundColor $wanColor
  Write-Host ("Tailscale: {0}    adapter: {1}, 100.x: {2}" -f $tsLabel, $tsAdapterName, $(if($tsHas100){'Yes'}else{'No'})) -ForegroundColor $tsColor
}

# Auto-pop monitor if triggered (burst or lockout) and allowed by config
function Start-MonitorIfTriggered {
  try {
    $cfg = Load-NetConfig
    if (-not $cfg -or -not $cfg.Security) { return }
    if (-not $cfg.Security.AutoPopMonitor) { return }
    if ($cfg.Security.MonitorSilent) { return }
    $win = [int]$cfg.Security.MonitorWindowSec; if ($win -le 0) { $win = 60 }
    $thr = [int]$cfg.Security.MonitorThreshold; if ($thr -le 0) { $thr = 5 }
    $since = (Get-Date).AddSeconds(-$win)
    $fails = @(Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=$since} -MaxEvents 200 -ErrorAction SilentlyContinue).Count
    $hasLock = @(Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4740; StartTime=$since} -MaxEvents 50 -ErrorAction SilentlyContinue).Count -gt 0
    $should = ($cfg.Security.AlertOnBurst -and ($fails -ge $thr)) -or ($cfg.Security.AlertOnLockout -and $hasLock)
    if (-not $should) { return }
    $lock = Join-Path $script:LogDir 'neo_monitor.lock'
    if (Test-Path $lock) {
      $age = (Get-Date) - (Get-Item $lock).LastWriteTime
      if ($age.TotalMinutes -lt 5) { return }
    }
    Start-LiveMonitorWindow
  } catch {}
}
function Get-4625Reason { param([string]$Status,[string]$Sub)
  $s = ("$Status").ToUpper(); $u = ("$Sub").ToUpper()
  if ($u -eq '0XC000006A') { return 'Bad password' }
  if ($u -eq '0XC0000064') { return 'User does not exist' }
  if ($u -eq '0XC0000234') { return 'Account locked out' }
  if ($u -eq '0XC0000070') { return 'Account restrictions' }
  if ($u -eq '0XC000006F') { return 'Logon time restriction' }
  if ($u -eq '0XC0000071') { return 'Password expired' }
  if ($u -eq '0XC0000193') { return 'Account expired' }
  if ($u -eq '0XC0000133') { return 'Time difference at DC' }
  if ($u -eq '0XC000015B') { return 'Not granted logon type' }
  if ($u -eq '0XC000005E') { return 'No logon servers available' }
  if ($s -eq '0XC000006D') { return 'Logon failure' }
  if ($s -eq '0XC000006A') { return 'Bad password' }
  if ($s -eq '0XC0000064') { return 'User does not exist' }
  return 'Unknown reason'
}

function Start-BruteforceMonitor {
  Write-Host ""
  Show-ImportantBanner -Text "Live auth monitor (4625 fails / 4740 lockouts). Q=quit, S=summary, C=clear, P=paged" -Fg Black -Bg Yellow
  $since = (Get-Date).AddSeconds(-5)

  $windowSec = 60
  $burstThreshold = 5
  $byIp = @{}      # ip -> [DateTime[]]
  $byUser = @{}    # user -> [DateTime[]]
  $recent = New-Object System.Collections.ArrayList  # rolling recent lines
  $summaryOnly = $false

  function Add-ToMap([hashtable]$map,[string]$key,[datetime]$ts){
    if (-not $map.ContainsKey($key)) { $map[$key] = New-Object System.Collections.ArrayList }
    [void]$map[$key].Add($ts)
    $cut=(Get-Date).AddSeconds(-$windowSec)
    $keep = New-Object System.Collections.ArrayList
    foreach($t in $map[$key]){ if($t -gt $cut){ [void]$keep.Add($t) } }
    $map[$key]=$keep
  }

  function Top5($map){
    $rows=@()
    foreach($k in $map.Keys){ $rows += [PSCustomObject]@{ Key=$k; Count=$map[$k].Count; Last= ($map[$k] | Sort-Object -Descending | Select-Object -First 1) } }
    $rows | Where-Object { $_.Count -gt 0 } |
      Sort-Object -Property @{Expression='Count';Descending=$true}, @{Expression='Last';Descending=$true} |
      Select-Object -First 5
  }

  function Print-Summary(){
    Write-Host ""; Write-Host "Top IPs (last $windowSec s):" -ForegroundColor Cyan
    $topIp = Top5 $byIp
    if ($topIp){ foreach($r in $topIp){ Write-Host ("  {0,3}  {1,-18}  last {2:HH:mm:ss}" -f $r.Count,$r.Key,$r.Last) -ForegroundColor Red } } else { Write-Host "  (none)" -ForegroundColor DarkGray }
    Write-Host "Top Users (last $windowSec s):" -ForegroundColor Cyan
    $topUser = Top5 $byUser
    if ($topUser){ foreach($r in $topUser){ Write-Host ("  {0,3}  {1}" -f $r.Count,$r.Key) -ForegroundColor Yellow } } else { Write-Host "  (none)" -ForegroundColor DarkGray }
  }

  function Load-4625Paged([int]$Max=5000){
    $items = @()
    try {
      $evts = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents $Max -ErrorAction SilentlyContinue
      foreach($e in $evts){
        try{
          $xml=[xml]$e.ToXml(); $data=@{}; foreach($d in $xml.Event.EventData.Data){ $data[$d.Name]=$d.'#text' }
          $ip=$data['IpAddress']; if(-not $ip){$ip='-'}
          $user=$data['TargetUserName']; $work=$data['WorkstationName']
          $st=$data['Status']; $sub=$data['SubStatus']; $reason=Get-4625Reason -Status $st -Sub $sub
          $items += [PSCustomObject]@{ Time=$e.TimeCreated; User=$user; IP=$ip; Workstation=$work; Reason=$reason; Status=$st; SubStatus=$sub }
        }catch{}
      }
    }catch{}
    # Newest first
    return ($items | Sort-Object Time -Descending)
  }

  function Show-Paged([object[]]$items,[int]$PageSize=100){
    if(-not $items -or $items.Count -eq 0){ Write-Host 'No failed logons found.' -ForegroundColor DarkGray; return }
    $total=$items.Count; $pages=[math]::Ceiling($total/[double]$PageSize)
    $pi=0
    while($true){
      Clear-Host
      Show-ImportantBanner -Text ("4625 failed logons (page {0}/{1}, newest first). N=next, B=back, R=reload, Q=quit" -f ($pi+1),$pages) -Fg Black -Bg Yellow
      $start=$pi*$PageSize
      $slice=$items[$start..([math]::Min($start+$PageSize-1,$total-1))]
      '{0,-10}  {1,-20}  {2,-18}  {3,-10}  {4}' -f 'Time','User','IP','Status','Reason' | Write-Host -ForegroundColor Cyan
      foreach($it in $slice){
        '{0:HH:mm:ss}   {1,-20}  {2,-18}  {3,-10}  {4}' -f $it.Time,$it.User,$it.IP,$it.Status,$it.Reason | Write-Host -ForegroundColor Red
      }
      $k=[Console]::ReadKey($true)
      if($k.Key -eq 'Q'){ break }
      elseif($k.Key -eq 'N'){ if($pi -lt ($pages-1)){ $pi++ } }
      elseif($k.Key -eq 'B'){ if($pi -gt 0){ $pi-- } }
      elseif($k.Key -eq 'R'){ $items=Load-4625Paged $items.Count; $total=$items.Count; $pages=[math]::Ceiling($total/[double]$PageSize); if($pi -ge $pages){$pi=[math]::Max(0,$pages-1)} }
    }
  }

  while ($true) {
    while ([Console]::KeyAvailable) {
      $k = [Console]::ReadKey($true)
      if ($k.Key -eq 'Q') { return }
      if ($k.Key -eq 'S') { $summaryOnly = -not $summaryOnly }
      if ($k.Key -eq 'C') { $byIp=@{}; $byUser=@{}; $recent=New-Object System.Collections.ArrayList; Clear-Host; Show-ImportantBanner -Text "Live auth monitor (4625 fails / 4740 lockouts). Q=quit, S=summary, C=clear, P=paged" -Fg Black -Bg Yellow }
      if ($k.Key -eq 'P') { $data=Load-4625Paged 5000; Show-Paged -items $data -PageSize 100; Clear-Host; Show-ImportantBanner -Text "Live auth monitor (4625 fails / 4740 lockouts). Q=quit, S=summary, C=clear, P=paged" -Fg Black -Bg Yellow; $since=(Get-Date).AddSeconds(-5) }
    }
    try {
      $events4625 = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=$since} -ErrorAction SilentlyContinue
      foreach ($e in $events4625) {
        try {
          $xml = [xml]$e.ToXml()
          $data = @{}
          foreach ($d in $xml.Event.EventData.Data) { $data[$d.Name] = $d.'#text' }
          $ip = $data['IpAddress']; if (-not $ip) { $ip = '-' }
          $user = $data['TargetUserName']
          $work = $data['WorkstationName']
          $st   = $data['Status']
          $sub  = $data['SubStatus']
          $reason = Get-4625Reason -Status $st -Sub $sub

          if ($ip -and $ip -ne '-' -and $ip -ne '::1') { Add-ToMap $byIp $ip $e.TimeCreated }
          if ($user) { Add-ToMap $byUser $user $e.TimeCreated }

          $line = "[{0:HH:mm:ss}] FAIL  {1}@{2}  {3}  ({4}/{5})" -f $e.TimeCreated, $user, $ip, $reason, $st, $sub
          if (-not $summaryOnly) { Write-Host $line -ForegroundColor Red }
          try {
            $count = if($ip -and $byIp.ContainsKey($ip)) { $byIp[$ip].Count } else { 0 }
            if ($count -ge $burstThreshold) { try { [Console]::Beep(900,180) } catch {} }
          } catch {}
        } catch { Write-Host ("Monitor decode error: " + $_.Exception.Message) -ForegroundColor DarkRed }
      }

      $events4740 = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4740; StartTime=$since} -ErrorAction SilentlyContinue
      foreach ($e in $events4740) {
        try {
          $xml = [xml]$e.ToXml()
          $data = @{}
          foreach ($d in $xml.Event.EventData.Data) { $data[$d.Name] = $d.'#text' }
          $tuser  = $data['TargetUserName']
          $caller = $data['CallerComputerName']
          try { [Console]::Beep(600,200) } catch {}
          $line = "[{0:HH:mm:ss}] LOCK  user={1}  caller={2}" -f $e.TimeCreated, $tuser, $caller
          if (-not $summaryOnly) { Write-Host $line -ForegroundColor Yellow }
        } catch { Write-Host ("Monitor decode error (4740): " + $_.Exception.Message) -ForegroundColor DarkRed }
      }

      if ($summaryOnly) { Print-Summary }
      $since = Get-Date
    } catch { Write-Host ("Monitor error: " + $_.Exception.Message) -ForegroundColor DarkRed }
    Start-Sleep -Milliseconds 700
  }
}

# --- Monitor in new window (alerting) ---------------------------------
function Start-LiveMonitorWindow {
  $tmp = Join-Path $env:TEMP ("neo_live_monitor_{0:yyyyMMdd_HHmmss}.ps1" -f (Get-Date))
  $script = @'
$ErrorActionPreference = "Continue"
try { $host.UI.RawUI.WindowTitle = 'neo_multiseat live logon monitor' } catch {}

function Get-4625Reason { param([string]$Status,[string]$Sub)
  $s = ("$Status").ToUpper(); $u = ("$Sub").ToUpper()
  if ($u -eq '0XC000006A') { return 'Bad password' }
  if ($u -eq '0XC0000064') { return 'User does not exist' }
  if ($u -eq '0XC0000234') { return 'Account locked out' }
  if ($u -eq '0XC0000070') { return 'Account restrictions' }
  if ($u -eq '0XC000006F') { return 'Logon time restriction' }
  if ($u -eq '0XC0000071') { return 'Password expired' }
  if ($u -eq '0XC0000193') { return 'Account expired' }
  if ($u -eq '0XC0000133') { return 'Time difference at DC' }
  if ($u -eq '0XC000015B') { return 'Not granted logon type' }
  if ($u -eq '0XC000005E') { return 'No logon servers available' }
  if ($s -eq '0XC000006D') { return 'Logon failure' }
  if ($s -eq '0XC000006A') { return 'Bad password' }
  if ($s -eq '0XC0000064') { return 'User does not exist' }
  return 'Unknown reason'
}

function Get-AuditLogonStatus {
  $succ = $false; $fail = $false
  try {
    $out = & auditpol.exe /get /subcategory:"Logon" 2>$null
    if ($out) {
      foreach($line in $out){
        if ($line -match '(?i)Success\s*:\s*Enable') { $succ = $true }
        if ($line -match '(?i)Failure\s*:\s*Enable') { $fail = $true }
      }
    }
  } catch {}
  [PSCustomObject]@{ Success=$succ; Failure=$fail }
}

function Parse-Event([System.Diagnostics.Eventing.Reader.EventRecord]$e){
  $xml = [xml]$e.ToXml()
  $d = @{}
  foreach($x in $xml.Event.EventData.Data){ $d[$x.Name] = $x.'#text' }
  $type = $e.Id
  $user = $d['TargetUserName']
  $ip   = if($d.ContainsKey('IpAddress') -and $d['IpAddress']) { $d['IpAddress'] } else { '-' }
  $lt   = $d['LogonType']
  $ws   = $d['WorkstationName']
  $st   = $d['Status']
  $sub  = $d['SubStatus']
  $reason = if($type -eq 4625){ Get-4625Reason -Status $st -Sub $sub } else { '' }
  [PSCustomObject]@{ Type=$type; Time=$e.TimeCreated; Record=$e.RecordId; User=$user; IP=$ip; LT=$lt; WS=$ws; Status=$st; Sub=$sub; Reason=$reason }
}

function Write-Footer($filters){
  try {
    $wTop = [Console]::WindowTop
    $wHeight = [Console]::WindowHeight
    $wWidth = [Console]::WindowWidth
    $oldL = [Console]::CursorLeft; $oldT = [Console]::CursorTop
    $row1 = $wTop
    $row2 = $wTop + 1
    $line1 = ($filters + (' ' * $wWidth))
    if ($line1.Length -gt $wWidth) { $line1 = $line1.Substring(0,$wWidth) }
    $line2 = '  Live logon monitor. Q=quit  R=RDP-only  S=toggle-success  K=lock  L=list +/-=days +/-  C=clear  E=export  G=GUI' + (' ' * $wWidth)
    if ($line2.Length -gt $wWidth) { $line2 = $line2.Substring(0,$wWidth) }
    [Console]::SetCursorPosition(0,$row1); [Console]::Write($line1)
    [Console]::SetCursorPosition(0,$row2); [Console]::Write($line2)
    [Console]::SetCursorPosition($oldL,$oldT)
  } catch {}
}

# Enable audit policy
try { & auditpol.exe /set /subcategory:"Logon" /success:enable /failure:enable | Out-Null } catch {}
$audit = Get-AuditLogonStatus
Write-Host ("Audit policy: Success={0}  Failure={1}" -f $(if($audit.Success){'On'}else{'Off'}), $(if($audit.Failure){'On'}else{'Off'})) -ForegroundColor DarkCyan

$rdpOnly = $true
$showSuccess = $true
$showFail = $true
$showLock = $true
$days = 4
$inp = Read-Host 'Days to list initially (ENTER=4)'
if ($inp -match '^[0-9]+$' -and [int]$inp -ge 1) { $days = [int]$inp }
$ids = 4624,4625,4740
$lastRecord = 0L

$global:lastFooter = ''
$global:lastFooterAt = Get-Date '2000-01-01'
$global:lastRow = $null
function Print-Status(){
  $s = ("RDP-only={0}  Success={1}  Lockout={2}  Days={3}" -f `
    $(if($rdpOnly){'On'}else{'Off'}), $(if($showSuccess){'On'}else{'Off'}), $(if($showLock){'On'}else{'Off'}), $days)
  $now = Get-Date
  if ($s -ne $global:lastFooter -or ($now - $global:lastFooterAt).TotalMilliseconds -gt 800) {
    Write-Footer $s
    $global:lastFooter = $s
    $global:lastFooterAt = $now
  }
}

function Print-Line($o){
  $global:lastRow = $o
  if ($o.Type -eq 4624) {
    if (-not $showSuccess) { return }
    if ($rdpOnly -and $o.LT -ne '10') { return }
    Write-Host ("[{0:yyyy-MM-dd HH:mm:ss}] SUCCESS {1}@{2} LT={3} WS={4}" -f $o.Time, $o.User, $o.IP, $o.LT, $o.WS) -ForegroundColor Green
  } elseif ($o.Type -eq 4625) {
    if (-not $showFail) { return }
    # Treat RDP-related failures as LT 10 (RemoteInteractive) OR network pre-auth types 3/7
    if ($rdpOnly -and (@('10','3','7') -notcontains $o.LT)) { return }
    Write-Host ("[{0:yyyy-MM-dd HH:mm:ss}] FAIL    {1}@{2} {3} (Status {4}/{5}) LT={6} WS={7}" -f $o.Time, $o.User, $o.IP, $o.Reason, $o.Status, $o.Sub, $o.LT, $o.WS) -ForegroundColor Red
  } else {
    if (-not $showLock) { return }
    Write-Host ("[{0:yyyy-MM-dd HH:mm:ss}] LOCKOUT user={1} caller={2}" -f $o.Time, $o.User, $o.WS) -ForegroundColor Yellow
  }
}

function Get-EventByRecordId([long]$rid){
  try {
    $fx = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">*[System[(EventRecordID=$rid)]]</Select>
  </Query>
</QueryList>
"@
    $e = Get-WinEvent -FilterXml $fx -ErrorAction SilentlyContinue | Select-Object -First 1
    return $e
  } catch { return $null }
}

function Show-EventDetailsByObject($o){
  try {
    $rid = [long]$o.Record
  } catch { $rid = $null }
  $e = $null
  if ($rid) { $e = Get-EventByRecordId -rid $rid }
  $tmp = Join-Path $env:TEMP ("neo_event_details_{0:yyyyMMdd_HHmmss}_{1}.txt" -f (Get-Date), $(if($rid){$rid}else{'nr'}))
  $lines = @()
  $lines += ("Type:    {0}" -f $o.Type)
  $lines += ("Time:    {0:yyyy-MM-dd HH:mm:ss}" -f $o.Time)
  $lines += ("Record:  {0}" -f $(if($rid){$rid}else{'(n/a)'}))
  $lines += ("User:    {0}" -f $o.User)
  $lines += ("IP:      {0}" -f $o.IP)
  $lines += ("LT:      {0}" -f $o.LT)
  $lines += ("WS:      {0}" -f $o.WS)
  if ($o.Type -eq 4625) {
    $lines += ("Status:  {0}" -f $o.Status)
    $lines += ("Sub:     {0}" -f $o.Sub)
    $lines += ("Reason:  {0}" -f $o.Reason)
  }
  $lines += ('-'*72)
  if ($e) {
    try { $lines += ($e | Format-List * | Out-String).TrimEnd() } catch {}
    $lines += ''
    try { $lines += 'XML:'; $lines += (([xml]$e.ToXml()).OuterXml) } catch {}
  } else {
    $lines += 'Original event payload not available (RecordId lookup failed).'
  }
  Set-Content -Path $tmp -Value ($lines -join "`r`n") -Encoding UTF8
  try { Start-Process notepad.exe $tmp | Out-Null } catch { Write-Host ("Open failed: " + $_.Exception.Message) -ForegroundColor DarkRed }
}

function Open-GridForSelection(){
  try {
    if(-not $lastList -or $lastList.Count -eq 0){ $res = Show-LastDays -d $days; $lastList=$res.Items }
    $grid = $lastList |
      Select-Object Time,Type,User,IP,LT,WS,Status,Sub,Reason,Record |
      Out-GridView -Title 'neo_multiseat live monitor - select a row for details' -PassThru
    if ($grid) { Show-EventDetailsByObject $grid }
  } catch {
    Write-Host ("Grid not available: " + $_.Exception.Message) -ForegroundColor DarkYellow
    if ($lastList -and $lastList.Count -gt 0) { Show-EventDetailsByObject ($lastList | Select-Object -First 1) }
  }
}
function Show-LastDays([int]$d){
  if ($d -lt 1) { $d = 1 }
  try {
    $ev = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=$ids; StartTime=(Get-Date).AddDays(-$d)} -MaxEvents 10000 -ErrorAction SilentlyContinue
    $rows = @(); foreach($e in $ev){ $rows += (Parse-Event $e) }
    $rows = $rows | Sort-Object Time -Descending
    $filtered = @(); $seen = @{}
    foreach($r in $rows){
      if ($seen.ContainsKey([string]$r.Record)) { continue } else { $seen[[string]$r.Record] = 1 }
      if ($r.Type -eq 4740) { if ($showLock) { $filtered += $r }; continue }
      if ($rdpOnly) {
        if ($r.Type -eq 4624) { if ($r.LT -ne '10') { continue } }
        elseif ($r.Type -eq 4625) { if (@('10','3','7') -notcontains $r.LT) { continue } }
      }
      if ($r.Type -eq 4624 -and $showSuccess) { $filtered += $r; continue }
      if ($r.Type -eq 4625 -and $showFail) { $filtered += $r; continue }
    }
    if($filtered.Count -gt 0){ return [PSCustomObject]@{ LastRecord=[long]$filtered[0].Record; Items=$filtered } }
  } catch { Write-Host ("Error loading history: " + $_.Exception.Message) -ForegroundColor DarkRed }
  return [PSCustomObject]@{ LastRecord=$lastRecord; Items=@() }
}

function Refresh-List(){
  $res = Show-LastDays -d $days
  $script:lastRecord = [long]$res.LastRecord
  $script:lastList = $res.Items
}

Print-Status
$since = (Get-Date).AddSeconds(-3)
  while ($true) {
    while([Console]::KeyAvailable){
      $k=[Console]::ReadKey($true)
      if($k.Key -eq 'Q'){ return }
      if($k.Key -eq 'R'){ $rdpOnly = -not $rdpOnly; Print-Status; Refresh-List }
      if($k.Key -eq 'S'){ $showSuccess = -not $showSuccess; Print-Status; Refresh-List }
      if($k.Key -eq 'K'){ $showLock = -not $showLock; Print-Status; Refresh-List }
      if($k.Key -eq 'OemPlus' -or $k.KeyChar -eq '+'){ $days += 1; Print-Status; Refresh-List }
      if($k.Key -eq 'OemMinus' -or $k.KeyChar -eq '-') { if($days -gt 1){ $days -= 1 }; Print-Status; Refresh-List }
    if($k.Key -eq 'C'){ Clear-Host; Print-Status; Refresh-List }
    if($k.Key -eq 'L'){
        # On-demand listing: print current filtered items (newest first)
        try {
          if(-not $lastList){ $res = Show-LastDays -d $days; $lastRecord = [long]$res.LastRecord; $lastList=$res.Items }
          Clear-Host
          # Re-draw pinned header, then list below
          Print-Status
          Write-Host ''
          Write-Host ("Listing last {0} day(s) (filtered, newest first)." -f $days) -ForegroundColor Cyan
          $toShow = $lastList | Select-Object -First 200
          foreach($row in $toShow){ Print-Line $row }
          Write-Host ''
        } catch { Write-Host ("List failed: " + $_.Exception.Message) -ForegroundColor DarkRed }
      }
      if($k.Key -eq 'E'){
        try {
          if(-not $lastList){ $res = Show-LastDays -d $days; $lastList=$res.Items }
          $export = $lastList | Select-Object -First 24 | Select-Object Time,Type,User,IP,LT,WS,Status,Sub,Reason
          $out = Join-Path $PSScriptRoot ("live_monitor_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))
          $export | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
          Write-Host ("Exported to " + $out) -ForegroundColor Green
        } catch { Write-Host ("Export failed: " + $_.Exception.Message) -ForegroundColor DarkRed }
      }
      if($k.Key -eq 'G'){ Open-GridForSelection }
  }
  try {
    $ev = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=$ids; StartTime=$since} -ErrorAction SilentlyContinue
    $new = @(); foreach($e in $ev){ if([long]$e.RecordId -gt [long]$lastRecord){ $new += $e } }
    if ($new.Count -gt 0) {
      $parsed = $new | ForEach-Object { Parse-Event $_ } | Sort-Object Time
      foreach($r in $parsed){
        if ($r.Type -eq 4740) { if ($showLock) { Print-Line $r } }
        elseif ($r.Type -eq 4624) { if ($showSuccess -and (-not $rdpOnly -or $r.LT -eq '10')) { Print-Line $r } }
        elseif ($r.Type -eq 4625) { if ($showFail -and (-not $rdpOnly -or (@('10','3','7') -contains $r.LT))) { Print-Line $r } }
        if([long]$r.Record -gt [long]$lastRecord){ $lastRecord = [long]$r.Record }
      }
      $since = ($parsed[-1]).Time
    } else { $since = (Get-Date) }
  } catch { Write-Host ("Monitor error: " + $_.Exception.Message) -ForegroundColor DarkRed }
  Print-Status
  Start-Sleep -Milliseconds 500
}
'@
  Set-Content -Path $tmp -Value $script -Encoding UTF8
  $alist2 = @('-NoExit','-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File', $tmp)
  Start-Process -FilePath 'powershell.exe' -ArgumentList $alist2 -WindowStyle Normal | Out-Null
}

function Enforce-NLA-And-TLS {
  $preview = @("Enable NLA (UserAuthentication=1)", "Set SecurityLayer=2 (TLS)")
  $cli = @(
    'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 1 /f',
    'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v SecurityLayer /t REG_DWORD /d 2 /f'
  )
  Confirm-Apply -Title "Enforce NLA + TLS" -PreviewLines $preview -ManualCli $cli -Action {
    New-ItemProperty -Path $RdpKey -Name UserAuthentication -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $RdpKey -Name SecurityLayer     -PropertyType DWord -Value 2 -Force | Out-Null
  }
}

function Disable-NTLMv1 {
  $preview = @("Set LmCompatibilityLevel=5 (NTLMv2 only)")
  $cli = @('reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LmCompatibilityLevel /t REG_DWORD /d 5 /f')
  Confirm-Apply -Title "Disable NTLMv1 (use NTLMv2 only)" -PreviewLines $preview -ManualCli $cli -Action {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel' -PropertyType DWord -Value 5 -Force | Out-Null
  }
}

function Set-AccountLockoutPolicy {
  $preview = @("Lockout after 25 failures", "Lockout duration 60 minutes", "Reset counter after 60 minutes")
  $cli = @('net accounts /lockoutthreshold:25 /lockoutduration:60 /lockoutwindow:60')
  Confirm-Apply -Title "Account lockout policy" -PreviewLines $preview -ManualCli $cli -Action {
    $netexe = Join-Path $env:SystemRoot 'System32\net.exe'
    & $netexe accounts '/lockoutthreshold:25' '/lockoutduration:60' '/lockoutwindow:60' | Out-Null
  }
}

function Tailscale-Helper {
  $ts = Get-TailscaleStatus
  if ($ts.Adapter) {
    Write-Host ("Tailscale adapter detected: {0}. 100.x present: {1}" -f $ts.Adapter.Name, $(if($ts.Has100){'Yes'}else{'No'})) -ForegroundColor Green
  } else {
    Write-Host "Tailscale not detected." -ForegroundColor Yellow
    Write-Host "Install from: https://tailscale.com/download" -ForegroundColor Yellow
    Write-Host "After install, sign in, ensure you see a 100.x address; then enable Tailscale mode here." -ForegroundColor Yellow
  }
  Read-Host "Press ENTER to continue"
}

# Minimal totals (fast path ~instant)
function Show-RdpRecentTable {
  Write-Host ""
  Show-ImportantBanner -Text "Auth totals (~24h window, capped)" -Fg Black -Bg Yellow
  $c = Get-AuthCounts -Hours 24 -Cap 200
  Write-Host ("Success: {0}    Failures: {1}" -f $c.OK, $c.FAIL) -ForegroundColor Cyan
  Write-Host "Use [4] Live monitor for real-time detail (user/IP/reason + burst alerts)." -ForegroundColor DarkCyan
  Read-Host "Press ENTER to return"
}

# --- Account lockout status helpers -----------------------------------
function Get-AccountLockoutStatus {
  $status = [PSCustomObject]@{ Active=$false; Threshold=0; Duration=0; Window=0 }
  try {
    $out = & (Join-Path $env:SystemRoot 'System32\net.exe') accounts 2>$null
    if ($out) {
      foreach ($line in $out) {
        $l = $line.Trim()
        if ($l -match '(?i)lockout.*threshold.*?:\s*(\d+)') { $status.Threshold = [int]$Matches[1] }
        elseif ($l -match '(?i)lockout.*duration.*?:\s*(\d+)') { $status.Duration = [int]$Matches[1] }
        elseif ($l -match '(?i)lockout.*window.*?:\s*(\d+)') { $status.Window = [int]$Matches[1] }
      }
      if ($status.Threshold -gt 0) { $status.Active = $true }
    }
  } catch {}
  return $status
}


function Show-AccountLockoutStatus {
  $s = Get-AccountLockoutStatus
  if ($s.Active) {
    Write-Host ("Lockout policy: Active  threshold={0}  duration={1}m  window={2}m" -f $s.Threshold,$s.Duration,$s.Window) -ForegroundColor Green
  } else {
    Write-Host "Lockout policy: Not set (threshold=0)" -ForegroundColor Red
  }
}

function Get-DoublePromptStatus {
  $nla = (Get-ItemProperty -Path $RdpKey -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
  $p1  = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fPromptForPassword' -ErrorAction SilentlyContinue).fPromptForPassword
  $p2  = (Get-ItemProperty -Path $RdpKey -Name 'fPromptForPassword' -ErrorAction SilentlyContinue).fPromptForPassword
  return ( ($nla -eq 1) -and ( ($p1 -eq 1) -or ($p2 -eq 1) ) )
}

function Show-DoublePromptStatus {
  $on = Get-DoublePromptStatus
  if ($on) { Write-Host 'Double Prompt: Enabled' -ForegroundColor Green } else { Write-Host 'Double Prompt: Disabled' -ForegroundColor DarkGray }
}

# --- Inline live logon monitor (4624/4625/4740) -----------------------
function Get-AuditLogonStatus {
  $succ = $false; $fail = $false
  try {
    $out = & auditpol.exe /get /subcategory:"Logon" 2>$null
    if ($out) {
      foreach($line in $out){
        if ($line -match '(?i)Success\s*:\s*Enable') { $succ = $true }
        if ($line -match '(?i)Failure\s*:\s*Enable') { $fail = $true }
      }
    }
  } catch {}
  [PSCustomObject]@{ Success=$succ; Failure=$fail }
}
function Start-LiveLogonMonitor {
  Write-Host ""; Show-ImportantBanner -Text "Live logon monitor. Q=quit  R=RDP-only  F=cycle(both/fail/succ)  S=succ  K=lock  L=list +/-=days +/-  C=clear  E=export" -Fg Black -Bg Yellow
  # Ensure audit policy for Logon success/failure
  try { & auditpol.exe /set /subcategory:"Logon" /success:enable /failure:enable | Out-Null } catch {}
  $audit = Get-AuditLogonStatus
  Write-Host ("Audit policy: Success={0}  Failure={1}" -f $(if($audit.Success){'On'}else{'Off'}), $(if($audit.Failure){'On'}else{'Off'})) -ForegroundColor DarkCyan

  $rdpOnly = $true
  $showSuccess = $true
  $showFail = $true
  $showLock = $true
  $days = 4
  $inp = Read-Host 'Days to list initially (ENTER=4)'
  if ($inp -match '^[0-9]+$' -and [int]$inp -ge 1) { $days = [int]$inp }
  $ids = 4624,4625,4740
  $lastRecord = 0L

  function Parse-Event([System.Diagnostics.Eventing.Reader.EventRecord]$e){
    $xml = [xml]$e.ToXml()
    $d = @{}
    foreach($x in $xml.Event.EventData.Data){ $d[$x.Name] = $x.'#text' }
    $type = $e.Id
    $user = $d['TargetUserName']
    $ip   = if($d.ContainsKey('IpAddress') -and $d['IpAddress']) { $d['IpAddress'] } else { '-' }
    $lt   = $d['LogonType']
    $ws   = $d['WorkstationName']
    $st   = $d['Status']
    $sub  = $d['SubStatus']
    $reason = if($type -eq 4625){ Get-4625Reason -Status $st -Sub $sub } else { '' }
    [PSCustomObject]@{ Type=$type; Time=$e.TimeCreated; Record=$e.RecordId; User=$user; IP=$ip; LT=$lt; WS=$ws; Status=$st; Sub=$sub; Reason=$reason }
  }

  function Print-Line($o){
    if ($o.Type -eq 4624) {
      if (-not $showSuccess) { return }
      if ($rdpOnly -and $o.LT -ne '10') { return }
      Write-Host ("[{0:yyyy-MM-dd HH:mm:ss}] SUCCESS {1}@{2} LT={3} WS={4}" -f $o.Time, $o.User, $o.IP, $o.LT, $o.WS) -ForegroundColor Green
    } elseif ($o.Type -eq 4625) {
      if (-not $showFail) { return }
      if ($rdpOnly -and $o.LT -ne '10') { return }
      Write-Host ("[{0:yyyy-MM-dd HH:mm:ss}] FAIL    {1}@{2} {3} (Status {4}/{5}) LT={6} WS={7}" -f $o.Time, $o.User, $o.IP, $o.Reason, $o.Status, $o.Sub, $o.LT, $o.WS) -ForegroundColor Red
    } else {
      if (-not $showLock) { return }
      Write-Host ("[{0:yyyy-MM-dd HH:mm:ss}] LOCKOUT user={1} caller={2}" -f $o.Time, $o.User, $o.WS) -ForegroundColor Yellow
    }
  }

  function Show-LastDays([int]$d){
    if ($d -lt 1) { $d = 1 }
    try {
      $ev = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=$ids; StartTime=(Get-Date).AddDays(-$d)} -MaxEvents 10000 -ErrorAction SilentlyContinue
      $rows = @()
      foreach($e in $ev){ $rows += (Parse-Event $e) }
      $rows = $rows | Sort-Object Time -Descending
      $filtered = @()
      foreach($r in $rows){
        if ($r.Type -eq 4740) { if ($showLock) { $filtered += $r }; continue }
        if ($rdpOnly -and $r.LT -ne '10') { continue }
        if ($r.Type -eq 4624 -and $showSuccess) { $filtered += $r; continue }
        if ($r.Type -eq 4625 -and $showFail) { $filtered += $r; continue }
      }
      Write-Host ""; Write-Host ("Last {0} day(s): showing {1} events (newest first)" -f $d, $filtered.Count) -ForegroundColor Cyan
      foreach($r in $filtered){ Print-Line $r }
      if($filtered.Count -gt 0){ return [PSCustomObject]@{ LastRecord=[long]$filtered[0].Record; Items=$filtered } }
    } catch { Write-Host ("Error loading history: " + $_.Exception.Message) -ForegroundColor DarkRed }
    return [PSCustomObject]@{ LastRecord=$lastRecord; Items=@() }
  }

  function Print-Status() {
    Write-Host ("Filters: RDP-only={0}  Success={1}  Fail={2}  Lockout={3}  Days={4}" -f `
      $(if($rdpOnly){'On'}else{'Off'}), $(if($showSuccess){'On'}else{'Off'}), $(if($showFail){'On'}else{'Off'}), $(if($showLock){'On'}else{'Off'}), $days) -ForegroundColor DarkCyan
  }
  function Cycle-ViewMode() {
    if ($showSuccess -and $showFail) {
      $showSuccess = $false; $showFail = $true; return
    }
    if (-not $showSuccess -and $showFail) {
      $showSuccess = $true; $showFail = $false; return
    }
    # success-only or any other state -> both
    $showSuccess = $true; $showFail = $true
  }
  Print-Status
  $res = Show-LastDays -d $days; $lastRecord = [long]$res.LastRecord; $lastList = $res.Items
  $since = (Get-Date).AddSeconds(-3)
  while ($true) {
    while([Console]::KeyAvailable){
      $k=[Console]::ReadKey($true)
      if($k.Key -eq 'Q'){ return }
      if($k.Key -eq 'R'){ $rdpOnly = -not $rdpOnly; Print-Status }
      if($k.Key -eq 'F'){ Cycle-ViewMode; Print-Status }
      if($k.Key -eq 'S'){ $showSuccess = -not $showSuccess; Print-Status }
      if($k.Key -eq 'K'){ $showLock = -not $showLock; Print-Status }
      if($k.Key -eq 'OemPlus' -or $k.KeyChar -eq '+'){ $days += 1; Print-Status }
      if($k.Key -eq 'OemMinus' -or $k.KeyChar -eq '-') { if($days -gt 1){ $days -= 1 }; Print-Status }
      if($k.Key -eq 'C'){ Clear-Host; Show-ImportantBanner -Text "Live logon monitor. Q=quit  R=RDP-only  S=succ  F=fail  K=lock  L=list +/-=days +/-  C=clear  E=export" -Fg Black -Bg Yellow; $audit = Get-AuditLogonStatus; Write-Host ("Audit policy: Success={0}  Failure={1}" -f $(if($audit.Success){'On'}else{'Off'}), $(if($audit.Failure){'On'}else{'Off'})) -ForegroundColor DarkCyan; Print-Status; $res = Show-LastDays -d $days; $lastRecord = [long]$res.LastRecord; $lastList=$res.Items }
      if($k.Key -eq 'L'){ $res = Show-LastDays -d $days; $lastRecord = [long]$res.LastRecord; $lastList=$res.Items }
      if($k.Key -eq 'E'){ try { if(-not $lastList){ $res = Show-LastDays -d $days; $lastList=$res.Items } ; $export = $lastList | Select-Object -First 24 | Select-Object Time,Type,User,IP,LT,WS,Status,Sub,Reason ; $csv = Join-Path $script:LogDir ("live_monitor_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date)) ; $export | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8 ; Write-Host ("Exported to " + $csv) -ForegroundColor Green } catch { Write-Host ("Export failed: " + $_.Exception.Message) -ForegroundColor DarkRed } }
    }
    try {
      $ev = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=$ids; StartTime=$since} -ErrorAction SilentlyContinue
      $new = @(); foreach($e in $ev){ if([long]$e.RecordId -gt [long]$lastRecord){ $new += $e } }
      if ($new.Count -gt 0) {
        $parsed = $new | ForEach-Object { Parse-Event $_ }
        $parsed = $parsed | Sort-Object Time
        foreach($r in $parsed){ 
          if ($r.Type -eq 4740) { if ($showLock) { Print-Line $r } }
          elseif ($r.Type -eq 4624) { if ($showSuccess -and (-not $rdpOnly -or $r.LT -eq '10')) { Print-Line $r } }
          elseif ($r.Type -eq 4625) { if ($showFail -and (-not $rdpOnly -or (@('10','3','7') -contains $r.LT))) { Print-Line $r } }
          if([long]$r.Record -gt [long]$lastRecord){ $lastRecord = [long]$r.Record }
        }
        $since = ($parsed[-1]).Time
      } else {
        $since = (Get-Date)
      }
    } catch { Write-Host ("Monitor error: " + $_.Exception.Message) -ForegroundColor DarkRed }
    Start-Sleep -Milliseconds 700
  }
}

# --- Double-prompt (NLA + always prompt for password on host) ---------
function Toggle-DoublePromptAuth {
  $preview = @(
    "Enable NLA (UserAuthentication=1)",
    "Always prompt for password upon connection (host GUI)",
    "Apply to policy + live RDP-Tcp"
  )
  $cli = @(
    'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 1 /f',
    'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fPromptForPassword /t REG_DWORD /d 1 /f',
    'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v fPromptForPassword /t REG_DWORD /d 1 /f'
  )
  Confirm-Apply -Title "Enable Double Prompt (NLA + host password)" -PreviewLines $preview -ManualCli $cli -Action {
    New-ItemProperty -Path $RdpKey -Name UserAuthentication -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fPromptForPassword' -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $RdpKey -Name 'fPromptForPassword' -PropertyType DWord -Value 1 -Force | Out-Null
    # Read-back status and print
    $nla = (Get-ItemProperty -Path $RdpKey -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
    $p1  = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fPromptForPassword' -ErrorAction SilentlyContinue).fPromptForPassword
    $p2  = (Get-ItemProperty -Path $RdpKey -Name 'fPromptForPassword' -ErrorAction SilentlyContinue).fPromptForPassword
    $on = ($nla -eq 1) -and (($p1 -eq 1) -or ($p2 -eq 1))
    if ($on) { Write-Host 'Double Prompt: Enabled' -ForegroundColor Green } else { Write-Host 'Double Prompt: Not fully enabled' -ForegroundColor Red }
  }
}

function NetModes-Menu {
  # Initialize once to avoid slow repeated scans
  Align-NeoFirewallRules
  Disable-BaseRdpFirewallRules
  Reconcile-NetConfig
  Sync-BlockRules
  Refresh-NetModesCache -Force

  while ($true) {
    Start-MonitorIfTriggered
    Show-NetModesStatusCached
    Write-Host ''
    Write-Host '[1] Toggle LAN On/Off'
    Write-Host '[2] Toggle WAN On/Off'
    Write-Host '[3] Toggle Tailscale On/Off'
    Write-Host '[4] Edit LAN allowlist (CIDR/IPs, comma-separated)'
    Write-Host '[5] Edit WAN allowlist (CIDR/IPs, comma-separated)'
    Write-Host '[R] Refresh status'
    Write-Host '[A] Advanced security (NLA/TLS, NTLMv1, Lockout, Monitor, Tailscale helper, Recent totals)'
    Write-Host '[B] Back'
    $ch = Read-Host 'Choose'

    switch -Regex ($ch) {
      '^(?i)1$' {
        Align-NeoFirewallRules
        $target = -not ((Get-NetFirewallRule -DisplayName $RuleLAN).Enabled -eq 'True')
        $prev = @("Set $RuleLAN Enabled = $target")
        Confirm-Apply -Title "Toggle LAN" -PreviewLines $prev -Action { Toggle-Mode -Mode LAN -Enabled:$target; Sync-BlockRules }
        continue
      }
      '^(?i)2$' {
        Align-NeoFirewallRules
        $target = -not ((Get-NetFirewallRule -DisplayName $RuleWAN).Enabled -eq 'True')
        $prev = @("Set $RuleWAN Enabled = $target")
        if ($target -and -not (Load-NetConfig).WAN.Allowlist.Count) {
          Write-Host 'WAN allowlist empty. Enter CIDR/IPs (e.g., 203.0.113.0/24, 198.51.100.42/32).' -ForegroundColor Yellow
          $cidrs = Input-CIDRs -Prompt 'WAN allowlist'
          if (-not $cidrs.Count) { Write-Host 'Cancelled.' ; continue }
          Confirm-Apply -Title "Set WAN allowlist" -PreviewLines @("WAN allowlist -> " + ($cidrs -join ', ')) -Action { Set-WAN-Allowlist -Cidrs $cidrs }
        } elseif ($target) {
          $cfg = Load-NetConfig
          if (-not (Test-WAN-AllowlistSafe $cfg.WAN.Allowlist)) {
            Write-Host 'Refusing to enable WAN: allowlist contains Any/0.0.0.0/0 or is empty.' -ForegroundColor Red
            Write-Host 'Edit the WAN allowlist (option 5) to specific CIDRs/IPs.' -ForegroundColor Yellow
            continue
          }
        }
        Confirm-Apply -Title "Toggle WAN" -PreviewLines $prev -Action { Toggle-Mode -Mode WAN -Enabled:$target; Sync-BlockRules }
        continue
      }
      '^(?i)3$' {
        Align-NeoFirewallRules
        $target = -not ((Get-NetFirewallRule -DisplayName $RuleTS).Enabled -eq 'True')
        $prev = @("Set $RuleTS Enabled = $target")
        Confirm-Apply -Title "Toggle Tailscale" -PreviewLines $prev -Action { Toggle-Mode -Mode TS -Enabled:$target; Sync-BlockRules }
        continue
      }
      '^(?i)4$' {
        $cidrs = Input-CIDRs -Prompt 'LAN allowlist (default LocalSubnet)'; if (-not $cidrs.Count) { continue }
        Confirm-Apply -Title "Set LAN allowlist" -PreviewLines @("LAN allowlist -> " + ($cidrs -join ', ')) -Action { Set-LAN-Allowlist -Cidrs $cidrs }
        continue
      }
      '^(?i)5$' {
        $cidrs = Input-CIDRs -Prompt 'WAN allowlist (CIDR/IPs)'; if (-not $cidrs.Count) { continue }
        Confirm-Apply -Title "Set WAN allowlist" -PreviewLines @("WAN allowlist -> " + ($cidrs -join ', ')) -Action { Set-WAN-Allowlist -Cidrs $cidrs }
        continue
      }
      '^(?i)R$' { Refresh-NetModesCache -Force; continue }
      '^(?i)A$' {
        while ($true) {
          Write-Host ''
          Write-Host '=== Advanced security ===' -ForegroundColor Cyan
          Show-AccountLockoutStatus
          Show-DoublePromptStatus
          Write-Host '[1] Enforce NLA + TLS (recommended for WAN)'
          Write-Host '[2] Disable NTLMv1 (NTLMv2 only)'
          Write-Host '[3] Set Account Lockout (25 fails / 60min)'
          Write-Host '[4] Live monitor (inline: success/fail/lockout)'
          Write-Host '[5] Tailscale helper (detect/install hints)'
          Write-Host '[6] Show auth totals (~24h)'
          # Removed by request to simplify advanced menu
          Write-Host '[10] Enable Double Prompt (NLA + host password)'
          Write-Host '[B] Back'
          $ax = Read-Host 'Choose'
          switch -Regex ($ax) {
            '^(?i)1$' { Enforce-NLA-And-TLS; continue }
            '^(?i)2$' { Disable-NTLMv1; continue }
            '^(?i)3$' { Set-AccountLockoutPolicy; Show-AccountLockoutStatus; continue }
            '^(?i)4$' { Start-LiveMonitorWindow; continue }
            '^(?i)5$' { Tailscale-Helper; continue }
            '^(?i)6$' { Show-RdpRecentTable; continue }
            # options 7/8/9 removed
            '^(?i)10$' { Toggle-DoublePromptAuth; continue }
            '^(?i)B$' { break }
            default   { Write-Host 'Invalid.'; continue }
          }
          break
        }
        continue
      }
      '^(?i)B$' { return }
      default { Write-Host 'Invalid.'; continue }
    }
  }
}

# --- Flow --------------------------------------------------------------
function Neo-InstallFlow {
  param([string]$TargetUser)
  Write-Host "=== Installing/Configuring neo_multiseat for account: $TargetUser ==="
  New-NeoRdpFile -TargetUser $TargetUser
  Install-Or-Update-RDPWrapper

  $ok = Enable-RDP-And-Firewall
  if (-not $ok) {
    Open-RDPConf-ShortGuidance
    Show-ImportantBanner -Text "RDP services did NOT start." -Fg White -Bg DarkRed
    $ans = Read-Host "Run the FIX now? (Y/N)"
    if ($ans -match '^(?i)Y$') {
      Fix-RDP-Service
      Install-Or-Update-RDPWrapper
      $ok = Enable-RDP-And-Firewall
      if (-not $ok) {
        Show-ImportantBanner -Text "Still failed to start RDP services. Investigate manually or run FIX again." -Fg White -Bg DarkRed
        Open-RDPConf-ShortGuidance
        Show-Credits
        return
      }
    } else {
      Show-ImportantBanner -Text "You chose not to run FIX now. Use menu option 2 (Fix RDP) and re-run option 1 later." -Fg Black -Bg Yellow
      Show-Credits
      return
    }
  }

  Open-RDPConf-And-Guide
  Write-Host "`nAll steps completed. Please reboot your PC manually once before testing concurrent RDP." -ForegroundColor Yellow
  Show-Credits
}

# --- Menu --------------------------------------------------------------
function Show-StartMenu {
  Write-Host ""
  Write-Host "======================================="
  Write-Host " neo_multiseat (RDP Wrapper)"
  Write-Host "======================================="
  Start-MonitorIfTriggered
  Show-HealthStrip
  Write-Host '[1] Install/Configure neo_multiseat (user + RDP Wrapper)'
  Write-Host '[2] Fix RDP services (reset termsrv.dll, uninstall wrapper)'
  Write-Host '[3] Delete a user'
  Write-Host '[4] Open RDP Wrapper folder'
  Write-Host '[5] Network access modes (LAN / WAN / Tailscale)'
  Write-Host '[Q] Quit'
}

function Main-Menu {
  do {
    Show-StartMenu
    $choice = Read-Host "Choose an option"
    switch -Regex ($choice) {
      '^(?i)1$' {
        $userName = Ensure-User
        Neo-InstallFlow -TargetUser $userName
        continue
      }
      '^(?i)2$' { Fix-RDP-Service; Show-Credits; continue }
      '^(?i)3$' { Remove-neoUser; continue }
      '^(?i)4$' { Open-RDP-Folder; continue }
      '^(?i)5$' { NetModes-Menu; continue }
      '^(?i)(Q|Quit|E|Exit)$' { return }
      default { Write-Warning "Invalid selection. Try again."; Start-Sleep -Milliseconds 300; continue }
    }
  } while ($true)
}

# Ensure firewall rules exist and JSON matches OS before entering main loop
Ensure-NeoFirewallRules
Reconcile-NetConfig

try {
  Main-Menu
} finally {
  Write-Host "`nNote: A reboot is recommended after installation or fixes. Please reboot manually." -ForegroundColor Yellow
  Show-Credits
  Write-Host ("`nTranscript saved at: {0}" -f $LogFile)
  Read-Host "Press ENTER to close this window"
  Stop-Transcript | Out-Null
}
 
