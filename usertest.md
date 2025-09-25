# Testing guide for FreeRDP multi-seat launchers

This walkthrough explains how to verify the bundled FreeRDP client and the per-seat launchers that fix the "stuck mouse" issue for secondary RDP sessions. Follow these steps on the Windows host where you run `neo_multiseat.ps1`.

## 1. Prerequisites

- Windows 10/11 **Pro** or **Enterprise**.
- Local administrator account on the host.
- Internet access for the first run (the script downloads the official FreeRDP ZIP once).
- PowerShell 5.1+ (built into Windows).

## 2. Run the script

1. Download the repo (or copy the latest `neo_multiseat.ps1`) onto the host.
2. Open **PowerShell as Administrator**.
3. Allow the script to run and start it:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\neo_multiseat.ps1
   ```
4. Pick **Install / Configure extra seats** from the menu and follow the prompts to select or create a Windows user for the extra seat.

> Tip: If you already have seats configured, re-running the option for each account refreshes the `.rdp` and FreeRDP launcher files.

## 3. Confirm the FreeRDP client download

The script caches the official `wfreerdp.exe` build under `clients/FreeRDP-3.5.0`. After the install step finishes:

1. Open **File Explorer** to the folder where `neo_multiseat.ps1` lives.
2. Verify that a new subfolder exists: `clients\FreeRDP-3.5.0\`.
3. Drill into that folder and ensure `wfreerdp.exe` is present. (The script downloads the ZIP, verifies the SHA256 hash, then extracts the binary here.)

If the folder is missing, re-run the script—PowerShell will print a warning if the download failed (network outage, blocked URL, etc.).

## 4. Locate the per-seat launchers

For each seat you configure, the script now drops two files:

- `Seat2_<User>_<timestamp>.rdp` (traditional Microsoft RDP file)
- `Connect - <User> (FreeRDP).cmd` (preconfigured launcher that enables relative mouse input)

You will find duplicates of both files in two places:

- The same folder as `neo_multiseat.ps1`
- `C:\Users\Public\Desktop` (Public Desktop)

Verify both locations contain the new `.cmd` launcher alongside the `.rdp` file.

## 5. Test the FreeRDP launcher

1. On the secondary seat, double-click `Connect - <User> (FreeRDP).cmd`.
2. When prompted, enter the password you set for that user during seat setup.
3. Once the desktop appears, launch the game or application that previously trapped the mouse.
4. Move the mouse in all directions—because the launcher passes `/mouse:relative:on` through FreeRDP, the pointer should no longer stop at the screen edge.

If the launcher reports that the client is missing, rerun `neo_multiseat.ps1` (Install option) to rebuild the cache and launcher.

## 6. Optional: regenerate launchers

Any time you add or reset a seat, the script recreates both the `.rdp` and FreeRDP `.cmd` files. To regenerate them manually:

1. Start `neo_multiseat.ps1` as Administrator.
2. Choose **Install / Configure extra seats**.
3. Select the existing user account and finish the prompts—the script overwrites the connection files with fresh copies.

---

Following the steps above ensures that every seat has a working FreeRDP launcher with relative mouse support, restoring smooth pointer movement for games on secondary RDP sessions while keeping the multi-seat workflow unchanged.
