# AGENTS

Repo-wide guidance for agents and contributors. Keep changes surgical, test quickly, and document any behavior you touch.

Context
- Project Name: neo_multiseat
- Maintainer(s): @neo0oen
- Tech Stack / Platform: Windows PowerShell (5.1+), Windows 10/11 Pro/Enterprise, RDP Wrapper, Windows Firewall
- Build & Run Basics: run `neo_multiseat.ps1` as Administrator; no build step
- Primary Goals:
  1) Stable multi-seat via RDP Wrapper with simple menu
  2) Safe network access modes (LAN/WAN/Tailscale) controlled by firewall
  3) Useful diagnostics (RDPConf checks, live auth monitor, fixes)
- Repo Path Conventions:
  - Root script: `./neo_multiseat.ps1`
  - Config: `./neo_multiseat.net.json` (auto-created)
  - Logs: `./neo_multiseat_YYYYMMDD_HHmmss.log` (Start-Transcript)

Contribution Priorities (in order)
1. Stabilize live monitor (Option 4): keybindings, header, listing/export.
2. Preserve network-mode safety (LAN/WAN/TS, guard rails, blocks).
3. Fix correctness/security issues before new features.
4. Improve UX performance (fast menu rendering, minimal rescans).
5. Keep README/AGENTS/BUILD in sync with any menu/behavior change.

Build & Run
- Launch elevated PowerShell:
  - `Set-ExecutionPolicy Bypass -Scope Process -Force`
  - `./neo_multiseat.ps1`
- Quick paths:
  - Install/Configure: menu [1]
  - Fix RDP: menu [2]
  - Network Modes: menu [5]
  - Live Monitor: menu [5] → Advanced → [4] (opens new window)

Testing Tips
- Verify core health (menu banner, color-coded): TermService Running, Wrapper OK, Port, NLA/TLS.
  - Colors: Green=good, Yellow=attention/disabled/disconnected, Red=problem.
  - WAN: Off is Green (safer); On is Red (exposed). Fail count shows Red when > 0.
- Network modes (menu [5]):
  - Ensure “Windows RDP group: Disabled”.
  - Toggle each of LAN/WAN/Tailscale and validate reachability matches.
  - Check firewall: `Get-NetFirewallRule -DisplayName 'neo_multiseat_*'`.
- RDP Wrapper GUI: use RDPConf and ensure green indicators.
- Live monitor (new window): Advanced → [4]
  - R toggles RDP-only filter
    - Successes: only LT=10 (RemoteInteractive)
    - Failures: LT in 10/7/3 (RDP-related network/pre-auth)
  - S toggles successes; failures and lockouts remain visible
  - K toggles lockouts; +/− adjusts days; L lists (on-demand print); E exports; G grid-select
  - Note: You no longer need to turn R off to see common RDP failures (LT=3/7 included when R is On)

Diagnostics/Logging
- Transcript log: `./neo_multiseat_*.log`
- Live monitor CSVs: exported in the monitor window folder
- Config JSON: `./neo_multiseat.net.json`
- RDP Wrapper folder: `C:\Program Files\RDP Wrapper`
- Event Viewer: Security 4624/4625/4740

Conventions
- Code style: PowerShell functions with PascalCase names; keep one-purpose helpers.
- Minimal changes: don’t refactor broadly; touch only necessary code paths.
- Logging: prefer `Write-Host` for user flow; errors via `Write-Warning`/`Write-Error`.
- UX: maintain fast menus; cache heavy queries; throttle refreshes.
- Filenames: keep `neo_multiseat.ps1` and firewall rule names in sync across helpers.

Sandbox / Approval Expectations
- Default: propose plan, then patch. Assume no outbound network in CI unless explicitly allowed.
- Avoid adding external dependencies. If downloads are introduced, provide offline mirrors and checksums.

Special Files to Keep in Sync
- Rule names: `$RuleLAN`, `$RuleWAN`, `$RuleTS`, `$RuleTSBlock`, `$RuleBlockAll`
- Any menu label change → update `README.md` instructions.
- RDP file behavior (`New-NeoRdpFile`) → reflect in README “How to connect”.

Common Pitfalls
- Built-in Windows “Remote Desktop” firewall group re-enabling → always disable; rely on neo rules.
- Conflicting firewall rules allowing 3389 → quarantine on toggles.
- Network profile (Public vs Private) → use Profile=Any for neo rules.
- Port mismatch → keep neo rules aligned with registry RDP port.
- AV/EDR blocking downloads → document mirrors; surface errors.
- Auditing disabled → live monitor won’t show events; tool enables Logon Success/Failure at start, but GPO can revert.
- Logon types → many failures are type 3 (network). RDP‑only hides them; toggle R off to see all.
