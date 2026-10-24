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
#
# Canh gác khẩn cấp (24/10/2026):  hx-ddos guard-on | guard-off | guard-status | lock | unlock
#   Dịch vụ hx-guard đo card mạng mỗi GUARD_STEP giây. Bình thường node proxy có vào ≈ ra (đo 20–24/10 trên 7 máy
#   China: phần thừa vào − ra cao nhất ~19 Mbit/s, vào ≤ 1,2 lần ra); bị flood thì vào lớn mà ra gần 0. Đủ
#   GUARD_SAMPLES lượt liên tiếp có (vào − ra ≥ GUARD_EXCESS_MBPS Mbit/s hoặc ≥ GUARD_EXCESS_PPS gói/s) và
#   vào ≥ GUARD_RATIO10/10 lần ra → KHOÁ: chuỗi HX-LOCK đầu INPUT bỏ im mọi gói (cả ping, máy trông như chết),
#   chỉ chừa SSH từ ALLOW_SSH + kết nối máy tự mở ra (agent báo panel), dừng V2bX.
#   Mở lại khi yên liên tục GUARD_HOLD giây (lần khoá thứ k trong 24 h: GUARD_HOLD × 2^(k-1), tối đa 3600).
#   `lock` tay thì chỉ `unlock` tay mới mở. GUARD_DRYRUN=1: chỉ ghi log "sẽ khoá", không khoá thật.
#   Log: /var/log/hx-guard.log (+ journalctl -t hx-guard).
set -u
CONF=/etc/hx-ddos.conf
[ -f "$CONF" ] && . "$CONF"
PORT="${PORT:-3241}"
ALLOW_SSH="${ALLOW_SSH:-43.133.42.80 103.5.209.17 103.5.209.20}"
GUARD_STEP="${GUARD_STEP:-5}"
GUARD_SAMPLES="${GUARD_SAMPLES:-4}"
GUARD_EXCESS_MBPS="${GUARD_EXCESS_MBPS:-40}"
GUARD_EXCESS_PPS="${GUARD_EXCESS_PPS:-30000}"
GUARD_RATIO10="${GUARD_RATIO10:-15}"    # vào ≥ 1,5 × ra
GUARD_HOLD="${GUARD_HOLD:-600}"
GUARD_DRYRUN="${GUARD_DRYRUN:-0}"
GUARD_DEV_FILE="${GUARD_DEV_FILE:-/proc/net/dev}"   # đổi được để thử bằng số giả
C=HX-DDOS
L=HX-LOCK
GDIR=/run/hx-guard
GLOG=/var/log/hx-guard.log

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
        # đang khoá khẩn cấp thì HX-LOCK phải đứng trên HX-DDOS
        if $T -S $L >/dev/null 2>&1; then
            while $T -D INPUT -j $L 2>/dev/null; do :; done
            $T -I INPUT 1 -j $L
        fi
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

# ── Canh gác khẩn cấp ─────────────────────────────────────────────────────────
glog() { echo "$(date '+%F %T') $*" >> "$GLOG"; logger -t hx-guard -- "$*" 2>/dev/null; }

guard_iface() { ip route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i+1); exit }}'; }

# "rx_bytes rx_gói tx_bytes tx_gói" của card $1 (dòng "eth0: 1 2 …" hoặc "eth0:1 2 …")
read_dev() {
    awk -v d="$1" '{ sub(/^ +/, ""); i = index($0, ":"); if (i && substr($0, 1, i-1) == d) {
        split(substr($0, i+1), f, " "); print f[1], f[2], f[9], f[10]; exit } }' "$GUARD_DEV_FILE"
}

is_locked() { [ -f "$GDIR/locked" ] || iptables -S $L >/dev/null 2>&1; }

lock_apply() {   # lock_apply <lý do> <1 = khoá tay> <giây yên để mở>
    mkdir -p "$GDIR"
    for T in iptables ip6tables; do
        command -v $T >/dev/null || continue
        $T -N $L 2>/dev/null || $T -F $L
        $T -A $L -i lo -j RETURN
        if [ $T = iptables ]; then for ip in $ALLOW_SSH; do $T -A $L -s "$ip" -p tcp --dport 22 -j RETURN; done; fi
        # chiều về của kết nối máy tự mở (agent báo panel, DNS, cập nhật); gói flood là NEW, bị bỏ trước khi vào bảng
        $T -A $L -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null
        $T -A $L -j DROP
        while $T -D INPUT -j $L 2>/dev/null; do :; done
        $T -I INPUT 1 -j $L
    done
    systemctl stop V2bX 2>/dev/null
    echo "$(date +%s) ${2:-0} ${3:-$GUARD_HOLD} $1" > "$GDIR/locked"
    glog "KHOA: $1"
}

unlock_apply() {
    for T in iptables ip6tables; do
        command -v $T >/dev/null || continue
        while $T -D INPUT -j $L 2>/dev/null; do :; done
        $T -F $L 2>/dev/null; $T -X $L 2>/dev/null
    done
    rm -f "$GDIR/locked"
    systemctl start V2bX 2>/dev/null
    glog "MO LAI: $1"
}

hold_for_new_lock() {   # ghi lần khoá; trả số giây phải yên (lần thứ k trong 24 h: GUARD_HOLD × 2^(k-1), tối đa 3600)
    local now k h
    now=$(date +%s); mkdir -p /var/lib/hx-guard
    echo "$now" >> /var/lib/hx-guard/locks
    k=$(awk -v t=$((now - 86400)) '$1 >= t' /var/lib/hx-guard/locks | wc -l)
    h=$GUARD_HOLD
    while [ "$k" -gt 1 ] && [ "$h" -lt 3600 ]; do h=$((h * 2)); k=$((k - 1)); done
    [ "$h" -gt 3600 ] && h=3600
    echo "$h"
}

guard_run() {
    local dev rb rp tb tp rb2 rp2 tb2 tp2 drb drp dtb dtp rx_m tx_m rx_p tx_p flood bad=0 quiet=0
    local since manual hold reason msg
    mkdir -p "$GDIR"
    dev="${GUARD_IFACE:-$(guard_iface)}"
    [ -n "$dev" ] || { glog "khong tim thay card mang"; exit 1; }
    glog "bat canh gac: card $dev, vao-ra >= ${GUARD_EXCESS_MBPS} Mbit/s hoac >= ${GUARD_EXCESS_PPS} goi/s va vao >= ${GUARD_RATIO10}/10 x ra, ${GUARD_SAMPLES}x${GUARD_STEP}s; mo lai khi yen ${GUARD_HOLD}s$([ "$GUARD_DRYRUN" = 1 ] && echo ' — CHAY THU, khong khoa that')"
    read -r rb rp tb tp < <(read_dev "$dev")
    while sleep "$GUARD_STEP"; do
        read -r rb2 rp2 tb2 tp2 < <(read_dev "$dev")
        [ -n "${tp2:-}" ] && [ -n "${tp:-}" ] || { rb=${rb2:-} rp=${rp2:-} tb=${tb2:-} tp=${tp2:-}; continue; }
        drb=$((rb2 - rb)); drp=$((rp2 - rp)); dtb=$((tb2 - tb)); dtp=$((tp2 - tp))
        rb=$rb2 rp=$rp2 tb=$tb2 tp=$tp2
        [ $drb -lt 0 ] || [ $drp -lt 0 ] || [ $dtb -lt 0 ] || [ $dtp -lt 0 ] && continue   # bộ đếm quay vòng / card dựng lại
        rx_m=$((drb * 8 / 1000000 / GUARD_STEP)); tx_m=$((dtb * 8 / 1000000 / GUARD_STEP))
        rx_p=$((drp / GUARD_STEP)); tx_p=$((dtp / GUARD_STEP))
        echo "$(date +%s) $rx_m $tx_m $rx_p $tx_p" > "$GDIR/last"

        if [ -f "$GDIR/locked" ]; then
            read -r since manual hold reason < "$GDIR/locked"
            # tự cập nhật / ai đó bật lại V2bX trong lúc khoá → tắt lại
            systemctl is-active -q V2bX 2>/dev/null && systemctl stop V2bX 2>/dev/null
            [ "$manual" = 1 ] && continue
            # lúc khoá máy không trả lời gì, ra ≈ 0 → chỉ xét chiều vào
            if [ $rx_m -lt $((GUARD_EXCESS_MBPS / 2)) ] && [ $rx_p -lt $((GUARD_EXCESS_PPS / 2)) ]; then
                quiet=$((quiet + GUARD_STEP))
            else
                quiet=0
            fi
            if [ $quiet -ge "${hold:-$GUARD_HOLD}" ]; then unlock_apply "yen ${quiet}s (khoa tu $(date -d @"$since" '+%F %T'))"; quiet=0; bad=0; fi
            continue
        fi

        flood=0
        [ $((rx_m - tx_m)) -ge "$GUARD_EXCESS_MBPS" ] && [ $((drb * 10)) -ge $((GUARD_RATIO10 * dtb)) ] && flood=1
        [ $((rx_p - tx_p)) -ge "$GUARD_EXCESS_PPS" ] && [ $((drp * 10)) -ge $((GUARD_RATIO10 * dtp)) ] && flood=1
        [ $flood = 1 ] && bad=$((bad + 1)) || bad=0
        if [ $bad -ge "$GUARD_SAMPLES" ]; then
            msg="vao ${rx_m} Mbit/s ${rx_p} goi/s, ra ${tx_m} Mbit/s ${tx_p} goi/s (${bad} luot x ${GUARD_STEP}s)"
            bad=0; quiet=0
            if [ "$GUARD_DRYRUN" = 1 ]; then glog "CHAY THU — se khoa: $msg"; continue; fi
            hold=$(hold_for_new_lock)
            lock_apply "$msg; mo lai khi yen ${hold}s" 0 "$hold"
        fi
    done
}

guard_on() {
    # đường chuẩn là /usr/local/sbin/hx-ddos (hyx + hx-ddos.service gọi chỗ đó); máy cài tay để ở chỗ khác thì chép sang
    local self; self=$(readlink -f "$0")
    if [ "$self" != /usr/local/sbin/hx-ddos ]; then
        install -m 755 "$self" /usr/local/sbin/hx-ddos && ln -sfn /usr/local/sbin/hx-ddos "$self"
    fi
    cat > /etc/systemd/system/hx-guard.service <<'UNIT'
[Unit]
Description=HX guard: khoa khan cap khi bi flood (hx-ddos guard-run)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/sbin/hx-ddos guard-run
Restart=always
RestartSec=5
Nice=-5

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable hx-guard.service >/dev/null 2>&1
    systemctl restart hx-guard.service
    sleep 1
    systemctl is-active -q hx-guard.service && echo "hx-guard: dang canh gac" || { echo "hx-guard: KHONG chay duoc"; return 1; }
}

guard_off() {
    systemctl disable --now hx-guard.service >/dev/null 2>&1
    is_locked && unlock_apply "tat canh gac"
    echo "hx-guard: da tat"
}

guard_status() {
    local t rx tx rp tp since manual hold reason
    systemctl is-active -q hx-guard.service 2>/dev/null && echo "canh gac: BAT" || echo "canh gac: tat"
    if [ -f "$GDIR/last" ]; then
        read -r t rx tx rp tp < "$GDIR/last"
        echo "do luc $(date -d @"$t" '+%T'): vao $rx Mbit/s $rp goi/s · ra $tx Mbit/s $tp goi/s"
    fi
    if [ -f "$GDIR/locked" ]; then
        read -r since manual hold reason < "$GDIR/locked"
        echo "TRANG THAI: DANG KHOA tu $(date -d @"$since" '+%F %T')$([ "$manual" = 1 ] && echo ' (khoa tay — mo bang: hx-ddos unlock)') — $reason"
    else
        echo "trang thai: binh thuong"
    fi
    [ -f "$GLOG" ] && { echo "--- log gan nhat:"; tail -5 "$GLOG"; }
}

case "${1:-status}" in
    on) on ;;
    guard-run) guard_run ;;
    guard-on) guard_on ;;
    guard-off) guard_off ;;
    guard-status) guard_status ;;
    lock) lock_apply "khoa tay${2:+: $2}" 1 0 ;;
    unlock) unlock_apply "mo tay" ;;
    boot) install_boot ;;
    unboot) systemctl disable hx-ddos.service >/dev/null 2>&1; echo "hx-ddos: khong tu bat khi khoi dong" ;;
    off) off ;;
    *) status ;;
esac
