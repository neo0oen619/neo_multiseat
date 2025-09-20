# Changelog

All notable changes in this session.

2025-09-20

- Live Monitor
  - RDP-only now includes RDP-related failures (LogonType 10/7/3) while keeping successes restricted to LT=10.
  - L key prints an on-demand, filtered list (newest-first) with pinned header.
  - Inline monitor aligned with the same failure filtering.
  - New: G opens grid-select (Out-GridView) for current list. Removed O=details; grid selection opens details directly.
- Advanced Menu
  - Simplified menu: removed options 7 (paged failed logons), 8 (toggle monitor silent), and 9 (monitor settings) as requested.
  - Code cleanup: removed the underlying functions for these features to keep the codebase lean.
- Docs
  - README/BUILD/AGENTS: clarified RDP-only behavior and documented Lockout (K).
  - README: Live Monitor section updated (keys R/S/K/L/E/C/Q/G; failures include LT 10/7/3; CSV/export and GUI grid noted).
- Status
  - Menu status line is now color-coded: Green (good), Yellow (attention/disabled/disconnected), Red (problem). Critical fields (service/wrapper/INI/TLS) highlight issues.
- Compatibility
  - `.rdp` file writes use `System.Text.Encoding::ASCII` for PowerShell 5.1 reliability.

2025-09-19

- Docs
  - README: folder layout; links to AGENTS.md and BUILD.md; network modes notes.
  - LICENSE: add MIT license.
  - Third‑Party Notices: clarify upstream projects and licensing (stascorp, asmtron).
  - AGENTS: priorities, run/test tips, pitfalls; live monitor usage.
  - BUILD: quick validation steps; live monitor tips; common fixes.
  - TODO: expanded with live monitor stabilization; guard rails; exports; auto‑start.
  - next_steps: focus on firewall hardening, monitor CSV/export, docs polish.
  - todoplan: compact daily plan.
  - agent_cavets: audit policy, logon types, debugging tips.

- Network Modes & Firewall
  - Disable built‑in Windows "Remote Desktop" group; rely on neo rules.
  - Add strict Tailscale and global block rules for off states.
  - Align neo rules to current RDP port; set Profile=Any; dedupe install.
  - WAN guard rail: refuse enabling WAN unless allowlist has specific CIDR/IP; reject Any/0.0.0.0/0/::/0.
  - Cache + fast status rendering; added Refresh.

- Logging
  - Logs moved to `./logs/`; rotation keeps last 25.

- Live Monitor (Advanced → [4])
  - New window monitor with pinned header.
  - Controls: R (RDP‑only), S (success toggle), K (lockouts), +/− (days), L (list), E (export), C (clear), Q (quit).
  - De‑dup list by RecordId; header throttled for stability.
  - Audit policy enable at start; status displayed.
  - Known issues (tracked in TODO): listing prints only on L; ensure streaming obeys filters for all logon types; refine UX.

- Double Prompt
  - Option [10]: enable NLA + host password prompt; read‑back status and show in Advanced header.

- General
  - Refactors for Start‑Process argument handling in child windows.
  - Misc. fixes to reduce parse errors and unicode issues in messages.
