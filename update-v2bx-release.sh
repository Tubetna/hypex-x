#!/bin/bash
# Cap nhat binary V2bX tren 1 may node tu GitHub release (giu ban cu .v109.bak), chay bang root:
#   sshp.py <ip> <user> <pass> < update-v2bx-release.sh   ·   jump_run.py ... (may sau hx-ddos)
set -e
case "$(uname -m)" in x86_64) S=amd64 ;; aarch64) S=arm64 ;; *) echo "arch la: $(uname -m)"; exit 1 ;; esac
BIN=/usr/bin/V2bX-bin/V2bX
echo "$(hostname) · $S · Limited 10 phut truoc: $(journalctl -u V2bX --since -10min --grep Limited -o cat 2>/dev/null | wc -l)"
rm -rf /tmp/v1010 /tmp/v1010.zip
curl -fsSL -m 180 -o /tmp/v1010.zip "https://github.com/Tubetna/hypex-x/releases/download/v1.0.10/V2bX-linux-$S.zip"
command -v unzip >/dev/null || { apt-get install -y -qq unzip >/dev/null 2>&1 || dnf install -y -q unzip >/dev/null 2>&1 || yum install -y -q unzip >/dev/null 2>&1; }
unzip -oq /tmp/v1010.zip V2bX -d /tmp/v1010
[ -s /tmp/v1010/V2bX ] || { echo "tai/giai nen loi"; exit 1; }
[ -f $BIN.v109.bak ] || cp -a $BIN $BIN.v109.bak
install -m 755 /tmp/v1010/V2bX $BIN
systemctl restart V2bX
sleep 12
echo "V2bX: $(systemctl is-active V2bX)"
journalctl -u V2bX --since -15s -o cat | grep -E 'Added [0-9]+ new users|panic|fatal' | head -6
echo "accepted 10s: $(journalctl -u V2bX --since -10s -o cat | grep -c accepted)"
rm -rf /tmp/v1010 /tmp/v1010.zip
