#!/bin/bash
# hypex-machine — agent báo tải máy (CPU / RAM / swap / đĩa / mạng) về trang "Máy chủ" của panel.
#
# Cài (lệnh panel sinh ở Máy chủ → Cài đặt):
#   curl -fsSL https://raw.githubusercontent.com/Tubetna/hypex-x/main/machine.sh \
#     | sudo bash -s -- --panel 'https://hypexcloud.com' --token 'XXXX' --machine-id 1
#
# Sau khi cài: dịch vụ systemd `hypex-machine`, cấu hình /etc/hypex-machine.conf,
# log `journalctl -u hypex-machine`. Gỡ: hypex-machine uninstall.
#
# Agent chỉ ĐỌC /proc và POST JSON tới /api/v2/server/machine/status theo push_interval panel
# trả về ở /api/v2/server/machine/nodes (mặc định 60 s). Không đụng V2bX — node vẫn cài bằng
# install.sh như cũ; đây chỉ là phần "đo sức khoẻ máy".
set -u

SELF_URL="${HX_MACHINE_URL:-https://raw.githubusercontent.com/Tubetna/hypex-x/main/machine.sh}"
BIN=/usr/local/sbin/hypex-machine
CONF=/etc/hypex-machine.conf
UNIT=/etc/systemd/system/hypex-machine.service

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; plain='\033[0m'
die() { echo -e "${red}Lỗi: $1${plain}" >&2; exit 1; }

# ── Đo ─────────────────────────────────────────────────────────────────
# CPU: tổng jiffies và idle (idle + iowait) từ /proc/stat
cpu_sample() { awk '/^cpu /{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print total, idle}' /proc/stat; }
# Mạng: tổng byte nhận/gửi mọi card trừ lo
net_sample() { awk 'NR>2 { sub(/^[ 	]+/,""); split($0,p,":"); if (p[1]=="lo") next; split(p[2],f," "); rx+=f[1]; tx+=f[9] } END{print rx+0, tx+0}' /proc/net/dev; }

collect() {
    local interval=$1
    local c1 c2 n1 n2 t1 t2
    c1=$(cpu_sample); n1=$(net_sample); t1=$(date +%s%N)
    sleep "$interval"
    c2=$(cpu_sample); n2=$(net_sample); t2=$(date +%s%N)

    local cpu
    cpu=$(awk -v a="$c1" -v b="$c2" 'BEGIN{split(a,x," "); split(b,y," "); dt=y[1]-x[1]; di=y[2]-x[2];
        if(dt<=0) print 0; else { v=(dt-di)*100/dt; if(v<0)v=0; if(v>100)v=100; printf "%.1f", v } }')
    local rx tx
    read -r rx tx < <(awk -v a="$n1" -v b="$n2" -v t1="$t1" -v t2="$t2" 'BEGIN{split(a,x," "); split(b,y," ");
        s=(t2-t1)/1e9; if(s<=0)s=1; drx=y[1]-x[1]; dtx=y[2]-x[2]; if(drx<0)drx=0; if(dtx<0)dtx=0; printf "%.0f %.0f", drx/s, dtx/s }')

    local mt ma st sf
    mt=$(awk '/^MemTotal/{print $2*1024}' /proc/meminfo)
    ma=$(awk '/^MemAvailable/{print $2*1024}' /proc/meminfo)
    [ -z "$ma" ] && ma=$(awk '/^MemFree/{print $2*1024}' /proc/meminfo)
    st=$(awk '/^SwapTotal/{print $2*1024}' /proc/meminfo)
    sf=$(awk '/^SwapFree/{print $2*1024}' /proc/meminfo)
    local dt du
    read -r dt du < <(df -B1 -P / 2>/dev/null | awk 'NR==2{print $2, $3}')

    printf '{"machine_id":%d,"token":"%s","cpu":%s,"mem":{"total":%d,"used":%d},"swap":{"total":%d,"used":%d},"disk":{"total":%d,"used":%d},"net":{"in_speed":%s,"out_speed":%s}}' \
        "$MACHINE_ID" "$TOKEN" "$cpu" "$mt" "$((mt-ma))" "${st:-0}" "$(( ${st:-0} - ${sf:-0} ))" "${dt:-0}" "${du:-0}" "$rx" "$tx"
}

# Hỏi panel: kiểm token + lấy push_interval
fetch_interval() {
    local body
    body=$(curl -fsS -m 15 -X POST -H 'Content-Type: application/json' \
        -d "{\"machine_id\":$MACHINE_ID,\"token\":\"$TOKEN\"}" "$PANEL/api/v2/server/machine/nodes" 2>/dev/null) || return 1
    echo "$body" | grep -oE '"push_interval":[0-9]+' | head -1 | cut -d: -f2
}

run_loop() {
    [ -r "$CONF" ] || die "Thiếu $CONF — chạy lại lệnh cài từ panel."
    # shellcheck disable=SC1090
    . "$CONF"
    local interval=${PUSH_INTERVAL:-60} n=0 code
    echo "hypex-machine: máy #$MACHINE_ID → $PANEL, mỗi ${interval}s"
    while :; do
        # Mỗi 30 lượt hỏi lại panel để theo push_interval mới
        if [ $((n % 30)) -eq 0 ]; then
            local iv; iv=$(fetch_interval) && [ -n "$iv" ] && [ "$iv" -ge 5 ] && interval=$iv
        fi
        n=$((n+1))
        local payload; payload=$(collect "$interval")
        code=$(curl -sS -m 15 -o /tmp/hypex-machine.last -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
            -d "$payload" "$PANEL/api/v2/server/machine/status" 2>/dev/null || echo 000)
        case "$code" in
            200) ;;
            403) echo "panel từ chối (403): máy bị tắt hoặc token sai — kiểm trang Máy chủ"; sleep 60 ;;
            *)   echo "gửi lỗi HTTP $code: $(head -c 200 /tmp/hypex-machine.last 2>/dev/null)" ;;
        esac
    done
}

# ── Cài / gỡ ────────────────────────────────────────────────────────────
install_agent() {
    [ "$(id -u)" = 0 ] || die "Cần chạy bằng root (sudo)."
    command -v curl >/dev/null || die "Thiếu curl."
    command -v systemctl >/dev/null || die "Chỉ hỗ trợ máy có systemd."
    [ -n "$PANEL" ] && [ -n "$TOKEN" ] && [ -n "$MACHINE_ID" ] || die "Thiếu --panel / --token / --machine-id."
    PANEL=${PANEL%/}

    echo -e "${yellow}Kiểm token với panel...${plain}"
    local iv; iv=$(fetch_interval) || die "Panel không nhận máy #$MACHINE_ID (token sai, máy bị tắt, hoặc không tới được $PANEL)."

    # Khi chạy qua `curl | bash` thì $0 là "bash" → tải lại chính script về BIN
    if [ -f "$0" ] && grep -q 'hypex-machine' "$0" 2>/dev/null; then
        cp -f "$0" "$BIN"
    else
        curl -fsSL -o "$BIN" "$SELF_URL" || die "Không tải được $SELF_URL"
    fi
    chmod 755 "$BIN"

    umask 077
    cat > "$CONF" << EOF
# hypex-machine — sinh bởi lệnh cài từ panel $(date '+%Y-%m-%d %H:%M')
PANEL='$PANEL'
TOKEN='$TOKEN'
MACHINE_ID=$MACHINE_ID
PUSH_INTERVAL=${iv:-60}
EOF
    umask 022
    cat > "$UNIT" << EOF
[Unit]
Description=hypex-machine: bao tai may ve panel (may #$MACHINE_ID)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN run
Restart=always
RestartSec=10
Nice=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now hypex-machine.service >/dev/null 2>&1 || die "Không bật được dịch vụ."
    sleep 3
    if systemctl is-active hypex-machine.service >/dev/null; then
        echo -e "${green}✓ Đã cài hypex-machine cho máy #$MACHINE_ID — báo về $PANEL mỗi ${iv:-60}s.${plain}"
        echo -e "  Log: journalctl -u hypex-machine -f · Gỡ: hypex-machine uninstall"
    else
        journalctl -u hypex-machine -n 20 --no-pager
        die "Dịch vụ không chạy — xem log trên."
    fi
}

uninstall_agent() {
    systemctl disable --now hypex-machine.service >/dev/null 2>&1
    rm -f "$UNIT" "$CONF" "$BIN"
    systemctl daemon-reload
    echo -e "${green}Đã gỡ hypex-machine.${plain}"
}

# ── Tham số ─────────────────────────────────────────────────────────────
PANEL=""; TOKEN=""; MACHINE_ID=""; ACTION="install"
while [ $# -gt 0 ]; do
    case "$1" in
        --mode) shift ;;                       # tương thích lệnh cũ "--mode machine"
        --panel) PANEL="$2"; shift 2 ;;
        --token) TOKEN="$2"; shift 2 ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        run) ACTION=run; shift ;;
        uninstall) ACTION=uninstall; shift ;;
        status) ACTION=status; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) shift ;;
    esac
done
case "$ACTION" in
    run) run_loop ;;
    uninstall) uninstall_agent ;;
    status) systemctl status hypex-machine.service --no-pager; [ -r "$CONF" ] && grep -v TOKEN "$CONF" ;;
    *) install_agent ;;
esac
