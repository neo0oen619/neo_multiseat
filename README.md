# neo_multiseat 🎮🖥️🖥️

Turn one Windows PC into a comfy **two-seat** workstation — without weird hacks or yak-shaving.  
Run one PowerShell script, pick a user, and boom: two people can use the same machine **at the same time** (via Remote Desktop).

> Heads-up: Remote Desktop licensing & your company policies still apply. Use this responsibly on systems you own/admin.

---

## Why though?

Sometimes you’ve got a solid PC and **two humans**. Pair programming, family PC, quick lab setup… no need to buy a second box when you only need a second *seat*.

---

## Features (no buzzwords, just vibes)

- **One script, one job** — a clean menu that guides you end-to-end.
- **Pick or create a user** — list existing accounts, reset a password, or add a new one.
- **Always creates a .RDP file** — named after the chosen user *and* timestamp.
- **Works with your fork** — downloads and updates from your repo for stability.
- **Auto-updates the good stuff** — fetches updated config after Windows updates.
- **Built-in “Fix it”** — if RDP gets grumpy, press Fix; the script repairs and retries.
- **Open the folder / delete a user** — quick maintenance shortcuts, right in the menu.
- **Polite finish** — tells you when to reboot, doesn’t hold your PC hostage.

---

## Requirements

- Windows 10/11 **Pro/Enterprise**
- Local admin rights
- Internet access (to pull binaries from your fork)
- PowerShell (Windows default is fine)

> Some AV tools may flag wrapper binaries. Add exclusions if you trust your source.

---

## Quick start

1. **Download** the script from this repo’s releases or `scripts/` folder.  
2. **Run PowerShell as Administrator**, then:

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\Setup-Seat2-Integrated.ps1
Choose an option:

Install / Configure Seat 2 (the main event)

Fix RDP (if Windows updates or configs got spicy)

Delete a user (with a big “are you sure?”)

Open the RDP folder (for the curious)

When done, reboot once before testing the second seat.

How to connect (super explicit)
The script always creates a ready-to-use .rdp file when you pick or create the Seat-2 user.

File name format:
Seat2_<username>_<YYYYMMDD_HHMMSS>.rdp

Where to find it:

In the same folder as the script

On the Public Desktop (so it’s easy for everyone)

To connect:

Double-click the .rdp file.

When prompted, enter the password you set in the script for that user.

If you see any scary warning, read it (responsibly), then continue.

Tip: You can copy the .rdp file to another machine and connect across the network (make sure PCs can see each other and ports/firewall are fine).

Troubleshooting (human-friendly)
“TermService failed to start”
Choose Fix RDP in the menu (or accept the “Fix now?” prompt). It will repair things and retry.

RDPConf shows red
Run the Fix, then Install again. If it’s still red, update the INI via autoupdate and try once more.

AV blocked something
Check logs and whitelist the RDP Wrapper folder if you trust it.

Still stuck?
Reboot once, then rerun the script and pick Fix → Install.

Rumor corner: Tailscale 🐒💨
A little bird (okay, an ape with suspiciously good Wi-Fi) whispered that pairing this setup with Tailscale makes remote connections feel like a small tail-wind.
Punchline from the ape: “It just worked — and I didn’t even have to climb the router.” 🍌

(Translation: If you want easy, secure remote access across the internet without port-forwarding, Tailscale can help.)

Credits 🙌
Original work & autoupdate (upstream): asmtron/rdpwrap

Your binaries & updates: pulled from your fork for stability (see this repo).

Signature: made with <3 by neo0oen

License & Disclaimer
Add a LICENSE file (MIT is common for scripts) if you want others to reuse/fork safely.

Disclaimer: This changes how Windows Remote Desktop behaves so two people can share the same PC at once. Use at your own risk. Ensure you comply with all licenses, policies, and laws. Back up your system. Drink water. Call your mom.
