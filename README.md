# neo_multiseat 🎮🖥️🖥️🖥️

Turn one Windows PC into a comfy **multi‑seat** workstation — without weird hacks or yak‑shaving.
Run one PowerShell script, pick a user, and boom: multiple people can use the same machine **at the same time** (via Remote Desktop).

> **Heads‑up:** Remote Desktop licensing & your company policies still apply. Use this responsibly on systems you own/admin.

---

## Why though?

Sometimes you’ve got a solid PC and **two (or more) humans**. Pair programming, family PC, quick lab setup… no need to buy extra boxes when you only need extra *seats*.

---

## Features (no buzzwords, just vibes)

- **One script, one job** — a clean menu that guides you end‑to‑end.
- **Pick or create a user** — list existing accounts, reset a password, or add a new one.
- **Always creates a `.rdp` file** — named after the chosen user *and* timestamp.
- **Optional neo client launcher** — auto-builds a bundled RDP client and drops a `.lnk` that forces relative mouse mode.
- **Supports more than two seats** — concurrent sessions for multiple users (people run 3–5 regularly; **10 can be done** on capable hardware/configs).
- **Works with your fork** — downloads and updates from your repo for stability.
- **Auto‑updates the good stuff** — fetches updated config after Windows updates.
- **Built‑in “Fix it”** — if RDP gets grumpy, press Fix; the script repairs and retries.
- **Locks the mouse for games** — forces GPU/WDDM mode so second+ seats don’t hit invisible screen borders when a game grabs the cursor (tap **CTRL+ALT+M** in-session to toggle relative mouse input if needed).
- **Open the folder / delete a user** — quick maintenance shortcuts, right in the menu.
- **Polite finish** — tells you when to reboot, doesn’t hold your PC hostage.

> Practical limits depend on CPU/RAM/IO/network and policy. Plan capacity like you would for a small terminal server.

---

## What’s new (add‑ons)

- **Menu Status line** with color‑coded health: **TermService, Port, Wrapper, INI, NLA, TLS, LAN/WAN/TS**, plus recent **auth counts**.
  - Colors: **Green** = good, **Yellow** = attention/disabled/disconnected, **Red** = problem.
  - **WAN**: **Off = Green** (safer); **On = Red** (exposed). **FAIL** count is **Red when > 0**.
- **Network Modes**: **LAN** (allowlisted subnets), **WAN** (strict CIDRs only — avoid `0.0.0.0/0`), **Tailscale** (auto‑detect adapter), and **Advanced** (NLA+TLS, disable NTLMv1, account lockout, Live Monitor, Tailscale helper).
- **Live Monitor**: real‑time view of successful/failed logons with quick filters, GUI grid, and CSV export.
- **Folder layout & files**:
  - `neo_multiseat.ps1` — main script and menus
  - `neo_multiseat.net.json` — network modes config (auto‑created)
  - `neo_multiseat_*.log` — transcript logs per run
  - `*.rdp` — generated connection files (per user)
  - `neo_rdp_client.exe` — auto-built WinForms launcher that flips relative mouse on
  - `* (neo client).lnk` — one-click shortcuts that call the launcher with host/user/port args

---

## Requirements

- Windows 10/11 **Pro/Enterprise**
- Local admin rights
- Internet access (to pull binaries from your fork)
- PowerShell (Windows default is fine)

> Some AV tools may flag wrapper binaries. Add exclusions if you trust your source.

---

## Quick start

1. **Download** `neo_multiseat.ps1` from the repo root (or **clone** this repo).  
2. **Run PowerShell as Administrator**, then run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\neo_multiseat.ps1
```

3. Choose an option:
   - **Install / Configure extra seats** (the main event)  
   - **Fix RDP** (if Windows updates or configs got spicy)  
   - **Delete a user** (with a big "are you sure?")  
   - **Open the RDP folder** (for the curious)

When done, **reboot once** before testing the extra seats.

---

## Menu Status

- The banner shows a color‑coded **STATUS** line: **TermService, Port, Wrapper, INI, NLA, TLS, LAN/WAN/TS**, and recent **auth counts**.
- Colors: **Green** = good, **Yellow** = attention/disabled/disconnected, **Red** = problem.
  - **WAN**: **Off = Green** (safer); **On = Red** (exposed).
  - **FAIL** count: **Red when > 0**.

---

## How to connect (super explicit)

- The script **always** creates a ready‑to‑use `.rdp` file when you pick or create a user.
- File name format:
  `Seat2_<username>_<YYYYMMDD_HHMMSS>.rdp`
- Optional launcher:
  `Seat2_<username>_<YYYYMMDD_HHMMSS> (neo client).lnk`
- Where to find it:
  - In the **same folder** as the script
  - On the **Public Desktop** (so it’s easy for everyone)
- To connect:
  1. Double‑click the `.rdp` file **or** the `(neo client)` shortcut (it launches the bundled client and forces relative mouse).
  2. When prompted, enter the password you set in the script for that user.
  3. If you see any warning, read it (responsibly), then continue.

> Tip: You can copy the `.rdp` file to another machine and connect across the network (make sure PCs can see each other and ports/firewall are open).

---

## neo_multiseat client (auto-built)

Want relative mouse capture without pressing **CTRL+ALT+M** each session? The script now compiles a tiny WinForms launcher (`neo_rdp_client.exe`) on demand whenever you generate a seat:

1. Run **Install / Configure extra seats** like normal. When you pick a user, the script checks whether `neo_rdp_client.exe` is present and up to date.
2. If it’s missing or outdated, PowerShell compiles the built-in C# source (no Visual Studio required) and drops the exe next to the script.
3. Alongside the `.rdp`, you’ll also get `Seat2_<username>_<timestamp> (neo client).lnk`. That shortcut launches the bundled client with host, username, and port arguments pre-filled, flips Microsoft’s hidden `AllowRelativeMouseMode`/`RelativeMouseMode` switches before connect, and jumps straight into the session with true relative mouse capture.

> Tip: If you prefer to ship a custom-signed build, replace `neo_rdp_client.exe` after running the script once—the timestamped `(neo client)` shortcuts pick it up automatically.

---

## Network Modes

- **LAN** — allowlisted local subnets for RDP (default `LocalSubnet`).
- **WAN** — internet exposure; requires a **strict allowlist** (CIDR/IPs). Avoid `Any/0.0.0.0/0`.
- **Tailscale** — access via the Tailscale adapter (if present).
- **Advanced** — NLA+TLS, disable NTLMv1, account lockout, **Live Monitor**, and Tailscale helper.

---

## Live Monitor

- Opens in a new terminal window (**Network Modes → Advanced → [4]**).
- Controls:
  - **R** — RDP‑only filter  
    - Successes: show only `LogonType=10 (RemoteInteractive)`  
    - Failures: include pre‑auth types **10/7/3** so common RDP failures remain visible
  - **S** toggle successes (show/hide **4624**)
  - **K** toggle lockouts (show/hide **4740**)
  - **+ / -** change days window; **L** list on demand; **E** export CSV; **C** clear; **Q** quit
  - **G** opens a GUI grid for the current filtered list (select a row for details)
- Notes:
  - Listing prints only when pressing **L** (by design); streaming honors filters.
  - CSV exports are written to the monitor window’s folder.

---

## More than two seats? (Yes.)

- **Create/prepare more users**: run **Install / Configure extra seats** again and select a different user each time (or press **N** to create new).  
- Each run drops a fresh `.rdp` file; hand those to your humans.  
- Multiple devices can connect **concurrently** to the same PC using different accounts.  
- **Scaling**: 3–5 sessions is common on modern hardware; **~10 is possible** if CPU/RAM/network keep up and policies allow it. Monitor Task Manager for bottlenecks.

---

## Troubleshooting (human‑friendly)

- **"TermService failed to start"**  
  Choose **Fix RDP** in the menu (or accept the "Fix now?" prompt). It will repair things and retry.
- **"Mouse won’t turn all the way" inside a fullscreen game**
  Re-run **Install / Configure** so the GPU/WDDM + cursor policy fix reapplies (it keeps each seat’s mouse locked to the entire display). Once you reconnect, press **CTRL+ALT+M** to enable relative mouse mode — that hotkey is per-session and helps when a game still bumps into the edges. If you ran **Fix RDP**, run **Install / Configure** once more to lay the mouse fix back down. For hands-off capture, use the generated `(neo client)` shortcut — it launches the bundled client, flips Microsoft’s hidden switches automatically, and keeps the cursor locked for games.
- **RDPConf shows red**  
  Run **Fix RDP**, then **Install** again. The script auto‑updates what it needs.
- **AV blocked something**  
  Check logs and whitelist the RDP Wrapper folder if you trust it.
- **Still stuck?**  
  Reboot once, then rerun the script and pick **Fix → Install**.

---

## Rumor corner: Tailscale 🐒💨

A little bird (okay, an **ape** with suspiciously good Wi‑Fi) whispered that pairing this setup with **Tailscale** makes remote connections feel like a **haunted VPN** — nothing on the router moves, but sessions start walking through walls.  
Punchline from the ape: "It just worked — and nobody had to sacrifice a router." 🍌

*(Translation: If you want easy, secure remote access across the internet without port‑forwarding, Tailscale can help.)*

---

## Credits 🙌

- **Original RDP Wrapper (author):** Stas’M Corp. — https://github.com/stascorp/rdpwrap  
- **Autoupdate fork (updater scripts):** asmtron — https://github.com/asmtron/rdpwrap  
- **Updates:** pulled from fork - [https://github.com/neo0oen619/neo_multiseat_rdpwrap_backup](https://github.com/neo0oen619/neo_multiseat_rdpwrap_backup)

**Signature:** *made with <3 by neo0oen*

---

## License & Disclaimer

- **License:** See the **LICENSE** file in this repo for terms.
- **Disclaimer:** This changes how Windows Remote Desktop behaves so multiple people can share the same PC at once. **Use at your own risk.** Ensure you comply with all licenses, policies, and laws. Back up your system. Hydrate. Call your mom.
