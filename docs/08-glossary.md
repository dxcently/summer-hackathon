# 08 — Glossary

> Every acronym, term, and tool name used in this `docs/` folder. Read this once. Come back when something in the other docs reads as alphabet soup.

## Competition terms

| Term | Meaning |
|---|---|
| **eCitadel** | The competition. Season IV is the 2026 run. CCDC-style format. |
| **CCDC** | Collegiate Cyber Defense Competition. The family of blue-team competitions this event copies. |
| **Blue team** | You. The defenders. |
| **Red team** | The organizers' offensive operators. They are *already inside your boxes* at T+0. Penalty category. |
| **Orange team** | Simulated automated "users" of your portal. New this year (10% of score). They log in and file tickets. |
| **Black team** | Organizers / referees. You won't talk to them often; questions go through the portal. |
| **Inject** | A business-memo-style task dropped on you mid-round via the portal. PDF response required. 35% of score. |
| **CCS** | Cyber Competition System — the agent that runs on each box and silently scores your hardening / forensics. 20% of score. |
| **IR / Instant Report** | A PDF you submit when you catch red team activity. Claws back red-team penalty points. |
| **Scoring engine** | The org-run external service that polls your services every 2–3 min. 35% of score. |
| **Scoreboard** | The portal page that shows your live service status (green/red) and current points. |
| **SLA** | Service Level Agreement. After 5 consecutive missed checks, you take a 3× point penalty per service. |
| **Revert** | Rolling a VM back to the org-issued snapshot. You get 4 free; extras cost penalty. See `07-revert-policy.md`. |
| **Grace period** | First 5 min of the round. Portal accessible, VMs are not. Use it to read announcements + plan. |
| **Practice round** | A 2-day low-stakes run before comp day. No red team, no orange team. Use it to learn the portal. |

## Network / infra terms

| Term | Meaning |
|---|---|
| **NAT (1:1)** | "Network Address Translation, one-to-one." Each internal IP (172.21.0.X) maps to exactly one external IP (172.27.team.X). Scoring engine hits the external IP; pfSense rewrites it to the internal IP. |
| **pfSense** | The open-source firewall/router OS that runs on the `thebox` VM. WebGUI at https://172.21.0.254. |
| **WireGuard** | The VPN you use to reach your team's network from your laptop. Config downloads from the portal after T+0. |
| **VMRC** | VMware Remote Console. Optional thick-client way to access VMs instead of the web browser. Unsupported / flaky for this comp. |
| **Subnet (/24, /30, /16)** | A CIDR netmask. `/24` = 256 addresses (a "class C"). `/30` = 4 addresses. `/16` = 65536 addresses. Block individual IPs only — not subnets. |
| **Transit subnet** | A tiny `/30` link between two routers. Here it's `172.21.1.0/30` (.1 upstream, .2 pfSense WAN). |
| **WAN / LAN** | "Wide Area Network" (the outside, toward the scoring engine) and "Local Area Network" (the inside, toward your VMs). |

## Active Directory / Windows terms

| Term | Meaning |
|---|---|
| **AD** | Active Directory. Microsoft's directory service for users + groups + machines + DNS for Windows networks. Cabal runs it. |
| **DC** | Domain Controller. The Windows server that hosts AD. Here: `cabal` at 172.21.0.103. |
| **Domain** | Logical grouping of AD-joined machines + accounts. Here: `rrintel.internal`. |
| **rrintel.internal** | The AD domain name for this scenario. Almost every scored service authenticates against it. |
| **AD bind** | An LDAP service account a server uses to look up users. If AD goes down, the bind fails, the service stops authenticating, and the scoring check fails. |
| **NTDS** | The on-disk AD database. `ntdsutil` is the CLI to back it up. |
| **GPO** | Group Policy Object. A bundle of configuration that Windows machines pull from the DC. Red team can plant login scripts here. |
| **LLMNR / NBT-NS** | Legacy Windows name-resolution protocols. Disable them — they're a credential-leak vector with no defensive value. |
| **SMB / SMBv1** | File-sharing protocol. v1 is ancient + insecure; disable it. v2/v3 with signing is fine. |
| **Kerberos / Kerberoast** | The AD authentication protocol. "Kerberoasting" is a class of attack where you request service tickets and crack them offline. |
| **LDAP** | Lightweight Directory Access Protocol. How non-Windows servers (like Concierge / Linux) talk to AD. Ports 389/636. |
| **SSSD** | System Security Services Daemon. The Linux service that joins a Linux host to AD via LDAP/Kerberos. Look for it on Concierge. |
| **realmd** | Linux tool that drives the AD-join process. `realm list` shows you if a Linux box is domain-joined. |
| **LAPS** | Local Administrator Password Solution. Microsoft tooling to rotate local admin passwords automatically. |
| **WMI** | Windows Management Instrumentation. Powerful local-management surface; red team uses WMI event subscriptions as a persistence mechanism. |
| **SPN** | Service Principal Name. An AD identifier for a service account. Weird new SPNs are a Kerberoast tell. |

## Linux / Unix terms

| Term | Meaning |
|---|---|
| **SSH** | Secure Shell. Remote terminal access on port 22. One of the scored services. |
| **sshd** | The SSH server daemon. Config at `/etc/ssh/sshd_config`. |
| **sshd_config** | The text file you edit to harden SSH. Validate with `sshd -t` before restarting. |
| **systemd / systemctl** | Modern Linux service manager + CLI. `systemctl list-units` shows running services. |
| **journalctl** | The systemd log reader. `journalctl -u <service>` shows logs for one service. |
| **cron** | Time-based job scheduler. Look in `/etc/cron.*/`, `/etc/crontab`, `/var/spool/cron/`. Red team plants jobs here. |
| **systemd timers** | Modern alternative to cron. `systemctl list-timers --all`. |
| **SUID / SGID** | "Set User ID" / "Set Group ID" bits on a binary — make it run as the file's owner regardless of caller. Backdoor vector. |
| **/etc/passwd** | Linux user database (one line per account, world-readable). |
| **/etc/shadow** | Password hashes for those accounts (root-only). |
| **/etc/sudoers** | Who can run what as root. `/etc/sudoers.d/` is a folder of drop-in fragments. |
| **authorized_keys** | Per-user file (`~/.ssh/authorized_keys`) listing public keys allowed to SSH in. Red-team backdoor favorite. |
| **SELinux** | Mandatory access control on Fedora/RHEL family. Should be `Enforcing`. Do not disable. |
| **AppArmor** | Same idea as SELinux but Debian/Ubuntu. |
| **UFW / firewalld / nftables / iptables** | Local firewall front-ends. Debian uses ufw/nftables; Fedora uses firewalld. |
| **ufw** | "Uncomplicated firewall" — the Debian-family front-end. `ufw allow 22/tcp`, etc. |
| **firewalld** | The Fedora/RHEL front-end. `firewall-cmd --add-service=ssh`. |

## Service / database terms

| Term | Meaning |
|---|---|
| **HTTP / HTTPS** | Web. Ports 80 / 443. Scored web checks log in and exercise the app, not just GET /. |
| **DNS** | Domain Name System. Port 53. Cabal serves DNS for `rrintel.internal`. |
| **PostgreSQL / MySQL / MariaDB / MSSQL** | Database servers. Likely on blacklist. Default ports 5432 / 3306 / 1433. |
| **pg_hba.conf** | PostgreSQL's auth-rule config. Controls who can connect from where with what method. |
| **nginx / Apache / httpd** | Web servers. Likely on concierge. |
| **PHP / php-fpm** | Server-side scripting + its process manager. Webshells hide here. |
| **Webshell** | A planted script (often PHP) that gives the attacker remote command exec via HTTP. Hunt with `grep -RElE 'eval\(\|base64_decode\('`. |
| **CSP / HSTS / X-Frame-Options** | HTTP security response headers. Cheap CCS wins to add. |

## Forensics / IR terms

| Term | Meaning |
|---|---|
| **IoC** | Indicator of Compromise. An IP, hash, filename, process name, log line — the kind of thing you put in an IR report. |
| **Hash (SHA-256)** | One-way fingerprint of a file. Used to identify malware uniquely. `sha256sum <file>` on Linux, `Get-FileHash` on Windows. |
| **Persistence** | The attacker's ability to survive a reboot. Cron, registry Run keys, scheduled tasks, SSH keys, etc. |
| **C2** | Command and Control. The attacker's server that an implant beacons to. Outbound to a weird IP is a C2 tell. |
| **Sysmon** | Microsoft's deep-process-logging tool. If installed, it's a goldmine for IR evidence. |
| **Defender** | Microsoft's built-in antivirus. Keep it on. `Set-MpPreference`, `Start-MpScan`. |
| **Exfil** | Exfiltration. The attacker copying your data out. |

## Portal / tooling terms

| Term | Meaning |
|---|---|
| **Portal** | The org-hosted web app where you submit injects + IRs, see scoreboard, file tickets, see VM consoles, and request reverts. |
| **Operations Portal** | The *in-scenario* portal the orange team uses to file tickets at you. Lives on your boxes (you have to keep it working). Different from the org portal above. |
| **Pandoc** | A document converter. Markdown → PDF via `pandoc inject.md -o inject.pdf --pdf-engine=xelatex`. |
| **xelatex** | A LaTeX engine Pandoc uses for PDF rendering. Install it before comp if you go the Pandoc route. |

## Time / scoring math terms

| Term | Meaning |
|---|---|
| **Check** | One probe by the scoring engine. Worth 1 pt (SSH) or 3 pts (other) if it passes. |
| **Round** | Not used in the strict "synchronous round" sense — checks fire at random 2–3 min intervals per service, independently. |
| **T+0** | Start of the competition window after the grace period. The clock newcomers should be tracking. |
| **Scoreboard lag** | ~5 min between a fix on the box and a visible status flip on the scoreboard (2–3 min check interval + 2–3 min upload lag). Do not panic-react in <5 min windows. |

## Things you should NOT call them

- Don't call the scoring engine "the bots" in tickets/PDFs. Call it "the org scoring engine."
- Don't call red team "the hackers" in IR reports. Call them "rogue blacklisters" (the in-scenario name) or "unauthorized actor."
- Don't call orange team "fake users" in your replies. They are users. Real grading happens against your reply quality.
