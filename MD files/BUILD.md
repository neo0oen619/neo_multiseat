# BUILD / RUN

Goal: exact, copy/paste steps to run and package the project.

Prerequisites
- Windows 10/11 Pro/Enterprise
- PowerShell 5.1+ (default on Windows)
- Local Administrator rights
- Internet access for initial RDP Wrapper downloads (or provide offline zips)

Run (no build step)
1) Open an elevated PowerShell window (Run as Administrator).
2) Allow this session to execute scripts:
   - `Set-ExecutionPolicy Bypass -Scope Process -Force`
3) Run the tool:
   - `./neo_multiseat.ps1`

Quick Validate
- Menu shows a color-coded status line with TermService, Port, Wrapper, INI, NLA, TLS, LAN/WAN/TS, and recent auth counts.
  - Green = good, Yellow = attention/disabled/disconnected, Red = problem.
- Option [1] completes without errors and RDPConf is green.
- Option [5] toggles LAN/WAN/Tailscale as expected.
- Option [5] → Advanced → [4] live monitor opens in a new window.
  - R toggles RDP-only filter: Successes LT=10; Failures LT in 10/7/3
  - S toggles successes; failures (4625) and lockouts (4740) remain visible
  - L lists on-demand (newest first); E exports CSV; +/- adjust days; C clears; G grid-select

Packaging / Distribution
- Single-file distribution: include `neo_multiseat.ps1`, `README.md`, `LICENSE` in a zip.
- Offline mirrors (optional): add RDP Wrapper zips to a `./vendor/` folder and point `$DL` URLs to local files.

Uninstall / Rollback
- Use option [2] Fix RDP services to restore `termsrv.dll` and stop wrapper.
- Disable all neo rules (menu [5] → set LAN/WAN/TS Off). This enables the block‑all rule to close port 3389.
- Optionally re‑enable Windows built‑in “Remote Desktop” firewall group if you want stock behavior.

Common Errors & Fixes
- “Execution of scripts is disabled”: run `Set-ExecutionPolicy Bypass -Scope Process -Force` in the elevated session.
- Not elevated: the script relaunches itself as Admin. If blocked, run as Administrator manually.
- AV/EDR blocks downloads: whitelist or replace `$DL` URLs with local mirrors.
- RDPConf shows red: run “Fix RDP” then “Install/Configure” again; ensure autoupdate ran.
- Can connect even when Off: ensure Windows RDP group is disabled; use menu [5] (the script manages this automatically).
- LAN On but blocked: network profile set to Public; neo rules now use Profile=Any; verify port alignment.
- Live monitor doesn’t show events: ensure auditing (Logon Success/Failure) is enabled; tool sets it at start.
