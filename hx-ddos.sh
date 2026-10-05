#!/bin/bash
# hx-ddos — lọc DDoS trên máy node Reality (28/09/2026, sau đợt flood UDP cổng ngẫu nhiên + dội SSH vào node China).
#
#   hx-ddos on | off | status | boot | unboot   (cấu hình ở /etc/hx-ddos.conf: PORT [nhiều cổng cách dấu cách],
#   ALLOW_SSH; boot = tự bật khi khởi động). Sửa dễ nhất qua menu: hyx → 25.
#
# Chuỗi HX-DDOS chèn đầu INPUT:
#   - kết nối đã có (ESTABLISHED/RELATED) → cho qua (phản hồi UDP game/thoại của khách, DNS, relay đều là chiều ra)
#   - SSH chỉ từ ALLOW_SSH, còn lại bỏ (hết cảnh MaxStartups đầy, không vào được máy)
#   - cổng node: mỗi IP tối đa 30 kết nối mới/giây (burst 60), vượt thì bỏ SYN
#   - mọi UDP/TCP mới khác → bỏ (Reality chỉ dùng TCP; flood UDP cổng ngẫu nhiên chết ở đây)
# Gói bị bỏ ở INPUT thì entry conntrack chưa "confirm" nên không làm đầy bảng conntrack.
# Không chống được flood đủ lớn để nhà mạng chặn IP (Gbit) — cái đó phải lọc ở Security Group / nhà cung cấp.
set -u
CONF=/etc/hx-ddos.conf
[ -f "$CONF" ] && . "$CONF"
PORT="${PORT:-3241}"
ALLOW_SSH="${ALLOW_SSH:-43.133.42.80 103.5.209.17 103.5.209.20}"
C=HX-DDOS

off() {
    for T in iptables ip6tables; do
        command -v $T >/dev/null || continue
        while $T -D INPUT -j $C 2>/dev/null; do :; done
        $T -F $C 2>/dev/null; $T -X $C 2>/dev/null
        $T -F HX-SSH 2>/dev/null; $T -X HX-SSH 2>/dev/null
    done
    echo "hx-ddos: da go"
}

on() {
    command -v iptables >/dev/null || { DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables >/dev/null 2>&1 || yum install -y -q iptables; }
    sysctl -qw net.ipv4.tcp_syncookies=1 net.ipv4.tcp_max_syn_backlog=4096 net.core.netdev_max_backlog=5000 2>/dev/null
    off >/dev/null
    for T in iptables ip6tables; do
        command -v $T >/dev/null || continue
        [ $T = ip6tables ] && ! ip -6 addr show scope global | grep -q inet6 && continue
        $T -N $C
        $T -A $C -i lo -j RETURN
        # SSH lạ bị bỏ cả khi kết nối ĐÃ mở (đặt trước ESTABLISHED) — không thì các phiên dội SSH mở từ
        # trước vẫn chiếm MaxStartups, chính mình không vào được (dính 28/09 trên CHINA 2)
        $T -N HX-SSH
        if [ $T = iptables ]; then for ip in $ALLOW_SSH; do $T -A HX-SSH -s "$ip" -j RETURN; done; fi
        $T -A HX-SSH -j DROP
        $T -A $C -p tcp --dport 22 -j HX-SSH
        $T -A $C -p tcp --dport 22 -j RETURN   # quay về từ HX-SSH = IP được phép; thiếu dòng này là rơi DROP cuối (dính 28/09 CHINA 4)
        $T -A $C -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
        $T -A $C -m conntrack --ctstate INVALID -j DROP
        if [ $T = iptables ]; then
            $T -A $C -p icmp -m limit --limit 20/second --limit-burst 40 -j RETURN
            $T -A $C -p icmp -j DROP
        else
            $T -A $C -p ipv6-icmp -j RETURN
        fi
        # PORT có thể là nhiều cổng cách nhau dấu cách (vd "80 443" — máy chạy 2 node)
        for P in $PORT; do
            $T -A $C -p tcp --dport "$P" --syn -m hashlimit --hashlimit-name "hx$T$P" --hashlimit-mode srcip \
                --hashlimit-above 30/second --hashlimit-burst 60 -j DROP
            $T -A $C -p tcp --dport "$P" -j RETURN
        done
        $T -A $C -j DROP
        $T -I INPUT 1 -j $C
    done
    # Luật ctstate ở trên nạp conntrack → máy 800 MB mặc định chỉ 6656 mục, bị dội kết nối / đo ITDOG
    # liên tục là "table full, dropping packet" (03/10). Nâng (không hạ) + nạp module sớm khi khởi động.
    ct=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)
    if [ "$ct" -gt 0 ]; then
        { echo "# hx-ddos: bang conntrack du cho node proxy"
          [ "$ct" -lt 65536 ] && echo "net.netfilter.nf_conntrack_max = 65536"
          echo "net.netfilter.nf_conntrack_tcp_timeout_established = 7200"; } > /etc/sysctl.d/93-hx-ddos-conntrack.conf
        echo nf_conntrack > /etc/modules-load.d/hx-ddos-conntrack.conf
        sysctl -q -p /etc/sysctl.d/93-hx-ddos-conntrack.conf 2>/dev/null
    fi
    echo "hx-ddos: bat — cong $PORT, SSH tu: $ALLOW_SSH, conntrack $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
}

status() {
    iptables -L $C -nv --line-numbers 2>/dev/null | head -30 || echo "chua bat"
}

install_boot() {
    cat > /etc/systemd/system/hx-ddos.service <<'UNIT'
[Unit]
Description=HX anti-DDoS filter (iptables HX-DDOS)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/hx-ddos on
ExecStop=/usr/local/sbin/hx-ddos off

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable hx-ddos.service >/dev/null 2>&1 && echo "hx-ddos: tu bat khi khoi dong"
}

case "${1:-status}" in
    on) on ;;
    boot) install_boot ;;
    unboot) systemctl disable hx-ddos.service >/dev/null 2>&1; echo "hx-ddos: khong tu bat khi khoi dong" ;;
    off) off ;;
    *) status ;;
esac
