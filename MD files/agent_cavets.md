# Agent Caveats

Known constraints and tips when automating in this repo.

Execution
- Windows‑only. Requires elevated PowerShell.
- Session policy: `Set-ExecutionPolicy Bypass -Scope Process -Force`.
- Avoid long‑running scans; prefer cached status helpers.

Networking & Firewall
- Always disable Windows built‑in “Remote Desktop” group; use neo rules.
- Align rule ports to the registry RDP port.
- Use Profile=Any to avoid Public‑profile surprises.
- Tailscale/WAN hard blocks are enabled when those modes are Off.

Logging / Diagnostics
- Transcript logs: `./neo_multiseat_*.log`.
- Live monitor keys (new window): `Q` quit, `R` RDP-only, `S` toggle-success, `K` lockouts, `L` list (on-demand), `+/-` days, `C` clear, `E` export, `G` GUI grid.
- RDP-only filter: Successes LT=10; Failures LT in 10/7/3.
- Event IDs: failures 4625, lockouts 4740, successes 4624.

Hot‑Reload / Iteration
- Keep functions small for patching.
- Cache heavy queries; refresh on demand.
- Validate toggles after each change.

Test Data
- Create a disposable local user for connect tests.
- Use a second machine (or VM) on same LAN for reachability checks.
- For Tailscale, confirm 100.x presence before testing.

Debugging Hooks
- Add temporary `Write-Host` lines; remove before finalizing.
- Inspect rules: `Get-NetFirewallRule neo_multiseat_* | Format-Table DisplayName,Enabled`.
- Inspect filters: `... | Get-NetFirewallPortFilter` and `... | Get-NetFirewallAddressFilter`.
