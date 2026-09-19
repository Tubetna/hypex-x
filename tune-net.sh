#!/usr/bin/env bash
# tune-net.sh — bộ tối ưu mạng cho node V2bX: BBR+fq, buffer TCP, TFO/NoDelay, DNS cache Xray,
# bufferSize 32, journald 300M, V2bX Nice -10. Idempotent, chạy lại bao nhiêu lần cũng được.
# Đo 13/09/2026 (node 33, vantage Hà Nội): ping 761 → 447 ms, tải 24–35 → 41–43 MB/s.
# Dùng: bash tune-net.sh   (hyx menu 22; bộ cài chỉ gọi khi HXtune=1)
# ⚠ 13/09/2026: khách chơi Liên Quân trên node 25/26 báo "khựng hơn" sau khi áp, gỡ thì ổn (đo 100 gói UDP
#   không thấy khác, nhưng khách là thước đo). Node GAME: đừng áp. Node duyệt web/tải: có lợi (ping 761→447 ms).
# Bo tuning mang cho node V2bX (idempotent) — 13/09/2026
set -e
[ "$(id -u)" = 0 ] || { echo "Cần root"; exit 1; }
command -v python3 >/dev/null || { echo "Cần python3 (apt-get install -y python3)"; exit 1; }
IF=$(ip -o -4 route show default | awk '{print $5}')
cat > /etc/sysctl.d/99-hypex-max.conf <<'EOT'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 33554432
net.ipv4.tcp_wmem = 4096 1048576 33554432
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1200
fs.file-max = 1048576
vm.swappiness = 10
EOT
modprobe tcp_bbr 2>/dev/null || true; sysctl -q -p /etc/sysctl.d/99-hypex-max.conf
tc qdisc replace dev $IF root fq 2>/dev/null || true; ip link set $IF txqueuelen 10000
cat > /etc/systemd/system/fq-qdisc.service <<EOT
[Unit]
Description=fq qdisc + txqueuelen for BBR pacing on $IF
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/sbin/tc qdisc replace dev $IF root fq
ExecStart=/sbin/ip link set $IF txqueuelen 10000
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOT
grep -q "^\* soft nofile" /etc/security/limits.conf || printf "* soft nofile 1048576\n* hard nofile 1048576\n" >> /etc/security/limits.conf
mkdir -p /etc/systemd/journald.conf.d; printf "[Journal]\nSystemMaxUse=300M\nMaxRetentionSec=7day\n" > /etc/systemd/journald.conf.d/limit.conf; systemctl restart systemd-journald
mkdir -p /etc/systemd/system/V2bX.service.d
printf "[Service]\nNice=-10\nCPUWeight=1000\nIOWeight=1000\n" > /etc/systemd/system/V2bX.service.d/priority.conf
# Xray: outbound NoDelay/keepalive, DNS cache, bufferSize 32.
# KHONG bat tcpFastOpen o outbound ra Internet: SYN mang du lieu bi WAF mot so site vut im
# (dichvucong.gov.vn treo cho moi khach node 30/33 tu 13/09 den 19/09/2026 vi dong nay).
# Sysctl tcp_fastopen=3 van giu (chi hieu luc khi ung dung tu xin TFO).
# Giu nguyen custom_outbound.json neu no da co outbound rieng (relay...), chi vá sockopt cua "direct".
cp -f /etc/V2bX/custom_outbound.json /etc/V2bX/custom_outbound.json.bak.tune 2>/dev/null || true
cp -f /etc/V2bX/config.json /etc/V2bX/config.json.bak.tune
python3 - <<'PY'
import json, os
p='/etc/V2bX/custom_outbound.json'
try:
    o=json.load(open(p)); assert isinstance(o,list) and o
except Exception:
    o=[{"tag":"direct","protocol":"freedom","settings":{"domainStrategy":"UseIPv4"}},
       {"tag":"block","protocol":"blackhole"}]
for ob in o:
    if ob.get("protocol")!="freedom": continue
    so=ob.setdefault("streamSettings",{}).setdefault("sockopt",{})
    so.pop("tcpFastOpen",None)
    so.update({"tcpNoDelay":True,"tcpKeepAliveIdle":300,"tcpKeepAliveInterval":30})
json.dump(o,open(p,"w"),indent=1)
PY
cat > /etc/V2bX/dns.json <<'EOT'
{"servers":[{"address":"1.1.1.1","port":53,"queryStrategy":"UseIPv4"},{"address":"8.8.8.8","port":53,"queryStrategy":"UseIPv4"},"localhost"],
 "queryStrategy":"UseIPv4","disableCache":false,"tag":"dns_inbound"}
EOT
python3 - <<'PY'
import json
p='/etc/V2bX/config.json'; c=json.load(open(p))
c['Log']['Level']='warning'
for k in c['Cores']:
    if k['Type']=='xray':
        k['Log']['Level']='warning'; k['DnsConfigPath']='/etc/V2bX/dns.json'
        k['OutboundConfigPath']='/etc/V2bX/custom_outbound.json'
        k.setdefault('XrayConnectionConfig',{"handshake":4,"connIdle":30,"uplinkOnly":2,"downlinkOnly":4})['bufferSize']=32
for n in c['Nodes']:
    n.setdefault('Options',{}).setdefault('XrayOptions',{}).update({"EnableDNS":True,"DNSType":"UseIPv4"})
json.dump(c,open(p,'w'),indent=2)
PY
systemctl daemon-reload; systemctl enable fq-qdisc.service >/dev/null 2>&1
systemctl restart V2bX; sleep 5
echo "V2bX=$(systemctl is-active V2bX) cc=$(sysctl -n net.ipv4.tcp_congestion_control) qdisc=$(tc qdisc show dev $IF | head -1 | awk '{print $2}') nice=$(ps -o ni= -p $(systemctl show V2bX -p MainPID --value)) rss=$(( $(ps -o rss= -p $(systemctl show V2bX -p MainPID --value)) /1024 ))MB"
journalctl -u V2bX -n 20 -o cat | grep -iE "error|fail|panic" | grep -v OCSP | head -3
