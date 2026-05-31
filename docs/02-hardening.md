# 02 — Hardening cheatsheets

> Priority order on every box: **baseline → kick out attacker → harden → leave alone**.
> Before changing anything, snapshot the current state to a notes file. Document for IR reports + injects.

## Why this doc exists (read once)

A "hardening" step is anything that makes a box harder to abuse without changing what the box *does for its users*. The mistake newcomers make is conflating these:

- **Recon** (read-only): looking at what's there. Cannot break anything. Always safe.
- **Containment**: disabling / killing / unplugging something the attacker is using. Can break a scored service if you misidentify what's legit.
- **Hardening**: changing config to raise the bar (firewall rules, SSH config, password policy). Can break a scored service if the change closes a port the scoring engine needs.

Do them in that order. Always **recon → contain → harden**, never the other way around. If you harden before recon, you'll firewall off the AD bind that authenticates the scoring engine and you'll wonder why the scoreboard went red.

## How to use this doc during the round

1. Open the section for the box you're working on (Blacklist / Concierge / Cabal / pfSense).
2. Copy-paste the **recon** block first, into the box's terminal. Read the output. Save it somewhere (paste into your shared note doc).
3. Decide what looks abnormal. The doc tells you what "normal" roughly looks like underneath each block.
4. **Don't** copy-paste the "stop the bleeding" block blindly — those commands disable things. Pick the lines that match your actual finding.

## Universal Linux triage (Blacklist + Concierge)

### Recon (read-only, do these first)

> These commands only *read* — no system state changes. Run them in order and screenshot or copy the output into your notes before you change anything. The point is to know what "normal looks like on this box" so you can spot deltas later.

```bash
# users
cat /etc/passwd
awk -F: '($3 < 1000) {print}' /etc/passwd     # system accounts
awk -F: '($3 >= 1000) {print}' /etc/passwd    # human accounts
cat /etc/shadow | awk -F: '($2!~"!"&&$2!~"\\*"){print $1}'  # accounts with passwords set

# privs
cat /etc/sudoers
ls -la /etc/sudoers.d/
getent group sudo wheel admin

# network
ss -tlnp
ss -ulnp
ip a
ip route
cat /etc/resolv.conf

# services
systemctl list-units --type=service --state=running
systemctl list-unit-files --state=enabled

# scheduled
crontab -l                   # root
for u in $(awk -F: '{print $1}' /etc/passwd); do crontab -l -u "$u" 2>/dev/null; done
ls -la /etc/cron.d/ /etc/cron.daily/ /etc/cron.hourly/ /etc/cron.weekly/ /etc/cron.monthly/
systemctl list-timers --all

# persistence / backdoors
find / -perm -4000 -type f 2>/dev/null               # SUID
find / -perm -2000 -type f 2>/dev/null               # SGID
find / -nouser -o -nogroup 2>/dev/null
find /home /root -name "authorized_keys" -exec ls -la {} \; -exec cat {} \;
find / -name "*.bash_history" -exec ls -la {} \; 2>/dev/null

# recently modified
find /etc -mtime -7 -type f
find /var/www -mtime -7 -type f 2>/dev/null
find /tmp /var/tmp /dev/shm -type f -ls

# processes
ps auxf
ps -eo pid,ppid,user,cmd --forest
lsof -i -n -P 2>/dev/null
```

### Stop the bleeding (after evidence captured)

```bash
# disable, don't delete (you may need to revert)
usermod -L <baduser>
chage -E 0 <baduser>

# kill SSH keys (back up first)
cp /home/<user>/.ssh/authorized_keys ~/evidence/<user>-authorized_keys.bak
: > /home/<user>/.ssh/authorized_keys

# disable cron entries (rename, don't delete)
mv /etc/cron.d/badjob /etc/cron.d/badjob.disabled

# kill malicious process + capture binary
cp /proc/<pid>/exe ~/evidence/<pid>-exe
sha256sum ~/evidence/<pid>-exe
kill -9 <pid>
```

### Harden SSH

```bash
# /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication yes      # only flip to no AFTER you confirm scoring uses keys
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers <only the accounts that need ssh>

# apply
sshd -t && systemctl restart sshd
```

### Local firewall (Debian: ufw / nftables; Fedora: firewalld)

Debian:
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 3306/tcp   # or whichever DB port — verify first
ufw enable
```

Fedora:
```bash
firewall-cmd --set-default-zone=public
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

Confirm scored ports stay open. **Never** firewall the LAN-side AD lookups.

---

## Blacklist (Debian 13 / DATABASE)

Likely apps: PostgreSQL / MySQL / MariaDB. Check ports `5432`, `3306`, `1433`.

```bash
# detect
ss -tlnp | grep -E '5432|3306|1433|27017|6379'
systemctl list-units --type=service | grep -iE 'postgres|mysql|maria|mongo|redis|mssql'

# Postgres triage
sudo -u postgres psql -c "\du"                        # roles
sudo -u postgres psql -c "SELECT usename FROM pg_shadow WHERE passwd IS NULL;"   # passwordless
cat /etc/postgresql/*/main/pg_hba.conf                # auth rules
cat /etc/postgresql/*/main/postgresql.conf | grep listen_addresses

# MySQL/MariaDB triage
mysql -e "SELECT User,Host,authentication_string FROM mysql.user;"
mysql -e "SELECT User,Host FROM mysql.user WHERE authentication_string='';"  # passwordless
mysql -e "SELECT User,Host FROM mysql.user WHERE User='';"                   # anonymous
mysql -e "SHOW GRANTS FOR 'root'@'%';"
cat /etc/mysql/mariadb.conf.d/50-server.cnf | grep bind-address
```

Hardening priorities:
- [ ] Drop anonymous and `%`-host root users
- [ ] Bind listener to LAN IP, not `0.0.0.0`, unless scored externally
- [ ] Set a strong password on every db user
- [ ] Disable `LOAD DATA LOCAL INFILE` (MySQL) if not used
- [ ] Backup the DB once you've stabilized: `pg_dumpall` / `mysqldump --all-databases`

---

## Concierge (Fedora 43 / WEB)

Likely stack: nginx/Apache + PHP/Node + AD auth (LDAP/SSSD). Look for it:

```bash
ss -tlnp | grep -E ':80|:443|:8080|:8443'
systemctl list-units --type=service | grep -iE 'httpd|nginx|apache|php-fpm|node|gunicorn'
ls /var/www/ 2>/dev/null
ls /opt/ /srv/

# AD / SSSD
systemctl status sssd
realm list
cat /etc/sssd/sssd.conf 2>/dev/null
```

Webshell hunt:
```bash
grep -RElE 'eval\(|base64_decode\(|system\(|exec\(|shell_exec\(|assert\(' /var/www 2>/dev/null
find /var/www -type f -newer /etc/hostname -mtime -14   # recently touched
find /var/www -name '*.php' -size +50k                  # giant php files often shells
```

SELinux:
```bash
getenforce       # should be Enforcing
setenforce 1     # don't disable it
ausearch -m AVC -ts recent
```

Hardening priorities:
- [ ] Audit admin users in the web app DB
- [ ] Disable directory listing
- [ ] Set `X-Frame-Options`, `Content-Security-Policy`, `Strict-Transport-Security`
- [ ] Patch the app if a CVE is obvious — but **only after** baseline functions confirmed
- [ ] Confirm AD-backed login works end-to-end (this is what scoring engine tests)

---

## Cabal (Windows Server 2022 / DC + DNS)

```powershell
# recon
Get-LocalUser
Get-LocalGroupMember Administrators
Get-ADUser -Filter * -Properties LastLogonDate,PasswordLastSet | Format-Table Name,Enabled,PasswordLastSet
Get-ADGroupMember "Domain Admins"
Get-ADGroupMember "Enterprise Admins"
Get-ADGroupMember "Schema Admins"

# services / scheduled
Get-Service | Where-Object Status -eq Running
Get-ScheduledTask | Where-Object {$_.State -ne 'Disabled'} | Format-Table TaskName,TaskPath,State

# persistence
Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
Get-CimInstance Win32_StartupCommand | Format-List
Get-Service | Where-Object {$_.StartType -eq 'Automatic'}

# DNS
Get-DnsServerZone
Get-DnsServerResourceRecord -ZoneName rrintel.internal

# sessions / shares
Get-SmbShare
Get-SmbSession
qwinsta
```

Hardening priorities (do NOT disable scoring/orange service accounts):
- [ ] Disable LLMNR and NBT-NS (Group Policy + registry)
  - `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\EnableMulticast = 0`
- [ ] Enable SMB signing
- [ ] Disable SMBv1: `Disable-WindowsOptionalFeature -Online -FeatureName smb1protocol`
- [ ] Enable Defender real-time + run quick scan: `Set-MpPreference -DisableRealtimeMonitoring $false; Start-MpScan -ScanType QuickScan`
- [ ] Audit policy: `auditpol /set /category:* /success:enable /failure:enable`
- [ ] Force AD account password reset for any unknown accounts (don't delete)
- [ ] Confirm DNS resolution still works for `rrintel.internal` from outside
- [ ] Backup AD with `ntdsutil` snapshot before major changes

Persistence hunt artifacts to grab:
- WMI subscriptions: `Get-CimInstance -Namespace root/subscription -ClassName __EventFilter`
- Run keys
- Scheduled tasks with weird `Author` or `RunAs SYSTEM`
- Anything in `C:\ProgramData\` recently modified
- Sysmon if installed: `Get-WinEvent -LogName Microsoft-Windows-Sysmon/Operational -MaxEvents 200`

---

## pfSense (thebox / FIREWALL)

WebGUI: https://172.21.0.254 (LAN) or via console.

Tasks:
- [ ] Change pfSense admin password (default `pfsense/pfsense` is assumed compromised)
- [ ] Confirm 1:1 NAT rules for the 3 hosts
- [ ] Inbound WAN rules: allow only scored ports → host
- [ ] Outbound rules: default allow LAN → WAN is fine; tighten if obvious C2 patterns appear
- [ ] Enable logging on the WAN inbound rule for IR evidence
- [ ] Optional: aliases for confirmed red-team IPs, block with logging

**Never** block /16 or /24 — scoring engine + red team share the same subnet.

Useful CLI (option 8 from console menu → shell):
```bash
pfctl -sr                   # show rules
pfctl -ss                   # show states
pfctl -sn                   # show NAT
tcpdump -ni igb1 host 172.21.0.102 and port 80
```
