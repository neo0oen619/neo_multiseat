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
$script:LogDir  = Join-Path $PSScriptRoot "."
$script:LogFile = Join-Path $LogDir ("neo_multiseat_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Force | Out-Null
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
}

# --- Paths / constants -------------------------------------------------
$ConfigPath = Join-Path $PSScriptRoot 'neo_multiseat.net.json'
$RuleLAN    = 'neo_multiseat_RDP_LAN'
$RuleWAN    = 'neo_multiseat_RDP_WAN'
$RuleTS     = 'neo_multiseat_RDP_Tailscale'
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

  $statusLine = ("STATUS  TermService:{0}  Port:{1}  Wrapper:{2}  INI:{3}  NLA:{4}  TLS:{5}  LAN:{6}  WAN:{7}  TS:{8}  Auth OK:{9} FAIL:{10} (~24h)" -f `
    $h.TermService, $h.Port, $h.Wrapper, $h.INI, $h.NLA, $h.TLSMode, $lanLabel, $wanLabel, $tsLabel, $h.OK, $h.FAIL)

  Write-Host ""
  Write-Host $statusLine -ForegroundColor DarkGreen
}

# --- RDP file helper (exact username filename) ------------------------
function New-NeoRdpFile {
  param([Parameter(Mandatory=$true)][string]$TargetUser)
  $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
         Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
         Select-Object -ExpandProperty IPAddress
  $primary = if ($ips) { $ips | Select-Object -First 1 } else { $env:COMPUTERNAME }

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
    [System.IO.File]::WriteAllText($outScript, $content, [System.Text.ASCIIEncoding]::new())
    [System.IO.File]::WriteAllText($outPublic, $content, [System.Text.ASCIIEncoding]::new())
    Write-Host "Created RDP file(s):" -ForegroundColor Green
    Write-Host "  $outScript"
    Write-Host "  $outPublic"
  } catch {
    Write-Warning "Could not write .RDP file(s): $($_.Exception.Message)"
  }
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
    "Firewall: enable built-in Remote Desktop group"
  )
  $gui = "Settings > System > Remote Desktop > Enable"
  $cli = @(
    'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f',
    'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f',
    'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f',
    'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxInstanceCount /t REG_DWORD /d 999999 /f',
    'netsh advfirewall firewall set rule group="remote desktop" new enable=yes'
  )
  Confirm-Apply -Title "Enable RDP & policy keys" -PreviewLines $preview -ManualGui $gui -ManualCli $cli -Action {
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxInstanceCount /t REG_DWORD /d 999999 /f | Out-Null
    try { Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop | Out-Null }
    catch { netsh advfirewall firewall set rule group="remote desktop" new enable=yes | Out-Null }
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
    Security = @{ NLA = $false; NTLMv1Disabled = $false; LockoutPolicy = $false }
  }
}
function Save-NetConfig($cfg) { $cfg | ConvertTo-Json -Depth 6 | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force }

function Ensure-NeoFirewallRules {
  if (-not (Get-NetFirewallRule -DisplayName $RuleLAN -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $RuleLAN -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow `
      -RemoteAddress LocalSubnet -Service TermService -Profile Domain,Private -Enabled False | Out-Null
  }
  if (-not (Get-NetFirewallRule -DisplayName $RuleWAN -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $RuleWAN -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow `
      -RemoteAddress "0.0.0.0/32" -Service TermService -Profile Any -Enabled False | Out-Null
  }
  if (-not (Get-NetFirewallRule -DisplayName $RuleTS -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $RuleTS -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow `
      -InterfaceAlias "Tailscale*" -Service TermService -Profile Any -Enabled False | Out-Null
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
  Reconcile-NetConfig
  $cfg = Load-NetConfig

  $lanR = Get-NetFirewallRule -DisplayName $RuleLAN -ErrorAction SilentlyContinue
  $wanR = Get-NetFirewallRule -DisplayName $RuleWAN -ErrorAction SilentlyContinue
  $tsR  = Get-NetFirewallRule -DisplayName $RuleTS  -ErrorAction SilentlyContinue

  $lanEnabled = ($lanR -and $lanR.Enabled -eq 'True')
  $wanEnabled = ($wanR -and $wanR.Enabled -eq 'True')
  $tsEnabled  = ($tsR  -and $tsR.Enabled  -eq 'True')

  $lanAddr = $null
  $wanAddr = $null
  try { $lanAddr = (Get-NetFirewallRule -DisplayName $RuleLAN | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue).RemoteAddress } catch {}
  try { $wanAddr = (Get-NetFirewallRule -DisplayName $RuleWAN | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue).RemoteAddress } catch {}

  $lanAllow = if ($lanAddr) { $lanAddr -join ', ' } else { 'LocalSubnet' }
  $wanAllow = if ($wanAddr) { $wanAddr -join ', ' } else { '<empty>' }

  $lanLabel = if ($lanEnabled) { "On (working)" } else { "Off (disconnected)" }
  $wanLabel = if ($wanEnabled) { "On (working)" } else { "Off (disconnected)" }

  $lanColor = if ($lanEnabled) { 'Green' } else { 'DarkGray' }
  $wanColor = if ($wanEnabled) { 'Green' } else { 'DarkGray' }

  $ts = Get-TailscaleStatus
  $tsAdapterName = if ($ts.Adapter) { $ts.Adapter.Name } else { 'not detected' }
  $tsWorking = $tsEnabled -and $ts.Adapter -and $ts.Has100
  $tsLabel = if ($tsEnabled) { if ($tsWorking) { 'On (working)' } else { 'On (disconnected)' } } else { 'Off (disconnected)' }
  $tsColor = if ($tsEnabled -and $tsWorking) { 'Green' } else { 'DarkGray' }

  Write-Host ""
  Write-Host "=== Network access modes ===" -ForegroundColor Cyan
  Write-Host ("LAN:       {0}    allowlist: {1}" -f $lanLabel, $lanAllow) -ForegroundColor $lanColor
  Write-Host ("WAN:       {0}    allowlist: {1}" -f $wanLabel, $wanAllow) -ForegroundColor $wanColor
  Write-Host ("Tailscale: {0}    adapter: {1}, 100.x: {2}" -f $tsLabel, $tsAdapterName, $(if($ts.Has100){'Yes'}else{'No'})) -ForegroundColor $tsColor
}

function Set-WAN-Allowlist { param([string[]]$Cidrs)
  if (-not $Cidrs -or -not $Cidrs.Count) { throw "WAN allowlist cannot be empty." }
  Set-NetFirewallRule -DisplayName $RuleWAN | Set-NetFirewallAddressFilter -RemoteAddress ($Cidrs -join ",") | Out-Null
  $cfg = Load-NetConfig; $cfg.WAN.Allowlist = $Cidrs; Save-NetConfig $cfg
}
function Set-LAN-Allowlist { param([string[]]$Cidrs)
  if (-not $Cidrs -or -not $Cidrs.Count) { throw "LAN allowlist cannot be empty." }
  Set-NetFirewallRule -DisplayName $RuleLAN | Set-NetFirewallAddressFilter -RemoteAddress ($Cidrs -join ",") | Out-Null
  $cfg = Load-NetConfig; $cfg.LAN.Allowlist = $Cidrs; Save-NetConfig $cfg
}

function Toggle-Mode {
  param([ValidateSet('LAN','WAN','TS')][string]$Mode, [bool]$Enabled)
  $name = switch($Mode){ 'LAN'{$RuleLAN} 'WAN'{$RuleWAN} 'TS'{$RuleTS} }
  if ($Enabled) { Enable-NetFirewallRule -DisplayName $name | Out-Null } else { Disable-NetFirewallRule -DisplayName $name | Out-Null }
  $cfg = Load-NetConfig
  switch($Mode){ 'LAN' { $cfg.LAN.Enabled = $Enabled } 'WAN' { $cfg.WAN.Enabled = $Enabled } 'TS' { $cfg.TS.Enabled = $Enabled } }
  Save-NetConfig $cfg
}

function Input-CIDRs { param([string]$Prompt)
  $raw = Read-Host $Prompt
  $arr = @()
  foreach ($p in ($raw -split ',')) { $t = $p.Trim(); if ($t) { $arr += $t } }
  return $arr
}

# Live monitor and security tools --------------------------------------
function Get-4625Reason { param([string]$Status,[string]$Sub)
  $s = ($Status|ToUpper); $u = ($Sub|ToUpper)
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
  Show-ImportantBanner -Text "Brute-force monitor (Security 4625 / 4740). Press Q to quit." -Fg Black -Bg Yellow
  $since = (Get-Date).AddSeconds(-5)

  $windowSec = 60
  $burstThreshold = 5
  $seen = @{} # ip -> [DateTime[]]

  while ($true) {
    while ([Console]::KeyAvailable) {
      $k = [Console]::ReadKey($true)
      if ($k.Key -eq 'Q') { return }
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
          $lt   = $data['LogonType']
          $st   = $data['Status']
          $sub  = $data['SubStatus']
          $reason = Get-4625Reason -Status $st -Sub $sub

          if ($ip -and $ip -ne '-' -and $ip -ne '::1') {
            if (-not $seen.ContainsKey($ip)) { $seen[$ip] = New-Object System.Collections.ArrayList }
            [void]$seen[$ip].Add($e.TimeCreated)
            $cut = (Get-Date).AddSeconds(-$windowSec)
            $toKeep = New-Object System.Collections.ArrayList
            foreach ($t in $seen[$ip]) { if ($t -gt $cut) { [void]$toKeep.Add($t) } }
            $seen[$ip] = $toKeep
            $count = $seen[$ip].Count
            if ($count -ge $burstThreshold) {
              try { [Console]::Beep(900,180) } catch {}
              Write-Host ("*** BURST {0} failures in {1}s from {2} ***" -f $count,$windowSec,$ip) -ForegroundColor Red
            }
          }

          Write-Host ("[{0:HH:mm:ss}] 4625 {1}@{2}  {3}  (Status {4}/{5})  LT={6}  WS={7}" `
            -f $e.TimeCreated, $user, $ip, $reason, $st, $sub, $lt, $work) -ForegroundColor Red
        } catch {
          Write-Host ("Monitor decode error: " + $_.Exception.Message) -ForegroundColor DarkRed
        }
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
          Write-Host ("[{0:HH:mm:ss}] 4740 LOCKOUT  user={1}  caller={2}" -f $e.TimeCreated, $tuser, $caller) -ForegroundColor Yellow
        } catch {
          Write-Host ("Monitor decode error (4740): " + $_.Exception.Message) -ForegroundColor DarkRed
        }
      }

      $since = Get-Date
    } catch {
      Write-Host ("Monitor error: " + $_.Exception.Message) -ForegroundColor DarkRed
    }
    Start-Sleep -Milliseconds 800
  }
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

function NetModes-Menu {
  Ensure-NeoFirewallRules
  Reconcile-NetConfig

  while ($true) {
    Show-NetModesStatus
    Write-Host ''
    Write-Host '[1] Toggle LAN On/Off'
    Write-Host '[2] Toggle WAN On/Off'
    Write-Host '[3] Toggle Tailscale On/Off'
    Write-Host '[4] Edit LAN allowlist (CIDR/IPs, comma-separated)'
    Write-Host '[5] Edit WAN allowlist (CIDR/IPs, comma-separated)'
    Write-Host '[A] Advanced security (NLA/TLS, NTLMv1, Lockout, Monitor, Tailscale helper, Recent totals)'
    Write-Host '[B] Back'
    $ch = Read-Host 'Choose'

    switch -Regex ($ch) {
      '^(?i)1$' {
        $target = -not ((Get-NetFirewallRule -DisplayName $RuleLAN).Enabled -eq 'True')
        $prev = @("Set $RuleLAN Enabled = $target")
        Confirm-Apply -Title "Toggle LAN" -PreviewLines $prev -Action { Toggle-Mode -Mode LAN -Enabled:$target }
        continue
      }
      '^(?i)2$' {
        $target = -not ((Get-NetFirewallRule -DisplayName $RuleWAN).Enabled -eq 'True')
        $prev = @("Set $RuleWAN Enabled = $target")
        if ($target -and -not (Load-NetConfig).WAN.Allowlist.Count) {
          Write-Host 'WAN allowlist empty. Enter CIDR/IPs (e.g., 203.0.113.0/24, 198.51.100.42/32).' -ForegroundColor Yellow
          $cidrs = Input-CIDRs -Prompt 'WAN allowlist'
          if (-not $cidrs.Count) { Write-Host 'Cancelled.' ; continue }
          Confirm-Apply -Title "Set WAN allowlist" -PreviewLines @("WAN allowlist -> " + ($cidrs -join ', ')) -Action { Set-WAN-Allowlist -Cidrs $cidrs }
        }
        Confirm-Apply -Title "Toggle WAN" -PreviewLines $prev -Action { Toggle-Mode -Mode WAN -Enabled:$target }
        continue
      }
      '^(?i)3$' {
        $target = -not ((Get-NetFirewallRule -DisplayName $RuleTS).Enabled -eq 'True')
        $prev = @("Set $RuleTS Enabled = $target")
        Confirm-Apply -Title "Toggle Tailscale" -PreviewLines $prev -Action { Toggle-Mode -Mode TS -Enabled:$target }
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
      '^(?i)A$' {
        while ($true) {
          Write-Host ''
          Write-Host '=== Advanced security ===' -ForegroundColor Cyan
          Write-Host '[1] Enforce NLA + TLS (recommended for WAN)'
          Write-Host '[2] Disable NTLMv1 (NTLMv2 only)'
          Write-Host '[3] Set Account Lockout (25 fails / 60min)'
          Write-Host '[4] Live monitor: failed logons (4625/4740) [press Q to quit]'
          Write-Host '[5] Tailscale helper (detect/install hints)'
          Write-Host '[6] Show auth totals (~24h)'
          Write-Host '[B] Back'
          $ax = Read-Host 'Choose'
          switch -Regex ($ax) {
            '^(?i)1$' { Enforce-NLA-And-TLS; continue }
            '^(?i)2$' { Disable-NTLMv1; continue }
            '^(?i)3$' { Set-AccountLockoutPolicy; continue }
            '^(?i)4$' { Start-BruteforceMonitor; continue }
            '^(?i)5$' { Tailscale-Helper; continue }
            '^(?i)6$' { Show-RdpRecentTable; continue }
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
