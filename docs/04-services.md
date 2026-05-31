# 04 — Scored services

> 7 total. SSH, HTTP, DNS. All polled externally every 2-3 min by an org-run scoring engine.
> **Almost every check uses AD authentication against `rrintel.internal`.** AD goes down → cascading red.

## What we know (from briefing)

- 7 total scored services
- Service types named: **SSH**, **HTTP**, **DNS**
- Scoring engine rotates IPs, lives on the same subnet as red team — never block subnets
- Web checks log in and exercise functionality — not just an HTTP 200
- Static HTML will NOT pass the web check
- Most checks use AD against `rrintel.internal`
- Points: non-SSH = 3/check, SSH = 1/check
- SLA: 5 consecutive misses → 3× point penalty

## Inferred service inventory (verify at T+0)

Based on host roles, the 7 are likely some combination of:

| # | Host | Service | Port | Auth | Points/check |
|---|---|---|---|---|---|
| 1 | blacklist (Debian) | SSH | 22 | AD or local | 1 |
| 2 | blacklist | Database (Postgres / MySQL / MSSQL) | 5432 / 3306 / 1433 | AD or local | 3 |
| 3 | concierge (Fedora) | SSH | 22 | AD | 1 |
| 4 | concierge | HTTP/HTTPS web app | 80 / 443 | AD (login + click action) | 3 |
| 5 | cabal (Win DC) | DNS (`rrintel.internal`) | 53 | — | 3 |
| 6 | cabal | RDP or LDAP | 3389 / 389 / 636 | AD | 3 |
| 7 | (one of these) | a second HTTP (operations portal) | 80 / 443 / 8080 | AD | 3 |

This is a guess. **The first thing to do at T+0 is enumerate `ss -tlnp` / `netstat -ano` on each box and match against scoreboard service names.**

## Dependency map

```
                            DNS (cabal:53) ─┐
                                            │
                            AD/LDAP (cabal:389/636) ─┐
                                                     │
                                                     ▼
                  Concierge web login ──── needs ──── AD bind
                  Concierge SSH (AD) ───── needs ──── AD bind
                  Blacklist DB (AD users) needs ──── AD bind
                  Blacklist SSH (AD) ──── needs ──── AD bind
                                                     │
                                                     ▼
                                          DC must be UP
                                          DNS must resolve from outside
```

**Implication:** if cabal goes down or DC service breaks, **every other service that uses AD will go red**. Cabal is the keystone.

## Score-protect rules

1. **Test from outside.** After any change, verify via your external IP using a Linux client (`curl https://172.27.X.102/`, `ssh user@172.27.X.101`, `dig @172.27.X.103 rrintel.internal`).
2. **Verify auth flow.** For web: actually log in. For SSH: actually run `id` after connecting.
3. **One change at a time.** If you bulk-edit and something breaks, you can't tell which change did it.
4. **Wait 5 min before reacting.** Scoreboard lag is real.
5. **Cabal first, web second, db third.** Restoration priority by blast radius.
6. **Don't turn off Defender / SELinux / sshd.** These hold the line and CCS docks you for disabling them.

## Common breakage causes

| Symptom | Likely cause |
|---|---|
| All AD-backed services red simultaneously | DC down / DNS down / AD service stopped |
| Web red but SSH green on same box | Web app dependency failed (DB, AD, file perms) |
| Service flaps green/red | Health-check intermittent — could be CPU pegged by red team |
| Service green internally but red externally | pfSense NAT rule broken or local firewall blocking |
| All services red after password change | Wrong format submitted; engine still using old creds → resubmit |

## After every change, run this checklist

- [ ] Service test from internal (`localhost`)
- [ ] Service test from another box on LAN
- [ ] Service test from external IP (via your VPN-attached laptop)
- [ ] Confirm AD auth still works
- [ ] Wait 5 min, check scoreboard
- [ ] If still red, check logs (`journalctl -u <service>`, Event Viewer)

## Useful test commands

```bash
# Linux from your VPN'd laptop
ssh -o StrictHostKeyChecking=no user@172.27.X.101 'id'
curl -ks https://172.27.X.102/ -o /dev/null -w '%{http_code}\n'
dig +short @172.27.X.103 rrintel.internal
```

```powershell
# From the DC itself
Resolve-DnsName rrintel.internal -Server 172.21.0.103
nltest /dsgetdc:rrintel.internal
Test-NetConnection -ComputerName 172.21.0.103 -Port 53
```
