
# Next Steps (1–2 weeks)

1) Harden firewall control
- Goal: Ensure no leaks under edge cases
- Files: `neo_multiseat.ps1`
- Validate: toggle combos; `Get-NetFirewallRule neo_multiseat_*`; external connect tests

2) Monitor polish (post-stabilization)
- Goal: Improve footer clarity and CSV export path; ensure Out-GridView hint/fallback
- Files: `neo_multiseat.ps1`, `README.md`
- Validate: footer reads clearly; G opens grid where available; CSV path consistent

3) LAN multi‑subnet guidance
- Goal: UX hint + input validation for CIDRs
- Files: `neo_multiseat.ps1`, `README.md`
- Validate: add two subnets; confirm rule updates; reconnect from both

4) Offline mirrors and checksums
- Goal: Allow no‑network installs with integrity
- Files: `neo_multiseat.ps1`, `BUILD.md`
- Validate: run without internet using local zips; checksum verified

5) Screenshots + doc touch‑ups
- Goal: Faster comprehension for new users
- Files: `README.md`, `AGENTS.md`
- Validate: images render; links accurate

6) Optional: firewall state export
- Goal: Quick attachable diagnostics
- Files: `neo_multiseat.ps1`
- Validate: command writes concise TXT with rules/ports
