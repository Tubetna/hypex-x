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
#   Luật gói/s còn đòi byte vào ≥ GUARD_RATIO10/10 lần ra HOẶC gói vào trung bình < GUARD_SMALL_PKT byte: khách tải
#   nặng có gói vào ~1.100 B còn gói ra được card gộp (TSO) → gói/s vào gấp 6 lần ra dù byte vào ≈ ra (26/10 khoá
#   nhầm CHINA 2 B: vào 337 / ra 319 Mbit/s, 38.386 / 5.891 gói/s).
#   chỉ chừa SSH từ ALLOW_SSH + kết nối máy tự mở ra (agent báo panel), dừng V2bX.
#   Từ 01/11/2026 còn đòi thêm gói LẠ ≥ GUARD_STRANGE_PPS gói/s: gói vào chuỗi HX-DDOS mà không thuộc kết nối
#   đã có (bỏ qua lo, SSH được phép, ESTABLISHED) — flood thật là gói NEW/INVALID tới cổng node hoặc cổng ngẫu nhiên.
#   CHINA 1 bị khoá nhầm 3 lần 31/10–01/11: vào 92–122 / ra 22–57 Mbit/s nhưng gần hết là ESTABLISHED (khách tải
#   UDP/QUIC nặng, đường về TQ nghẽn), dừng V2bX là vào tụt về 0,1 Mbit/s. GUARD_STRANGE_PPS=0 = bỏ điều kiện này.
#   Mở lại khi yên liên tục GUARD_HOLD giây (lần khoá thứ k trong 24 h: GUARD_HOLD × 2^(k-1), tối đa 3600).
#   `lock` tay thì chỉ `unlock` tay mới mở. GUARD_DRYRUN=1: chỉ ghi log "sẽ khoá", không khoá thật.
#   Log: /var/log/hx-guard.log (+ journalctl -t hx-guard).
#
# Cổng riêng mỗi khách (01/11/2026): FPORT="20000:29999" trong /etc/hx-ddos.conf → chuỗi nat HX-FPORT chuyển mọi
#   TCP tới dải này về cổng node (cổng đầu của PORT). Panel cấp mỗi khách 1 cổng trong dải (FakePortService) →
#   lúc khoá, hx-guard bắt mẫu 3 s bằng tcpdump và ghi "cong bi dap" → tra hx_user_port ra khách làm lộ sub.
#   Security Group phải mở TCP cả dải. FPORT rỗng = tắt.
#
# Hysteria2 nhảy cổng (03/11/2026): UPORT="30000:30999" + UPORT_TO="30443" → nhận UDP vào cổng node Hy2 (UPORT_TO,
#   giới hạn luồng mới mỗi IP) + nat HX-FPORT chuyển mọi UDP trong dải UPORT về UPORT_TO. Security Group phải mở UDP
#   cả dải. UPORT rỗng = tắt (mọi UDP mới vẫn bị bỏ như cũ).
#
# Báo panel (02/11/2026): khoá tự động → POST https://<ApiHost>/hxguard/push.php (X-Key = ApiKey của V2bX, như
#   hx-sharescan) kèm số đo + top 5 cổng bị đập; mở lại (sau khoá tự động) → 1 tin nữa. Panel `monitor:guard` tra
#   cổng ra khách rồi mail admin. Gửi nền, thử lại ~2,5 phút. `hx-ddos guard-test`: thử cả đường (bắt SYN 3 s + gửi
#   1 tin khoá + 1 tin mở, đánh dấu THỬ) mà KHÔNG khoá máy.
set -u
CONF=/etc/hx-ddos.conf
[ -f "$CONF" ] && . "$CONF"
PORT="${PORT:-3241}"
FPORT="${FPORT:-}"
UPORT="${UPORT:-}"
UPORT_TO="${UPORT_TO:-}"
ALLOW_SSH="${ALLOW_SSH:-43.133.42.80 103.5.209.17 103.5.209.20}"
GUARD_STEP="${GUARD_STEP:-5}"
GUARD_SAMPLES="${GUARD_SAMPLES:-4}"
GUARD_EXCESS_MBPS="${GUARD_EXCESS_MBPS:-40}"
GUARD_EXCESS_PPS="${GUARD_EXCESS_PPS:-30000}"
GUARD_RATIO10="${GUARD_RATIO10:-15}"    # vào ≥ 1,5 × ra
GUARD_SMALL_PKT="${GUARD_SMALL_PKT:-300}"   # gói vào TB dưới mức này (byte) = flood gói nhỏ
GUARD_STRANGE_PPS="${GUARD_STRANGE_PPS:-2000}"   # gói lạ/giây (không thuộc kết nối đã có) tối thiểu để coi là flood
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
        while $T -t nat -D PREROUTING -j HX-FPORT 2>/dev/null; do :; done
        $T -t nat -F HX-FPORT 2>/dev/null; $T -t nat -X HX-FPORT 2>/dev/null
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
        if [ -n "$UPORT" ] && [ -n "$UPORT_TO" ]; then
            $T -A $C -p udp --dport "$UPORT_TO" -m conntrack --ctstate NEW -m hashlimit --hashlimit-name "hxu$T" \
                --hashlimit-mode srcip --hashlimit-above 20/second --hashlimit-burst 40 -j DROP
            $T -A $C -p udp --dport "$UPORT_TO" -j RETURN
        fi
        $T -A $C -j DROP
        $T -I INPUT 1 -j $C
        # dải cổng riêng mỗi khách → cổng node; nat chạy trước INPUT nên luật cổng node ở trên áp luôn cho dải
        if [ -n "$FPORT" ] || { [ -n "$UPORT" ] && [ -n "$UPORT_TO" ]; }; then
            $T -t nat -N HX-FPORT
            [ -n "$FPORT" ] && $T -t nat -A HX-FPORT -p tcp --dport "$FPORT" -j REDIRECT --to-ports "${PORT%% *}"
            [ -n "$UPORT" ] && [ -n "$UPORT_TO" ] && $T -t nat -A HX-FPORT -p udp --dport "$UPORT" -j REDIRECT --to-ports "$UPORT_TO"
            $T -t nat -I PREROUTING 1 -j HX-FPORT
        fi
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
    echo "hx-ddos: bat — cong $PORT${FPORT:+ (+ dai $FPORT)}${UPORT:+, UDP $UPORT -> $UPORT_TO}, SSH tu: $ALLOW_SSH, conntrack $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
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

# Tổng gói LẠ đã vào chuỗi HX-DDOS (v4 + v6): mọi luật trừ lo, SSH, ESTABLISHED; cộng gói SSH lạ bị HX-SSH bỏ.
# Chuỗi chưa bật → 0 (khi đó điều kiện gói lạ luôn trượt, nên guard_run bỏ qua nó).
read_strange() {
    local T s=0 n
    for T in iptables ip6tables; do
        command -v $T >/dev/null || continue
        n=$($T -L $C -v -x -n 2>/dev/null | awk 'NR > 2 && $6 != "lo" && !/dpt:22/ && !/RELATED,ESTABLISHED/ { s += $1 } END { print s + 0 }')
        s=$((s + n))
        n=$($T -L HX-SSH -v -x -n 2>/dev/null | awk 'NR > 2 && $3 == "DROP" { s += $1 } END { print s + 0 }')
        s=$((s + n))
    done
    echo "$s"
}

# Mẫu 3 s gói TCP mới (SYN) tới cổng node + dải FPORT, đếm theo cổng đích (tcpdump bắt ở card, trước nat/lọc)
# → mỗi dòng "số_gói cổng", top 5
guard_syn() {
    local dev="$1" f
    command -v tcpdump >/dev/null || return 0
    # chỉ SYN đi VÀO (bỏ SYN máy tự mở ra ngoài và SYN-ACK trả về — không thì cổng 443/cổng tạm lẫn vào)
    f="tcp[tcpflags] & (tcp-syn|tcp-ack) == tcp-syn"
    timeout 3 tcpdump -nn -Q in -i "$dev" -c 20000 "$f" 2>/dev/null \
        | awk '{ d = $5; sub(/:$/, "", d); n = split(d, a, "."); if (a[n] ~ /^[0-9]+$/) print a[n] }' | sort | uniq -c | sort -rn | head -5
}
fmt_syn() { awk 'NF == 2 { printf "%s%s (%s goi)", (NR > 1 ? ", " : ""), $2, $1 } END { if (NR) print "" }'; }
guard_ports() { guard_syn "$1" | fmt_syn; }

# Id node trên máy (NodeID trong config V2bX) → "21,22"
guard_nodes() { grep -oE '"NodeID" *: *[0-9]+' /etc/V2bX/config.json 2>/dev/null | grep -oE '[0-9]+$' | sort -un | paste -sd, -; }

guard_push() {   # guard_push <json> — gửi panel trong nền, thử lại; không bao giờ chặn vòng canh gác
    local host key
    host=$(grep -oE '"ApiHost" *: *"[^"]+"' /etc/V2bX/config.json 2>/dev/null | head -1 | sed -E 's/.*"(https?:\/\/)?([^"]+)"$/\2/')
    key=$(grep -oE '"ApiKey" *: *"[^"]+"' /etc/V2bX/config.json 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
    [ -n "$host" ] && [ -n "$key" ] || { glog "bao panel: thieu ApiHost/ApiKey trong /etc/V2bX/config.json"; return 0; }
    (
        r=""
        for i in 1 2 3 4 5; do
            r=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -X POST -H "X-Key: $key" -H "Content-Type: application/json" \
                --data-binary "$1" "https://${host%/}/hxguard/push.php?h=$(hostname | tr -cd 'A-Za-z0-9._-')" 2>/dev/null)
            [ "$r" = 200 ] && { glog "bao panel: ok"; exit 0; }
            # 400/403 = tin hỏng / sai khoá → thử lại cũng vậy
            case "$r" in 400|403) glog "bao panel: bi tu choi (HTTP $r)"; exit 0 ;; esac
            sleep $((i * 15))
        done
        glog "bao panel: KHONG gui duoc (HTTP ${r:-?})"
    ) </dev/null >/dev/null 2>&1 &
}

# guard_alert_lock <card> <vào Mbit/s> <ra Mbit/s> <vào gói/s> <ra gói/s> <gói lạ/s> <giây yên để mở> <1 = thử>
# Bắt SYN 3 s, ghi "cong bi dap" vào log, báo panel.
guard_alert_lock() {
    local syn ports
    syn=$(guard_syn "$1")
    [ -n "$syn" ] && glog "cong bi dap (SYN 3s): $(printf '%s\n' "$syn" | fmt_syn)"
    ports=$(printf '%s\n' "$syn" | awk 'NF == 2 { printf "%s[%s,%s]", (n++ ? "," : ""), $2, $1 }')
    guard_push "{\"ev\":\"lock\",\"test\":${8:-0},\"nodes\":[$(guard_nodes)],\"rx_m\":$2,\"tx_m\":$3,\"rx_p\":$4,\"tx_p\":$5,\"st_p\":$6,\"hold\":$7,\"secs\":3,\"ports\":[$ports]}"
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
    local since=0 manual=1 rest why
    [ -f "$GDIR/locked" ] && read -r since manual rest < "$GDIR/locked"
    case "$since" in ''|*[!0-9]*) since=$(date +%s) ;; esac
    for T in iptables ip6tables; do
        command -v $T >/dev/null || continue
        while $T -D INPUT -j $L 2>/dev/null; do :; done
        $T -F $L 2>/dev/null; $T -X $L 2>/dev/null
    done
    rm -f "$GDIR/locked"
    systemctl start V2bX 2>/dev/null
    glog "MO LAI: $1"
    # khoá tự động mới báo panel đã mở (khoá tay là anh tự làm)
    if [ "$manual" = 0 ]; then
        case "$1" in "mo tay") why="mo tay" ;; "tat canh gac") why="tat canh gac" ;; *) why="tu mo" ;; esac
        guard_push "{\"ev\":\"unlock\",\"nodes\":[$(guard_nodes)],\"for\":$(($(date +%s) - since)),\"why\":\"$why\"}"
    fi
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
    local dev rb rp tb tp rb2 rp2 tb2 tp2 drb drp dtb dtp rx_m tx_m rx_p tx_p flood bad=0 quiet=0 sc sc2 st_p
    local since manual hold reason msg
    mkdir -p "$GDIR"
    dev="${GUARD_IFACE:-$(guard_iface)}"
    [ -n "$dev" ] || { glog "khong tim thay card mang"; exit 1; }
    glog "bat canh gac: card $dev, vao-ra >= ${GUARD_EXCESS_MBPS} Mbit/s hoac >= ${GUARD_EXCESS_PPS} goi/s (kem byte vao >= ${GUARD_RATIO10}/10 x ra hoac goi vao < ${GUARD_SMALL_PKT} B) va vao >= ${GUARD_RATIO10}/10 x ra, goi la >= ${GUARD_STRANGE_PPS}/s, ${GUARD_SAMPLES}x${GUARD_STEP}s; mo lai khi yen ${GUARD_HOLD}s$([ "$GUARD_DRYRUN" = 1 ] && echo ' — CHAY THU, khong khoa that')"
    read -r rb rp tb tp < <(read_dev "$dev")
    sc=$(read_strange)
    while sleep "$GUARD_STEP"; do
        read -r rb2 rp2 tb2 tp2 < <(read_dev "$dev")
        sc2=$(read_strange)
        st_p=$(((sc2 - sc) / GUARD_STEP)); sc=$sc2
        [ $st_p -lt 0 ] && st_p=0   # chuỗi HX-DDOS vừa dựng lại (hx-ddos on) → bộ đếm về 0
        [ -n "${tp2:-}" ] && [ -n "${tp:-}" ] || { rb=${rb2:-} rp=${rp2:-} tb=${tb2:-} tp=${tp2:-}; continue; }
        drb=$((rb2 - rb)); drp=$((rp2 - rp)); dtb=$((tb2 - tb)); dtp=$((tp2 - tp))
        rb=$rb2 rp=$rp2 tb=$tb2 tp=$tp2
        [ $drb -lt 0 ] || [ $drp -lt 0 ] || [ $dtb -lt 0 ] || [ $dtp -lt 0 ] && continue   # bộ đếm quay vòng / card dựng lại
        rx_m=$((drb * 8 / 1000000 / GUARD_STEP)); tx_m=$((dtb * 8 / 1000000 / GUARD_STEP))
        rx_p=$((drp / GUARD_STEP)); tx_p=$((dtp / GUARD_STEP))
        echo "$(date +%s) $rx_m $tx_m $rx_p $tx_p $st_p" > "$GDIR/last"

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
        if [ $((rx_p - tx_p)) -ge "$GUARD_EXCESS_PPS" ] && [ $((drp * 10)) -ge $((GUARD_RATIO10 * dtp)) ]; then
            { [ $((drb * 10)) -ge $((GUARD_RATIO10 * dtb)) ] || [ $drb -lt $((drp * GUARD_SMALL_PKT)) ]; } && flood=1
        fi
        # khách tải nặng cũng làm vào ≫ ra (UDP/QUIC, đường về TQ nghẽn) nhưng toàn gói ESTABLISHED → không phải flood
        [ "$GUARD_STRANGE_PPS" -gt 0 ] && [ $st_p -lt "$GUARD_STRANGE_PPS" ] && flood=0
        [ $flood = 1 ] && bad=$((bad + 1)) || bad=0
        if [ $bad -ge "$GUARD_SAMPLES" ]; then
            msg="vao ${rx_m} Mbit/s ${rx_p} goi/s, ra ${tx_m} Mbit/s ${tx_p} goi/s, goi la ${st_p}/s (${bad} luot x ${GUARD_STEP}s)"
            bad=0; quiet=0
            if [ "$GUARD_DRYRUN" = 1 ]; then glog "CHAY THU — se khoa: $msg"; continue; fi
            hold=$(hold_for_new_lock)
            lock_apply "$msg; mo lai khi yen ${hold}s" 0 "$hold"
            guard_alert_lock "$dev" "$rx_m" "$tx_m" "$rx_p" "$tx_p" "$st_p" "$hold" 0 &
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
    local t rx tx rp tp st since manual hold reason
    systemctl is-active -q hx-guard.service 2>/dev/null && echo "canh gac: BAT" || echo "canh gac: tat"
    if [ -f "$GDIR/last" ]; then
        read -r t rx tx rp tp st < "$GDIR/last"
        echo "do luc $(date -d @"$t" '+%T'): vao $rx Mbit/s $rp goi/s · ra $tx Mbit/s $tp goi/s · goi la ${st:-?}/s"
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
    ports) guard_ports "${GUARD_IFACE:-$(guard_iface)}" ;;   # xem tay: cổng nào đang nhận nhiều SYN nhất (3 s)
    guard-test)   # thử kênh báo panel: bắt SYN 3 s + 1 tin khoá + 1 tin mở (đánh dấu THỬ), KHÔNG khoá máy
        rx=0 tx=0 rp=0 tp=0 st=0
        [ -f "$GDIR/last" ] && read -r _ rx tx rp tp st < "$GDIR/last"
        guard_alert_lock "${GUARD_IFACE:-$(guard_iface)}" "${rx:-0}" "${tx:-0}" "${rp:-0}" "${tp:-0}" "${st:-0}" "$GUARD_HOLD" 1
        wait
        guard_push "{\"ev\":\"unlock\",\"test\":1,\"nodes\":[$(guard_nodes)],\"for\":4,\"why\":\"tu mo\"}"
        wait
        tail -3 "$GLOG" ;;
    lock) lock_apply "khoa tay${2:+: $2}" 1 0 ;;
    unlock) unlock_apply "mo tay" ;;
    boot) install_boot ;;
    unboot) systemctl disable hx-ddos.service >/dev/null 2>&1; echo "hx-ddos: khong tu bat khi khoi dong" ;;
    off) off ;;
    *) status ;;
esac
