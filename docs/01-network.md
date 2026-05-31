# 01 — Network

## RR Intel topology (confirmed from briefing slide + transcript)

```
                          INTERNET / Org scoring engine + Red team
                                    |
                          Upstream router .1 (OUT OF SCOPE — do not touch)
                                    |
                     Transit 172.21.1.0/30
                                    |
                              pfSense (thebox)
                              WAN  172.21.1.2/30
                              LAN  172.21.0.254/24
                                    |
                          ─────────────┬────────────┬────────────
                          |            |            |
                  blacklist .101  concierge .102  cabal .103
                  Debian 13       Fedora 43       Win Server 2022
                  DATABASE        WEB             AD DC + DNS
```

External (NAT) address: `172.27.<team>.0/24` — e.g. team 17 → `172.27.17.x`. **All scored services must work via the external IP.**

Internal addressing: `172.21.0.0/24`

| Host | Internal IP | External IP (NAT 1:1) | OS | Role |
|---|---|---|---|---|
| blacklist | 172.21.0.101 | 172.27.X.101 | Debian 13 | Database |
| concierge | 172.21.0.102 | 172.27.X.102 | Fedora 43 | Web server |
| cabal | 172.21.0.103 | 172.27.X.103 | Windows Server 2022 | Domain Controller (`rrintel.internal`) + DNS |
| thebox (pfSense) | LAN .254 / WAN .2 | — | pfSense | Firewall |

## Transit `172.21.1.0/30`

- `.1` → upstream router, **out of scope, do not scan, do not touch**
- `.2` → pfSense WAN
- `.3` → only present during practice round (extra firewall for messing around)

## NAT

- 1:1 NAT: inside-IP ↔ outside-IP map one-to-one
- Internal LAN: `172.21.0.0/24`
- External assignment: `172.27.0.0/16`, specifically `172.27.<team>.0/24`
- Scoring engine hits external IPs, so services must bind to LAN interface and pfSense must NAT them through

## Service / scoring-engine network behavior

- Scoring engine is **external** — outside pfSense
- It **reuses + rotates IPs**
- It lives **on the same subnet as red team IPs** — you cannot distinguish them by source IP alone
- Therefore: **block individual IPs only after confirming red team behavior**, never block /24s
- Allowlists are safer than denylists for inbound scored ports

## Internal AD authentication

- Almost every scoring check uses AD auth against `rrintel.internal`
- DC is on cabal (172.21.0.103)
- If DC is down → web/login checks cascade red
- Concierge web auth → AD; Blacklist DB users may also be AD-bound
- DNS for the domain is on the DC

## VPN access (operator side, not service side)

- WireGuard config available **after the round starts**, download from portal
- Only routes to **your team's 4 VMs** — everything else firewalled off
- Recommended to pre-install WireGuard client; download config during the 5-min grace period

## Scoreboard / scoring lag

- Check interval: random 2-3 min per service (not synchronized round)
- Portal upload lag: 2-3 min after scoring engine logs the result
- End-to-end visibility lag after a fix: **~5 min**, sometimes more
- Do not panic-react in <5min windows; you'll over-correct

## Practice round vs comp differences (network-relevant)

| | Practice | Comp |
|---|---|---|
| Boxes | Mint + Alma + Win + pfSense | Debian + Fedora + Win + pfSense |
| Red team active | No | Yes |
| Orange team active | No | Yes |
| CCS on pfSense | No | Yes |
| Time limit | None (2 days) | 6h + 5min grace |
| Extra firewall on .3 | Yes (mess around) | No |

## Do-not-scan list

- `172.21.1.1` (upstream gateway)
- `172.21.1.2` (your own pfSense WAN — pointless and flagged)
- Any IP outside your team's external /24 (other teams)
- Red team subnet
- Anything not your VM or part of an inject scope
