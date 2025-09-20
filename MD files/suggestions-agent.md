# Suggestions (Agent)

Context: Live monitor and Advanced menu have been simplified and improved. Below are optional, scoped suggestions for future quality and robustness. No code changes are included here — paste any items you want implemented.

- Monitor footer clarity (tiny):
  - Add a compact hint: "Succ=LT10, Fail=LT10/7/3" at the end of the footer line.

- CSV export path and size:
  - Option to export CSVs under `./logs/` (consistent with transcript logs) instead of the monitor window folder.
  - Consider an environment variable or config flag to choose destination.
  - Cap export rows (e.g., 200) and include filter summary in CSV header.

- Out-GridView availability hint:
  - Detect if `Out-GridView` is unavailable and print a one-liner with a fallback suggestion (e.g., "Install RSAT/PowerShell ISE" or use `O`-style Notepad details as a fallback behind a config flag).

- Credits animation toggle:
  - Add a config flag to disable the animated credits banner for very slow terminals.

- WAN allowlist UX:
  - Validate CIDR/IP format and provide examples inline. Offer to auto-add `/32` when a bare IP is entered.

- Optional firewall state export:
  - Add a menu item to export a concise firewall/RDP state snapshot to `./logs/neo_firewall_state_*.txt` for support.

- Download integrity:
  - Add optional SHA256 checksum verification for wrapper/mirror zips when provided.

- Auto-pop monitor tuning:
  - If you restore monitor settings later, consider exposing a minimal "threshold/window" quick toggle directly in Advanced without the full editor.


Proposed README cleanup (for MD files/README.md)
- Replace the current README (which has encoding artifacts) with the cleaned version below to accurately reflect current behavior and improve readability. If you approve, paste this into `MD files/README.md`.

---

# neo_multiseat

Turn one Windows PC into a comfy multi-seat workstation without weird hacks. Run one PowerShell script, pick a user, and boom: multiple people can use the same machine at the same time (via Remote Desktop).

Note: Remote Desktop licensing and your company policies still apply. Use this responsibly on systems you own/admin.

## Why
Sometimes you have a solid PC and two (or more) humans. Pair programming, family PC, quick lab setup — no need to buy extra boxes when you only need extra seats.

## Features
- One script, one job — a clean menu that guides you end-to-end.
- Pick or create a user — list existing accounts, reset a password, or add a new one.
- Always creates a `.rdp` file — named after the chosen user.
- Supports more than two seats — concurrent sessions for multiple users (3–5 is common; ~10 with capable hardware/configs).
- Uses your mirrors — downloads and updates from your repo for stability.
- Built-in “Fix it” — if RDP gets grumpy, press Fix; the script repairs and retries.
- Open the folder / delete a user — quick maintenance shortcuts in the menu.
- Polite finish — tells you when to reboot, doesn’t hold your PC hostage.

Practical limits depend on CPU/RAM/IO/network and policy. Plan capacity like a small terminal server.

## Requirements
- Windows 10/11 Pro/Enterprise
- Local admin rights
- PowerShell 5.1+
- Internet (for initial wrapper downloads) or provide offline zips

Some AV tools may flag wrapper binaries. Add exclusions if you trust your source.

## Quick Start
1) Open elevated PowerShell (Run as Administrator).
2) Allow this session to execute scripts: `Set-ExecutionPolicy Bypass -Scope Process -Force`
3) Run the tool: `./neo_multiseat.ps1`
4) Choose an option: Install/Configure, Fix RDP, Delete a user, Open RDP folder.

Reboot once before testing extra seats.

## Menu Status
- The banner shows a color‑coded STATUS line: TermService, Port, Wrapper, INI, NLA, TLS, LAN/WAN/TS, and recent auth counts.
- Colors: Green = good, Yellow = attention/disabled/disconnected, Red = problem.
  - WAN: Off is Green (safer); On is Red (exposed).
  - Fail count: Red when > 0.

## How To Connect
- The script creates a ready‑to‑use `.rdp` file when you pick or create a user.
- File name format: `<username>.rdp`
- Where to find it: same folder as the script and on the Public Desktop.
- To connect: double‑click the `.rdp` file, enter the password you set, proceed through any standard prompts.

## Network Modes
- LAN — allowlisted local subnets for RDP (default `LocalSubnet`).
- WAN — internet exposure; requires a strict allowlist (CIDR/IPs). Avoid `Any/0.0.0.0/0`.
- Tailscale — access via the Tailscale adapter (if present).
- Advanced — NLA+TLS, disable NTLMv1, account lockout, live monitor, and Tailscale helper.

## Live Monitor
- Opens in a new terminal window (Advanced -> [4]).
- Controls:
  - `R` RDP‑only filter: Successes LT=10; Failures LT in 10/7/3
  - `S` toggle successes (show/hide 4624)
  - `K` toggle lockouts (show/hide 4740)
  - `+/-` days window; `L` list on demand; `E` export CSV; `C` clear; `Q` quit
  - `G` GUI: grid of the current filtered list; select a row for full details
- Why: Many failed RDP attempts are logged as type 3 or 7 before a full session exists; RDP‑only includes them so failures remain visible.

Known notes:
- Listing prints only when pressing `L` (by design); streaming honors filters.
- Minor UI polish pending (header refresh cadence, compact formatting).

## Folder Layout
- `neo_multiseat.ps1` — main script and menus
- `neo_multiseat.net.json` — network modes config (auto‑created)
- `neo_multiseat_*.log` — transcript logs per run
- `*.rdp` — generated connection files (per user)

## More Than Two Seats
- Create/prepare more users by running Install/Configure and selecting a different user (or create new).
- Each run drops a fresh `.rdp` file; hand those to your users.
- Multiple devices can connect concurrently using different accounts.
- Scaling: 3–5 sessions is common; ~10 possible if CPU/RAM/network keep up and policies allow it.

## Troubleshooting
- TermService failed to start: use Fix RDP (repairs termsrv.dll path, wrapper, and services), then try Install again.
- RDPConf shows red: run Fix RDP, then Install/Configure; ensure autoupdate ran.
- AV blocked something: check logs and whitelist the wrapper folder if you trust it.
- Still stuck? Reboot, then run Fix -> Install.

## Credits
- Original (Stas’ RDP Wrapper): https://github.com/stascorp/rdpwrap
- Autoupdate (asmtron): https://github.com/asmtron/rdpwrap
- Updates: pulled from your fork (see this repo).

## Third‑Party Notices
This project configures Windows Remote Desktop and downloads components from the projects above during setup. Those components remain subject to their own licenses. Refer to their repositories for full license terms and notices.
