# neo_multiseat 🎮🖥️🖥️

Turn one Windows PC into a comfy **two‑seat** workstation — without weird hacks or hours of yak‑shaving.  
Run one PowerShell script, pick a user, and boom: two people can use the same machine **at the same time** (via Remote Desktop).

> Heads‑up: Remote Desktop licensing & company policies still apply. Use this responsibly on systems you own/admin.

---

## Why though?
Because sometimes you’ve got a solid PC and **two humans**. Pair programming, family computer, quick lab setup… no need to buy a second box when you only need a second *seat*.

---

## Features (no buzzwords, just vibes)

- **One script, one job** — a clean menu that guides you end‑to‑end.
- **Pick or create a user** — list existing accounts, reset a password, or add a new one.
- **Works with your fork** — downloads and updates from your repo for stability.
- **Auto‑updates the good stuff** — pulls the latest configuration so things keep working after Windows updates.
- **Built‑in “Fix it” button** — if RDP goes grumpy, press Fix; the script repairs and retries for you.
- **Open the folder / delete a user** — quick maintenance shortcuts, right in the menu.
- **No leftover clutter** — doesn’t spam files you don’t need.
- **Polite finish** — tells you when to reboot, doesn’t hold your PC hostage.

---

## Quick start

1) **Download** the script from this repo’s releases or `scripts/` folder.  
2) **Run PowerShell as Administrator**, then:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Setup-Seat2-Integrated-v6.ps1
```
3) Choose an option:  
   - **Install / Configure Seat 2** (the main event)  
   - **Fix RDP** (if Windows updates or configs got spicy)  
   - **Delete a user** (with a big “are you sure?”)  
   - **Open the RDP folder** (for the curious)  

That’s it. When you’re done, **reboot once** before testing the second seat.

---

## FAQ (for humans)

**Is this safe/legal?**  
It depends on your Windows edition, licensing, and company policy. This project is for admins who know their environment.

**Will this break after Windows updates?**  
It’s designed to help itself — it fetches updated config from your fork and includes a **Fix** option if something turns red.

**Can I make it three seats?**  
This repo focuses on a clean, reliable **two‑seat** setup. More seats = more variables; PRs welcome if you’ve got a stable recipe.

---

## Credits 🙌

- **Upstream & autoupdate work:** asmtron’s fork of RDP Wrapper — absolute legend. citeturn0search3  
- **Your binaries & updates:** pulled from your fork to keep things consistent. (See this repo’s instructions.) citeturn0search0

**Signature:** _made with <3 by neo0oen_

---

## Disclaimer

This project changes how one Windows feature behaves so two people can share the same PC at once. **Use at your own risk.** Double‑check your local laws, licenses, and policies. Back up your system. Drink water. Call your mom.

