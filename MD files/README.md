# neo_multiseat

Turn one Windows PC into a comfy multi-seat workstation without weird hacks. Run one PowerShell script, pick a user, and boom: multiple people can use the same machine at the same time (via Remote Desktop).

Note: Remote Desktop licensing and your company policies still apply. Use this responsibly on systems you own/admin.

---

## Why

Sometimes you have a solid PC and two (or more) humans. Pair programming, family PC, quick lab setup — no need to buy extra boxes when you only need extra seats.

---

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

---

## Requirements

- Windows 10/11 Pro/Enterprise
- Local admin rights
- PowerShell 5.1+
- Internet (for initial wrapper downloads) or provide offline zips

Some AV tools may flag wrapper binaries. Add exclusions if you trust your source.

---

## Quick Start

1) Open elevated PowerShell (Run as Administrator).
2) Allow this session to execute scripts:
   - `Set-ExecutionPolicy Bypass -Scope Process -Force`
3) Run the tool:
   - `./neo_multiseat.ps1`
4) Choose an option:
   - Install / Configure extra seats (main)
   - Fix RDP (repairs wrapper/services)
   - Delete a user / Open RDP folder

Reboot once before testing extra seats.

---

## Menu Status

- The banner shows a color‑coded STATUS line: TermService, Port, Wrapper, INI, NLA, TLS, LAN/WAN/TS, and recent auth counts.
- Colors: Green = good, Yellow = attention/disabled/disconnected, Red = problem.
  - WAN: Off is Green (safer); On is Red (exposed).
  - FAIL count: Red when > 0.

---

## How To Connect

- The script creates a ready‑to‑use `.rdp` file when you pick or create a user.
- File name format: `<username>.rdp`
- Where to find it:
  - Same folder as the script
  - Public Desktop (for convenience)
- To connect:
  1) Double‑click the `.rdp` file.
  2) Enter the password set in the script for that user.
  3) Continue through any standard RDP prompts.

Tip: You can copy the `.rdp` to another machine and connect across the network (ensure reachability and correct firewall mode).

---

## Network Modes

- LAN — allowlisted local subnets for RDP (default `LocalSubnet`).
- WAN — internet exposure; requires a strict allowlist (CIDR/IPs). Avoid `Any/0.0.0.0/0`.
- Tailscale — access via the Tailscale adapter (if present).
- Advanced — NLA+TLS, disable NTLMv1, account lockout, live monitor, and Tailscale helper.

---

## Live Monitor

- Opens in a new terminal window (Network Modes → Advanced → [4]).
- Controls:
  - `R` RDP‑only filter
    - Successes: show only LogonType=10 (RemoteInteractive)
    - Failures: include RDP‑related pre‑auth types 10/7/3 (so you see common RDP failures even when RDP‑only is On)
  - `S` toggle successes (show/hide 4624)
  - `K` toggle lockouts (show/hide 4740)
  - `+/-` change days window; `L` list on demand; `E` export CSV; `C` clear; `Q` quit
  - `G` GUI: open a grid of the current filtered list; select a row for full details
- Why: Many failed RDP attempts are logged as type 3 or 7 before a full RDP session exists; the RDP‑only filter includes them so failures remain visible.

Notes:
- Listing prints only when pressing `L` (by design); streaming honors filters.
- CSV exports are written to the monitor window’s folder.

---

## Folder Layout

- `neo_multiseat.ps1` — main script and menus
- `neo_multiseat.net.json` — network modes config (auto‑created)
- `neo_multiseat_*.log` — transcript logs per run
- `*.rdp` — generated connection files (per user)

---

## More Than Two Seats

- Create/prepare more users by running Install/Configure and selecting a different user (or create new).
- Each run drops a fresh `.rdp` file; hand those to your users.
- Multiple devices can connect concurrently using different accounts.
- Scaling: 3–5 sessions is common on modern hardware; ~10 possible if CPU/RAM/network keep up and policies allow it.

---

## Troubleshooting

- TermService failed to start
  - Use “Fix RDP” (repairs termsrv.dll path, wrapper, and services), then try Install again.
- RDPConf shows red
  - Run Fix RDP, then Install/Configure; ensure autoupdate ran.
- AV blocked something
  - Check logs and whitelist the wrapper folder if you trust it.
- Still stuck?
  - Reboot once, then rerun the script and pick Fix → Install.

---

## Credits

- Original (Stas’ RDP Wrapper): https://github.com/stascorp/rdpwrap
- Autoupdate (asmtron): https://github.com/asmtron/rdpwrap
- Updates: pulled from your fork (see this repo).

---

## Third‑Party Notices

This project configures Windows Remote Desktop and downloads components from the projects above during setup. Those components remain subject to their own licenses. Refer to their repositories for full license terms and notices.

---

## Links

- See `AGENTS.md` for contributor/agent guidelines
- See `BUILD.md` for environment and packaging steps

---

## License & Disclaimer

- Add a LICENSE file (MIT is common for scripts) if you want others to reuse/fork safely.
- Disclaimer: This changes how Windows Remote Desktop behaves so multiple people can share the same PC at once. Use at your own risk. Ensure you comply with all licenses, policies, and laws. Back up your system.
