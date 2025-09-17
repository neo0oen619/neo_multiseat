# Require admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Error "Please run PowerShell as Administrator." ; exit 1
}

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

$script:LogDir  = Join-Path $PSScriptRoot "."
$script:LogFile = Join-Path $LogDir ("SetupSeat2_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Force | Out-Null
Write-Host "Logging to $LogFile`n"

# --- Upstream download locations (fixed) -------------------------------
$DL = @{
  RDPWrapZip = 'https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip'     # official release zip
  AutoZip    = 'https://github.com/asmtron/rdpwrap/raw/master/autoupdate_v1.2.zip'                  # autoupdate v1.2
}
# ----------------------------------------------------------------------

# --- Visual helpers ----------------------------------------------------
$script:Esc = [char]27
$script:CreditsShown = $false

function Show-ImportantBanner {
  param([string]$Text, [ConsoleColor]$Fg='Black', [ConsoleColor]$Bg='Yellow')
  $line = ('=' * 72)
  Write-Host $line -ForegroundColor $Fg -BackgroundColor $Bg
  $boldStart = "$Esc[1m"; $boldEnd = "$Esc[22m"
  Write-Host ("{0}{1}{2}" -f $boldStart, ("  " + $Text), $boldEnd) -ForegroundColor $Fg -BackgroundColor $Bg
  Write-Host $line -ForegroundColor $Fg -BackgroundColor $Bg
}

function Credit-Banner-Begin {
  Show-ImportantBanner -Text "Binaries from stascorp; autoupdate by asmtron" -Fg Black -Bg Cyan
  Write-Host "Original project by Stas'M; autoupdate maintained by asmtron." -ForegroundColor DarkGray
}
function Show-PurplePulse { param([string]$Text)
  $esc = $script:Esc
  $rgb = @("38;2;160;0;200","38;2;185;0;215","38;2;205;0;230","38;2;185;0;215","38;2;160;0;200")
  try { foreach ($c in $rgb) { Write-Host "$esc[1m$esc[$c" + "m" + $Text + "$esc[0m" } }
  catch { foreach ($cc in @('Magenta','DarkMagenta','Magenta')) { Write-Host $Text -ForegroundColor $cc } }
}
function Show-FinaleCredits {
  if ($script:CreditsShown) { return }
  Write-Host ""
  Show-ImportantBanner -Text "autoupdate credit: https://github.com/asmtron/rdpwrap" -Fg White -Bg DarkBlue
  Show-PurplePulse "made with <3 by neo0oen"
  $script:CreditsShown = $true
}

# --- RDP file helper ---------------------------------------------------
function New-Seat2RdpFile {
  param([Parameter(Mandatory=$true)][string]$TargetUser)
  $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
         Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
         Select-Object -ExpandProperty IPAddress
  $primary = if ($ips) { $ips | Select-Object -First 1 } else { $env:COMPUTERNAME }

  $content = @"
full address:s:$primary
username:s:$TargetUser
prompt for credentials:i:1
screen mode id:i:2
authentication level:i:2
compression:i:1
"@

  $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
  $fileName = "Seat2_{0}_{1}.rdp" -f $TargetUser, $ts
  $outScript = Join-Path $PSScriptRoot $fileName
  $outPublic = Join-Path $env:Public ("Desktop\" + $fileName)

  try {
    $content | Out-File -FilePath $outScript -Encoding ASCII -Force
    $content | Out-File -FilePath $outPublic -Encoding ASCII -Force
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
    # Fallback for systems without Expand-Archive or weird encodings
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

# --- Installer download / layout --------------------------------------
function Ensure-UpstreamBinaries {
  $prog = "${env:ProgramFiles}\RDP Wrapper"
  if (-not (Test-Path $prog)) { New-Item -ItemType Directory -Path $prog -Force | Out-Null }

  # 1) RDPWrap core (RDPWInst.exe / RDPConf.exe / RDPCheck.exe + batch files)
  $rdpZip = Join-Path $env:TEMP ("RDPWrap_{0}.zip" -f (Get-Date -Format 'yyyyMMddHHmmss'))
  $needCore = @('RDPWInst.exe','RDPConf.exe','RDPCheck.exe') | ForEach-Object { -not (Test-Path (Join-Path $prog $_)) }
  if ($needCore -contains $true) {
    if (-not (Get-WebFile -Uri $DL.RDPWrapZip -OutFile $rdpZip)) {
      throw "Could not download RDPWrap release zip."
    }
    if (-not (Extract-Zip -ZipPath $rdpZip -Dest $prog)) {
      throw "Failed to extract RDPWrap release zip."
    }
    Remove-Item $rdpZip -Force -ErrorAction SilentlyContinue
  }

  # 2) Autoupdate (autoupdate.bat + helpers)
  if (-not (Test-Path (Join-Path $prog 'autoupdate.bat'))) {
    $autoZip = Join-Path $env:TEMP ("autoupdate_{0}.zip" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    if (-not (Get-WebFile -Uri $DL.AutoZip -OutFile $autoZip)) {
      throw "Could not download autoupdate_v1.2.zip."
    }
    if (-not (Extract-Zip -ZipPath $autoZip -Dest $prog)) {
      throw "Failed to extract autoupdate_v1.2.zip."
    }
    Remove-Item $autoZip -Force -ErrorAction SilentlyContinue
  }
}

# --- User helpers (unchanged) -----------------------------------------
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
  Write-Host "=== Choose or Create Seat-2 User ===`n"
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

function Remove-SeatUser {
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
  Write-Host "`n=== Enabling RDP and starting services ==="
  reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f | Out-Null
  reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f | Out-Null
  reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fSingleSessionPerUser /t REG_DWORD /d 0 /f | Out-Null
  reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxInstanceCount /t REG_DWORD /d 999999 /f | Out-Null

  try { Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop | Out-Null }
  catch { netsh advfirewall firewall set rule group="remote desktop" new enable=yes | Out-Null }

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
  Write-Host "`n=== Deploying RDP Wrapper (stascorp release + asmtron autoupdate) ==="
  Credit-Banner-Begin
  $prog = "${env:ProgramFiles}\RDP Wrapper"
  Ensure-UpstreamBinaries

  $inst = Join-Path $prog 'RDPWInst.exe'
  $conf = Join-Path $prog 'RDPConf.exe'
  $auto = Join-Path $prog 'autoupdate.bat'

  & $inst -i | Write-Host
  & $inst -w | Write-Host
  if (Test-Path $auto) {
    Write-Host "`n=== Running RDP Wrapper Autoupdate ==="
    Start-Process -FilePath $auto -Verb RunAs -Wait
  } else {
    Write-Warning "autoupdate.bat not found."
  }
  if (-not (Test-Path $conf)) { throw "RDPConf.exe not found after install." }
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
  Write-Host "`n=== Fixing RDP services (reset to inbox termsrv.dll) ==="
  try {
    Stop-Service TermService -ErrorAction SilentlyContinue
    Stop-Service UmRdpService -ErrorAction SilentlyContinue

    $uninst = "C:\Program Files\RDP Wrapper\uninstall.bat"
    if (Test-Path $uninst) { Start-Process -FilePath $uninst -Verb RunAs -Wait }

    $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters'
    $desired = '%SystemRoot%\System32\termsrv.dll'
    New-ItemProperty -Path $k -Name ServiceDll -PropertyType ExpandString -Value $desired -Force | Out-Null

    $s = (Get-ItemProperty -Path $k -Name ServiceDll).ServiceDll
    $p = [Environment]::ExpandEnvironmentVariables($s)
    Write-Host "ServiceDll now: $s"
    Write-Host "Expanded path: $p"
    if (-not (Test-Path $p)) { throw "termsrv.dll not found at expected path: $p" }

    try { Set-Service -Name TermService -StartupType Automatic } catch {}
    try { Set-Service -Name UmRdpService -StartupType Manual } catch {}
    Start-Service TermService
    Start-Service UmRdpService
    Get-Service TermService,UmRdpService,SessionEnv | Format-Table Name,Status,StartType -AutoSize

    Write-Host "Fix complete."
  } catch {
    Write-Error $_.Exception.Message
    throw
  }
}

# --- Menu / Flow -------------------------------------------------------
function Show-StartMenu {
  Write-Host ""
  Write-Host "======================================="
  Write-Host " Two-Seat Setup (RDP Wrapper)"
  Write-Host "======================================="
  Write-Host "[1] Install/Configure Seat 2 (user + RDP Wrapper)"
  Write-Host "[2] Fix RDP services (reset termsrv.dll, uninstall wrapper)"
  Write-Host "[3] Delete a user"
  Write-Host "[4] Open RDP Wrapper folder"
  Write-Host "[Q] Quit"
}

function Seat2-InstallFlow {
  param([string]$TargetUser)
  Write-Host "=== Installing/Configuring Seat 2 for account: $TargetUser ==="
  New-Seat2RdpFile -TargetUser $TargetUser
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
        Show-FinaleCredits
        return
      }
    } else {
      Show-ImportantBanner -Text "You chose not to run FIX now. Use menu option 2 (Fix RDP) and re-run option 1 later." -Fg Black -Bg Yellow
      Show-FinaleCredits
      return
    }
  }

  Open-RDPConf-And-Guide
  Write-Host "`nAll steps completed. Please reboot your PC manually once before testing concurrent RDP." -ForegroundColor Yellow
  Show-FinaleCredits
}

function Main-Menu {
  do {
    Show-StartMenu
    $choice = Read-Host "Choose an option"
    switch -Regex ($choice) {
      '^(?i)1$' {
        $userName = Ensure-User
        Seat2-InstallFlow -TargetUser $userName
        continue
      }
      '^(?i)2$' { Fix-RDP-Service; Show-FinaleCredits; continue }
      '^(?i)3$' { Remove-SeatUser; continue }
      '^(?i)4$' { Open-RDP-Folder; continue }
      '^(?i)(Q|Quit|E|Exit)$' { return }
      default { Write-Warning "Invalid selection. Try again."; Start-Sleep -Milliseconds 600; continue }
    }
  } while ($true)
}

try { Main-Menu } finally {
  Write-Host "`nNote: A reboot is recommended after installation or fixes. Please reboot manually." -ForegroundColor Yellow
  Show-FinaleCredits
  Stop-Transcript | Out-Null
}
