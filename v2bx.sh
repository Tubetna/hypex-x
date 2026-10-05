#!/usr/bin/env bash

# ==========================================
#   HYX · Quản lý node V2bX  (lệnh: hyx — tên cũ v2bx / hypex-x vẫn chạy)
#   Tác giả: Tubetna
# ==========================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
white='\033[1;37m'
bold='\033[1m'
dim='\033[2m'
plain='\033[0m'

# ── Bảng màu: xanh nước biển nhạt → tím nhạt ──
# Dãy màu đi rồi quay lại (A→B→A) nên hiệu ứng "chạy màu" vòng tròn liền mạch.
# Terminal 24-bit (COLORTERM=truecolor, hoặc tự đặt HYX_TRUECOLOR=1) → gradient mịn 16 nấc;
# còn lại 256 màu pastel; terminal 16 màu thì hạ về cyan/xanh/tím cơ bản.
ESC=$'\033'; R0="${ESC}[0m"; B1="${ESC}[1m"; D1="${ESC}[2m"
# Không tin `tput colors`: MobaXterm/PuTTY đặt TERM=xterm (báo 8 màu) nhưng vẽ được 256 màu.
# Chỉ hạ 16 màu với console thật (linux/vt100/dumb) hoặc khi đặt HYX_COLORS=16.
case "$TERM" in linux|vt100|vt102|vt220|dumb|ansi|cons25) NCOL=8 ;; *) NCOL=256 ;; esac
[[ "$HYX_COLORS" =~ ^[0-9]+$ ]] && NCOL=$HYX_COLORS
GC=(); GB=()   # mã màu chữ / nền dựng sẵn — vẽ từng ký tự khỏi gọi subshell
if [ -n "$HYX_TRUECOLOR" ] || [[ "$COLORTERM" =~ ^(truecolor|24bit)$ ]]; then
    # #78DCFF (xanh nước biển nhạt) → #C8A0FF (tím nhạt)
    for _i in 0 1 2 3 4 5 6 7 8 7 6 5 4 3 2 1; do
        _rgb="$(( 120 + 80 * _i / 8 ));$(( 220 - 60 * _i / 8 ));255"
        GC+=("${ESC}[38;2;${_rgb}m"); GB+=("${ESC}[48;2;${_rgb}m")
    done
    HLC="${ESC}[1;38;2;255;255;255m"
    FLC=("${ESC}[38;2;255;245;180m" "${ESC}[38;2;255;205;90m" "${ESC}[38;2;255;150;60m" "${ESC}[38;2;235;95;70m")
    SMC=("${ESC}[38;2;225;225;240m" "${ESC}[38;2;180;180;200m" "${ESC}[38;2;135;135;155m")
elif [ "$NCOL" -ge 256 ]; then
    # 123 #87FFFF · 117 #87D7FF · 111 #87AFFF · 147 #AFAFFF · 141 #AF87FF · 183 #D7AFFF
    for _c in 123 117 111 147 141 183 141 147 111 117; do
        GC+=("${ESC}[38;5;${_c}m"); GB+=("${ESC}[48;5;${_c}m")
    done
    HLC="${ESC}[1;38;5;231m"
    FLC=("${ESC}[38;5;229m" "${ESC}[38;5;221m" "${ESC}[38;5;209m" "${ESC}[38;5;203m")
    SMC=("${ESC}[38;5;254m" "${ESC}[38;5;248m" "${ESC}[38;5;242m")
else
    for _c in 6 6 4 4 5 5 5 4 4 6; do GC+=("${ESC}[38;5;${_c}m"); GB+=("${ESC}[48;5;${_c}m"); done
    HLC="${ESC}[1;37m"
    FLC=("${ESC}[1;33m" "${ESC}[33m" "${ESC}[1;31m" "${ESC}[31m")
    SMC=("${ESC}[37m" "${ESC}[37m" "${ESC}[2;37m")
fi
NG=${#GC[@]}
g()  { printf '%s' "${GC[$(( $1 % NG ))]}"; }   # g <i> → mã màu thứ i
# Tô một chuỗi theo gradient, mỗi ký tự một màu (offset $2 để làm hiệu ứng chạy)
gtext() {
    local str="$1" off="${2:-0}" i out=""
    for (( i=0; i<${#str}; i++ )); do out+="${GC[$(( (i + off) % NG ))]}${str:i:1}"; done
    printf '%s%s' "$out" "$R0"
}
# Hiệu ứng: chỉ khi có tty và không đặt HYX_NOANIM (SSH script/cron thì tắt)
anim_ok() { [ -t 1 ] && [ -z "$HYX_NOANIM" ]; }
# Ngủ ngắn giữa các khung hình; bấm phím bất kỳ → SKIP=1 (bỏ qua phần còn lại của hiệu ứng)
SKIP=0
nap() {
    if [ "$SKIP" = 1 ]; then return 0; fi
    if [ -t 0 ]; then read -rs -n1 -t "$1" _k && SKIP=1; else sleep "$1"; fi
    return 0
}
cur_off() { anim_ok && printf '%s' "${ESC}[?25l"; }
cur_on()  { [ -t 1 ] && printf '%s' "${ESC}[?25h"; return 0; }
trap 'cur_on' EXIT
trap 'cur_on; printf "%s\n" "$R0"; exit 130' INT TERM
# Spinner: spin "việc đang làm" lệnh... — chạy lệnh nền; vòng quay + thanh chạy qua lại + số giây
SPIN_OUT=/tmp/.hyx_spin.log
spin() {
    local msg="$1"; shift
    if ! anim_ok; then "$@" >"$SPIN_OUT" 2>&1; return $?; fi
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 rc t0=$SECONDS p k tr
    "$@" >"$SPIN_OUT" 2>&1 & local pid=$!
    cur_off
    while kill -0 $pid 2>/dev/null; do
        p=$(( i % 20 )); [ $p -ge 10 ] && p=$(( 19 - p ))
        tr=""
        for (( k=0; k<12; k++ )); do
            if [ $k -ge $p ] && [ $k -le $(( p + 2 )) ]; then tr+="${GC[$(( (k + i) % NG ))]}━"
            else tr+="${D1}${GC[$(( k % NG ))]}─${R0}"; fi
        done
        printf '\r  %s%s%s %s  %s%s  %s%ds%s\033[K' "${GC[$(( i % NG ))]}" "${frames:$(( i % 10 )):1}" "$R0" \
            "$msg" "$tr" "$R0" "$D1" $(( SECONDS - t0 )) "$R0"
        i=$((i+1)); sleep 0.07
    done
    wait $pid; rc=$?
    printf '\r\033[K'; cur_on
    return $rc
}
# Đọc log có spinner: rlog "<lệnh shell>" — journal node vài trăm MB, mỗi lệnh 2–10 s
rlog() { spin "Đọc log..." bash -c "$1"; [ -s "$SPIN_OUT" ] && cat "$SPIN_OUT" || echo -e "  ${dim}(không có dòng nào)${plain}"; }

# ${#str} phải đếm ký tự chứ không phải byte thì cột chữ có dấu mới thẳng
if [ -z "$LC_ALL" ] && locale -a 2>/dev/null | grep -qi 'C.utf8\|C.UTF-8'; then export LC_ALL=C.UTF-8; fi

SERVICE="V2bX"
BIN_DIR="/usr/bin/V2bX-bin"
BINARY="${BIN_DIR}/V2bX"
CONF_DIR="/etc/V2bX"
CONFIG="${CONF_DIR}/config.json"
BASE_URL="${V2BX_BASE_URL:-https://github.com/Tubetna/hypex-x/releases/latest/download}"
SCRIPT_URL="${V2BX_SCRIPT_URL:-https://raw.githubusercontent.com/Tubetna/hypex-x/main}"
INSTALL_SCRIPT="${SCRIPT_URL}/install.sh"

# ── Kiểm tra quyền root ──────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}Lỗi: Cần chạy bằng quyền root!${plain}"
    exit 1
fi

# ── Hệ thống init ────────────────────────
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    INIT_SYSTEM="systemd"
elif command -v rc-update &>/dev/null; then
    INIT_SYSTEM="openrc"
else
    INIT_SYSTEM="none"
fi

svc() {
    # svc <start|stop|restart|status|enable|disable>
    case "${INIT_SYSTEM}" in
        systemd)
            case "$1" in
                enable)  systemctl enable  $SERVICE ;;
                disable) systemctl disable $SERVICE ;;
                *)       systemctl "$1" $SERVICE ;;
            esac ;;
        openrc)
            case "$1" in
                enable)  rc-update add $SERVICE default ;;
                disable) rc-update del $SERVICE default ;;
                *)       rc-service $SERVICE "$1" ;;
            esac ;;
        *) echo -e "${red}Máy không có systemd lẫn OpenRC.${plain}"; return 1 ;;
    esac
}

svc_active() {
    case "${INIT_SYSTEM}" in
        systemd) systemctl is-active --quiet $SERVICE 2>/dev/null ;;
        openrc)  rc-service $SERVICE status >/dev/null 2>&1 ;;
        *)       return 1 ;;
    esac
}

# ── Phát hiện kiến trúc (phải khớp với install.sh) ──
detect_endian() {
    local probe d
    for probe in /bin/sh /bin/busybox /proc/self/exe; do
        [ -r "$probe" ] || continue
        d=$(od -An -tu1 -j5 -N1 "$probe" 2>/dev/null | tr -d ' ')
        [ "$d" = "1" ] && { echo "le"; return; }
        [ "$d" = "2" ] && { echo "be"; return; }
    done
    echo "le"
}

detect_arch() {
    local m bits
    m=$(uname -m)
    bits=$(getconf LONG_BIT 2>/dev/null || echo 64)
    case "$m" in
        x86_64|amd64)
            [ "$bits" = "32" ] && ARCH_SUFFIX="linux-386" || ARCH_SUFFIX="linux-amd64" ;;
        i386|i486|i586|i686|x86|x86pc)  ARCH_SUFFIX="linux-386" ;;
        aarch64|arm64|armv8*|armv9*)
            [ "$bits" = "32" ] && ARCH_SUFFIX="linux-arm32-v7" || ARCH_SUFFIX="linux-arm64" ;;
        armv7*|armhf)        ARCH_SUFFIX="linux-arm32-v7" ;;
        armv6*)              ARCH_SUFFIX="linux-arm32-v6" ;;
        armv5*|armv4*|arm)   ARCH_SUFFIX="linux-arm32-v5" ;;
        mips64el|mips64le)   ARCH_SUFFIX="linux-mips64le" ;;
        mips64)  [ "$(detect_endian)" = "le" ] && ARCH_SUFFIX="linux-mips64le" || ARCH_SUFFIX="linux-mips64" ;;
        mipsel|mipsle)       ARCH_SUFFIX="linux-mips32le" ;;
        mips)    [ "$(detect_endian)" = "le" ] && ARCH_SUFFIX="linux-mips32le" || ARCH_SUFFIX="linux-mips32" ;;
        ppc64le|powerpc64le) ARCH_SUFFIX="linux-ppc64le" ;;
        ppc64|powerpc64) [ "$(detect_endian)" = "le" ] && ARCH_SUFFIX="linux-ppc64le" || ARCH_SUFFIX="linux-ppc64" ;;
        s390x)               ARCH_SUFFIX="linux-s390x" ;;
        *)                   ARCH_SUFFIX="" ;;
    esac
}

# ── Lấy trạng thái dịch vụ ──────────────
get_status() {
    if svc_active; then
        echo -e "${green}● Đang chạy${plain}"
    elif [ -f "$BINARY" ]; then
        echo -e "${red}● Đã dừng${plain}"
    else
        echo -e "${yellow}● Chưa cài${plain}"
    fi
}

# ── Lấy phiên bản ───────────────────────
get_version() {
    if [ -f "$BINARY" ]; then
        $BINARY version 2>/dev/null | tail -1 || echo "Không xác định"
    else
        echo "Chưa cài đặt"
    fi
}

# ── Đọc nhanh cấu hình / cert / MSS cho header và trạng thái ──
get_autostart() {
    case "${INIT_SYSTEM}" in
        systemd) systemctl is-enabled $SERVICE &>/dev/null ;;
        openrc)  rc-update show default 2>/dev/null | grep -q "$SERVICE" ;;
        *) false ;;
    esac && echo -e "${green}tự chạy ✓${plain}" || echo -e "${yellow}tự chạy ✗${plain} ${dim}(9)${plain}"
}
get_nodes() {
    # "#25 VLESS  #26 VLESS" — đọc thẳng config.json, không cần jq
    [ -f "$CONFIG" ] || { echo "chưa có config"; return; }
    paste -d' ' <(grep -oE '"NodeID"\s*:\s*[0-9]+' "$CONFIG" | grep -oE '[0-9]+' | sed 's/^/#/') \
                <(grep -oE '"NodeType"\s*:\s*"[^"]+"' "$CONFIG" | cut -d'"' -f4) | tr '\n' ' '
}
get_cert_info() {
    local crt="${CONF_DIR}/cert.crt" cn exp
    [ -s "$crt" ] || { echo "không"; return; }
    cn=$(openssl x509 -in "$crt" -noout -subject 2>/dev/null | sed -n 's/.*CN *= *\([^,]*\).*/\1/p')
    exp=$(openssl x509 -in "$crt" -noout -enddate 2>/dev/null | cut -d= -f2 | awk '{print $2" "$1" "$4}')
    if openssl x509 -in "$crt" -noout -issuer 2>/dev/null | grep -qi "let's encrypt"; then
        openssl x509 -in "$crt" -noout -checkend 604800 &>/dev/null \
            && echo -e "${cn} ${dim}· hết hạn ${exp}${plain}" \
            || echo -e "${red}${cn} · SẮP HẾT HẠN ${exp}${plain}"
    else
        echo -e "${yellow}tự ký (${cn})${plain}"
    fi
}
get_mss_status() {
    if iptables -t mangle -S INPUT 2>/dev/null | grep -q TCPMSS; then
        echo -e "${green}✓ ép 1400${plain}"
    else
        echo -e "${yellow}✗ chưa ép${plain} ${dim}(menu 20)${plain}"
    fi
}

get_mem_status() {
    local tot lim sw
    tot=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
    sw=$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
    lim=$(grep -oE 'GOMEMLIMIT=[0-9]+MiB' /etc/systemd/system/V2bX.service.d/memory.conf 2>/dev/null | cut -d= -f2)
    if [ -n "$lim" ]; then
        echo -e "${green}✓ trần ${lim}${plain} ${dim}· RAM ${tot} MB · swap ${sw} MB${plain}"
    else
        echo -e "${yellow}✗ chưa đặt trần${plain} ${dim}· RAM ${tot} MB · swap ${sw} MB (menu 21)${plain}"
    fi
}

get_relay_status() {
    local f=/etc/V2bX/custom_outbound.json a
    if [ -f "$f" ] && grep -q '"relay-vn"' "$f" 2>/dev/null; then
        a=$(python3 -c 'import json;o=json.load(open("'"$f"'"));x=[e for e in o if e.get("tag")=="relay-vn"][0]["settings"]["vnext"][0];print("%s:%s"%(x["address"],x["port"]))' 2>/dev/null)
        echo -e "${green}✓ → ${a:-?}${plain} ${dim}· $(grep -c '"hx-relay"' /etc/V2bX/route.json 2>/dev/null || echo 0) luật (menu 24)${plain}"
    else
        echo -e "${dim}chưa đặt (menu 24)${plain}"
    fi
}

get_reaper_status() {
    if systemctl is-enabled v2bx-conn-reaper.timer &>/dev/null; then
        local last
        last=$(journalctl -t v2bx-reaper -n 1 -o cat --no-pager 2>/dev/null)
        echo -e "${green}✓ timer 5 phút${plain} ${dim}· ${last:-chưa ngắt gì}${plain}"
    else
        echo -e "${yellow}✗ chưa bật${plain} ${dim}(menu 23 — node Reality trực tiếp nên bật)${plain}"
    fi
}

# ══════════════════════════════════════════
#   Giao diện: banner gradient · thẻ trạng thái · menu theo nhóm
# ══════════════════════════════════════════
shopt -s extglob
TERM_W=$(tput cols 2>/dev/null || echo 80); [[ "$TERM_W" =~ ^[0-9]+$ ]] || TERM_W=80
# W = bề ngang trong hộp (không tính 2 viền). Màn ≥ 70 cột: 3 cột mục, hẹp hơn: 2 cột.
if [ "$TERM_W" -ge 70 ]; then UI_COLS=3; W=62; else UI_COLS=2; W=$(( TERM_W - 6 )); [ "$W" -lt 44 ] && W=44; fi

# Độ dài HIỂN THỊ (bỏ mã màu thật lẫn dạng chữ \033[..m) → VL
vlen() {
    local s="${1//${ESC}\[*([0-9;])m/}"
    s="${s//\\033\[*([0-9;])m/}"
    VL=${#s}
}

# Đường ngang gradient: hline <góc trái> <góc phải> [tiêu đề]
hline() {
    local L="$1" R="$2" t="${3:+ $3 }" out i start=0
    out="${GC[0]}${L}"
    if [ -n "$t" ]; then out+="─${B1}${ESC}[38;5;255m${t}${R0}"; start=$(( 1 + ${#t} )); fi
    for (( i=start; i<W; i++ )); do out+="${GC[$(( i * NG / W ))]}─"; done
    out+="${GC[$((NG-1))]}${R}${R0}"
    printf '  %s\n' "$out"
    [ "$UI_REVEAL" = 1 ] && sleep 0.012
}

# Một dòng trong hộp; viền trái/phải đổi màu theo dòng → gradient dọc
BROW=0
brow() {
    local s="$1" pad
    vlen "$s"; pad=$(( W - 2 - VL )); [ "$pad" -lt 0 ] && pad=0
    printf '  %s│%s %b%*s %s│%s\n' "${GC[$(( BROW % NG ))]}" "$R0" "$s" "$pad" '' "${GC[$(( (BROW + 4) % NG ))]}" "$R0"
    BROW=$(( BROW + 1 ))
    [ "$UI_REVEAL" = 1 ] && sleep 0.012
}

# Banner chữ khối (ANSI Shadow) — 55 cột
BANNER=(
"██╗  ██╗██╗   ██╗██████╗ ███████╗██╗  ██╗      ██╗  ██╗"
"██║  ██║╚██╗ ██╔╝██╔══██╗██╔════╝╚██╗██╔╝      ╚██╗██╔╝"
"███████║ ╚████╔╝ ██████╔╝█████╗   ╚███╔╝ █████╗ ╚███╔╝ "
"██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══╝   ██╔██╗ ╚════╝ ██╔██╗ "
"██║  ██║   ██║   ██║     ███████╗██╔╝ ██╗      ██╔╝ ██╗"
"╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚══════╝╚═╝  ╚═╝      ╚═╝  ╚═╝"
)
BANNER_W=55
# banner_line <dòng> <lệch màu> <vị trí vệt sáng> <số dòng>
# Vệt sáng chạy chéo: ký tự có (cột + dòng - hl) trong [-1, 1] tô trắng sáng.
banner_line() {
    local s="$1" off="$2" hl="${3:--99}" row="${4:-0}" i ch c d out="" n=${#1}
    for (( i=0; i<n; i++ )); do
        ch="${s:i:1}"
        if [ "$ch" = " " ]; then out+=" "; continue; fi
        c="${GC[$(( (i * NG / n + off) % NG ))]}"
        d=$(( i + row * 2 - hl ))
        if [ "$d" -ge -1 ] && [ "$d" -le 1 ]; then out+="${HLC}${ch}${R0}"
        elif [ "$ch" = "█" ]; then out+="${c}${ch}"
        else out+="${D1}${c}${ch}${R0}"   # bóng đổ ╚═╝ tối hơn
        fi
    done
    printf '%*s%s%s\n' "$(( 2 + (W + 2 - BANNER_W) / 2 ))" '' "$out" "$R0"
}
draw_banner() {
    if [ "$TERM_W" -lt $(( BANNER_W + 4 )) ]; then   # màn quá hẹp: chữ gradient thường
        printf '  %s%s%s\n' "$B1" "$(gtext 'HYPEX-X')" "$R0"; return
    fi
    local r k hl nb=${#BANNER[@]}
    if [ "$UI_REVEAL" = 1 ] && [ "$SKIP" != 1 ]; then
        # hiện từng dòng, mỗi dòng màu lệch dần → như sóng đổ xuống
        for (( k=0; k<nb; k++ )); do banner_line "${BANNER[k]}" $(( nb - k )) -99 "$k"; nap 0.035; done
        # vệt sáng quét chéo từ trái sang phải, màu trôi theo
        for (( hl=-12; hl<=BANNER_W + 12; hl+=3 )); do
            [ "$SKIP" = 1 ] && break
            printf '\033[%dA' "$nb"
            for (( k=0; k<nb; k++ )); do banner_line "${BANNER[k]}" $(( (hl + 12) / 6 )) "$hl" "$k"; done
            nap 0.018
        done
        printf '\033[%dA' "$nb"
    fi
    for (( k=0; k<nb; k++ )); do banner_line "${BANNER[k]}" 0 -99 "$k"; done
}

# ── Cảnh tên lửa phóng (chỉ lần mở đầu, bấm phím bất kỳ để bỏ qua; HYX_NOROCKET=1 để tắt) ──
# Chỉ dùng ký tự có trong font phổ biến (Consolas, DejaVu, MobaXterm): ▲ ● █ ▄ ▀ ▌ ▐ ░ ▒ ▓ · ∙ +
ROCKET=(
"    ▲    "
"   ▄█▄   "
"  ▐███▌  "
"  ▐█●█▌  "
"  ▐███▌  "
"  ▐███▌  "
" ▄▐███▌▄ "
"▐█▐███▌█▌"
"▀▀ ▀▀▀ ▀▀"
)
FLAME=(   # 4 khung, mỗi khung 3 dòng cách nhau bằng |
"   ▓█▓   |    ▒    |    ░    "
"   ▒█▒   |   ░▓░   |    ▒    "
"   ▓█▓   |   ▒█▒   |   ░▒░   "
"   ░▓░   |    ▓    |   ░ ░   "
)
RK=(); FL=()
paint_rocket() {   # dựng sẵn chuỗi đã tô màu cho thân + lửa
    local r i ch c s out f k
    RK=()
    for (( r=0; r<${#ROCKET[@]}; r++ )); do
        s="${ROCKET[r]}"; out=""
        for (( i=0; i<${#s}; i++ )); do
            ch="${s:i:1}"
            case "$ch" in
                ' ') out+="${R0} " ;;
                '●') out+="${HLC}●${R0}" ;;
                '▲') out+="${GC[$(( NG / 2 ))]}▲" ;;
                '▀') out+="${D1}${GC[$(( (r + i) % NG ))]}▀${R0}" ;;
                *)   c=$(( (r * NG / 2 / 8 + (i > 4 ? i - 4 : 4 - i)) % NG )); out+="${GC[$c]}${ch}" ;;
            esac
        done
        RK+=("${out}${R0}")
    done
    FL=()
    for f in "${FLAME[@]}"; do
        for k in 0 1 2; do
            s=$(cut -d'|' -f$(( k + 1 )) <<<"$f"); out=""
            for (( i=0; i<${#s}; i++ )); do
                ch="${s:i:1}"
                case "$ch" in
                    '█') out+="${FLC[0]}█" ;; '▓') out+="${FLC[1]}▓" ;;
                    '▒') out+="${FLC[2]}▒" ;; '░') out+="${FLC[3]}░" ;; *) out+="${R0} " ;;
                esac
            done
            FL+=("${out}${R0}")
        done
    done
}
# smoke_str <bán kính> <độ tan 0..2> → khói xám ở mặt đất (chiều rộng 2*bk+1)
smoke_str() {
    local s=$1 fade=$2 k d out="" ch
    for (( k=-s; k<=s; k++ )); do
        d=$(( k < 0 ? -k : k ))
        if   [ $(( d * 3 )) -le "$s" ] && [ "$fade" -eq 0 ]; then ch="▓"
        elif [ $(( d * 3 )) -le $(( s * 2 )) ] && [ "$fade" -le 1 ]; then ch="▒"
        else ch="░"; fi
        [ "$fade" -ge 2 ] && [ $(( (k + s) % 2 )) -eq 1 ] && ch=" "
        out+="${SMC[$(( d * 3 / (s + 1) ))]}${ch}"
    done
    SMOKE="${out}${R0}"
}
rocket_launch() {
    anim_ok || return 0
    [ -n "$HYX_NOROCKET" ] && return 0
    local LN; LN=$(tput lines 2>/dev/null || echo 24); [[ "$LN" =~ ^[0-9]+$ ]] || LN=24
    [ "$LN" -ge 22 ] && [ "$TERM_W" -ge 44 ] || return 0
    local H=18 SW=$(( W + 2 )) RC=$(( (W + 2 - 9) / 2 )) blank j r rr k fr top shake
    local sx=() sy=() sc=() row=() stars='··∙∙·+·∙*·' frame txt tc sm=0 smf=0 v=0 ns=26
    paint_rocket
    printf -v blank '%*s' "$SW" ''
    for (( j=0; j<ns; j++ )); do
        sx+=($(( RANDOM % SW ))); sy+=($(( RANDOM % H ))); sc+=("${stars:$(( RANDOM % ${#stars} )):1}")
    done
    SKIP=0; cur_off
    printf '\033[H'
    # khung hình: k < 12 = đếm ngược + đánh lửa (rung), sau đó cất cánh có gia tốc
    for (( k=0; ; k++ )); do
        [ "$SKIP" = 1 ] && break
        if [ $k -lt 12 ]; then
            top=$(( H - 13 )); shake=$(( k % 2 )); sm=$(( 2 + k / 2 )); smf=0
            txt=$(( 3 - k / 4 ))
        else
            v=$(( k - 12 )); top=$(( H - 13 - v * v / 6 - v )); shake=0
            sm=$(( 8 + v / 2 )); [ $sm -gt $(( SW / 2 - 2 )) ] && sm=$(( SW / 2 - 2 ))
            smf=$(( v / 5 )); [ $smf -gt 2 ] && smf=2
            [ $v -lt 4 ] && txt="CẤT CÁNH!" || txt=""
            [ $top -lt -14 ] && break
        fi
        # sao rơi xuống (nhanh dần khi tên lửa lên)
        for (( r=0; r<H; r++ )); do row[r]="$blank"; done
        for (( j=0; j<ns; j++ )); do
            if [ $k -ge 12 ]; then
                sy[j]=$(( sy[j] + 1 + v / 4 ))
                if [ "${sy[j]}" -ge "$H" ]; then sy[j]=$(( sy[j] % H )); sx[j]=$(( RANDOM % SW )); fi
            fi
            r=${sy[j]}; row[r]="${row[r]:0:${sx[j]}}${sc[j]}${row[r]:$(( sx[j] + 1 ))}"
        done
        fr=$(( (k + RANDOM % 2) % 4 ))
        smoke_str "$sm" "$smf"
        frame="${ESC}[H"
        for (( r=0; r<H; r++ )); do
            tc="${D1}${GC[$(( (r + k) % NG ))]}"
            rr=$(( r - top ))
            if [ $rr -ge 0 ] && [ $rr -lt 9 ]; then
                frame+="  ${tc}${row[r]:0:$(( RC + shake ))}${R0}${RK[rr]}${tc}${row[r]:$(( RC + shake + 9 ))}${R0}"
            elif [ $rr -ge 9 ] && [ $rr -lt 12 ]; then
                frame+="  ${tc}${row[r]:0:$(( RC + shake ))}${R0}${FL[$(( fr * 3 + rr - 9 ))]}${tc}${row[r]:$(( RC + shake + 9 ))}${R0}"
            elif [ $rr -ge 12 ] && [ $rr -lt 16 ] && [ $k -ge 12 ]; then   # vệt khói sau đuôi
                frame+="  ${tc}${row[r]:0:$(( RC + 4 ))}${R0}${SMC[$(( (rr - 12) / 2 + 1 ))]}$([ $rr -lt 14 ] && echo '░' || echo '·')${tc}${row[r]:$(( RC + 5 ))}${R0}"
            elif [ $r -eq $(( H - 1 )) ]; then
                frame+="  ${tc}${row[r]:0:$(( RC + 4 - sm ))}${R0}${SMOKE}${tc}${row[r]:$(( RC + 5 + sm ))}${R0}"
            elif [ $r -eq 2 ] && [ -n "$txt" ]; then
                frame+="  ${tc}${row[r]:0:$(( (SW - ${#txt}) / 2 ))}${R0}${B1}$(gtext "$txt" "$k")${tc}${row[r]:$(( (SW + ${#txt}) / 2 ))}${R0}"
            else
                frame+="  ${tc}${row[r]}${R0}"
            fi
            frame+="${ESC}[K"$'\n'
        done
        printf '%s' "$frame"
        if [ $k -lt 12 ]; then nap 0.07; else nap 0.04; fi
    done
    # xoá từng dòng (không dùng ESC[J từ đầu màn: MobaXterm/PuTTY đẩy cả cảnh vào lịch sử cuộn)
    frame="${ESC}[H"; for (( r=0; r<=H; r++ )); do frame+="${ESC}[2K"$'\n'; done
    printf '%s\033[H' "$frame"
    SKIP=0
}

# ── Thanh nạp trạng thái: chạy thật từng bước lấy dữ liệu, đầu thanh là tên lửa ──
load_bar() {   # load_bar <đã xong> <tổng> <nhãn>
    # bề ngang thanh co theo màn: cả dòng phải vừa 1 hàng, không thì \r chỉ xoá được nửa sau
    local d=$1 n=$2 bw=$(( TERM_W - 41 )) f i out="" pct
    [ "$bw" -gt 30 ] && bw=30; [ "$bw" -lt 10 ] && bw=10
    f=$(( d * bw / n )); pct=$(( d * 100 / n ))
    for (( i=0; i<bw; i++ )); do
        if   [ $i -lt $(( f - 3 )) ] || [ "$d" -ge "$n" ]; then out+="${GC[$(( i * NG / bw ))]}█"
        elif [ $i -lt "$f" ]; then out+="${FLC[$(( 3 - (f - i) ))]}$( [ $(( f - i )) -eq 1 ] && echo '▓' || echo '▒')"
        elif [ $i -eq "$f" ] && [ "$d" -lt "$n" ]; then out+="${HLC}►"
        else out+="${D1}${GC[$(( i * NG / bw ))]}·${R0}"; fi
    done
    printf '\r  %s%s%s %s│%s%s%s│%s %s%3d%%%s  %s%s%s\033[K' "${GC[$(( d % NG ))]}" "${SPF:$(( d % 10 )):1}" "$R0" \
        "$D1" "$R0" "$out" "$D1" "$R0" "$B1" "$pct" "$R0" "$D1" "$3" "$R0"
}
SPF='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
load_status() {
    local names=("dịch vụ" "phiên bản" "tự chạy" "node" "tài nguyên" "chứng chỉ" "lớp bảo vệ" "chuyển tiếp VN") n=8 k slow=0
    [ "$UI_REVEAL" = 1 ] && slow=1
    for (( k=0; k<n; k++ )); do
        anim_ok && load_bar "$k" "$n" "Đang nạp ${names[k]}…"
        case $k in
            0) S_STATUS=$(get_status) ;;
            1) S_VER=$(get_version | sed 's/ (.*//') ;;
            2) S_AUTO=$(card_auto) ;;
            3) S_NODES=$(get_nodes) ;;
            4) S_RUN=$(card_runtime) ;;
            5) S_CERT=$(get_cert_info) ;;
            6) S_GUARD=$(card_guard) ;;
            7) S_RELAY=$(card_relay) ;;
        esac
        [ "$slow" = 1 ] && nap 0.06
    done
    if anim_ok; then
        load_bar "$n" "$n" "Sẵn sàng"; [ "$slow" = 1 ] && nap 0.3
        printf '\r\033[K'
    fi
}

# ── Trạng thái gọn cho thẻ (không kèm chú thích menu) ──
ok_mark()  { printf '%b✓%b' "$green" "$plain"; }
no_mark()  { printf '%b✗%b' "$yellow" "$plain"; }
fmt_dur() {
    local s=$1
    if   [ "$s" -ge 86400 ]; then printf '%dd %dh' $((s/86400)) $((s%86400/3600))
    elif [ "$s" -ge 3600 ];  then printf '%dh %dm' $((s/3600)) $((s%3600/60))
    else printf '%dm' $((s/60)); fi
}
card_auto() {
    case "${INIT_SYSTEM}" in
        systemd) systemctl is-enabled $SERVICE &>/dev/null ;;
        openrc)  rc-update show default 2>/dev/null | grep -q "$SERVICE" ;;
        *) false ;;
    esac && printf '%s tự chạy' "$(ok_mark)" || printf '%s tự chạy %b(9)%b' "$(no_mark)" "$dim" "$plain"
}
card_runtime() {
    local et rss est ld
    et=$(ps -o etimes= -C V2bX 2>/dev/null | head -1 | tr -d ' ')
    rss=$(ps -o rss= -C V2bX 2>/dev/null | head -1 | tr -d ' ')
    est=$(ss -Htn state established 2>/dev/null | wc -l)
    ld=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
    if [ -n "$et" ]; then
        printf '%bChạy%b %s   %bRAM%b %s MB   %bKết nối%b %s   %bTải%b %s' \
            "$dim" "$plain" "$(fmt_dur "$et")" "$dim" "$plain" "$(( ${rss:-0} / 1024 ))" "$dim" "$plain" "$est" "$dim" "$plain" "$ld"
    else
        printf '%bV2bX không chạy%b   %bTải%b %s' "$red" "$plain" "$dim" "$plain" "$ld"
    fi
}
card_guard() {
    local lim
    lim=$(grep -oE 'GOMEMLIMIT=[0-9]+MiB' /etc/systemd/system/V2bX.service.d/memory.conf 2>/dev/null | cut -d= -f2)
    iptables -t mangle -S INPUT 2>/dev/null | grep -q TCPMSS && printf '%s MSS 1400' "$(ok_mark)" || printf '%s MSS' "$(no_mark)"
    printf '   '
    [ -n "$lim" ] && printf '%s OOM %s' "$(ok_mark)" "$lim" || printf '%s OOM' "$(no_mark)"
    printf '   '
    systemctl is-enabled v2bx-conn-reaper.timer &>/dev/null && printf '%s Dọn KN' "$(ok_mark)" || printf '%s Dọn KN' "$(no_mark)"
    printf '   '
    iptables -S HX-DDOS &>/dev/null && printf '%s Chống DDoS' "$(ok_mark)" || printf '%b· DDoS tắt%b' "$dim" "$plain"
}
card_relay() {
    local f=/etc/V2bX/custom_outbound.json a
    if [ -f "$f" ] && grep -q '"relay-vn"' "$f" 2>/dev/null; then
        a=$(python3 -c 'import json;o=json.load(open("'"$f"'"));x=[e for e in o if e.get("tag")=="relay-vn"][0]["settings"]["vnext"][0];print("%s:%s"%(x["address"],x["port"]))' 2>/dev/null)
        printf '%s → %s %b· %s luật%b' "$(ok_mark)" "${a:-?}" "$dim" "$(grep -c '"hx-relay"' /etc/V2bX/route.json 2>/dev/null || echo 0)" "$plain"
    else
        printf '%bkhông dùng%b' "$dim" "$plain"
    fi
}

# ── Header: banner + thẻ trạng thái ──
UI_FIRST=1
show_header() {
    clear
    detect_arch
    UI_REVEAL=0; [ "$UI_FIRST" = 1 ] && anim_ok && UI_REVEAL=1
    cur_off
    [ "$UI_REVEAL" = 1 ] && rocket_launch
    echo ""
    draw_banner
    local sub="Quản lý node V2bX  ·  lệnh hyx" i
    printf '%*s' "$(( 2 + (W + 2 - ${#sub}) / 2 ))" ''
    if [ "$UI_REVEAL" = 1 ] && [ "$SKIP" != 1 ]; then   # chữ phụ gõ dần, màu chạy theo
        for (( i=0; i<${#sub}; i++ )); do printf '%s%s' "${GC[$(( i * NG / ${#sub} ))]}" "${sub:i:1}"; nap 0.01; done
        printf '%s\n' "$R0"
    else
        printf '%s%s%s\n' "$D1" "$(gtext "$sub")" "$R0"
    fi
    echo ""
    load_status
    BROW=0
    hline '╭' '╮' 'TRẠNG THÁI'
    local nodes="$S_NODES"; [ ${#nodes} -gt $(( W - 12 )) ] && nodes="${nodes:0:$(( W - 15 ))}…"
    brow "${S_STATUS}   ${B1}${S_VER}${R0} ${dim}· ${ARCH_SUFFIX:-?}${plain}   ${S_AUTO}"
    brow "${dim}Node${plain}  ${yellow}${nodes}${plain}"
    brow "$S_RUN"
    brow "${dim}Cert${plain}  ${S_CERT}"
    brow "$S_GUARD"
    brow "${dim}Về VN${plain} ${S_RELAY}"
    hline '╰' '╯'
}

# ── Menu theo nhóm. Số mục GIỮ NGUYÊN như bản cũ (quen tay) ──
declare -A LABEL=(
    [1]='Cài đặt' [2]='Cập nhật' [3]='Gỡ bỏ' [4]='Bật' [5]='Dừng' [6]='Khởi động lại'
    [9]='Bật tự chạy' [10]='Tắt tự chạy'
    [7]='Trạng thái' [8]='Xem log' [14]='Cấu hình' [18]='Giới hạn TB'
    [11]='BBR' [12]='Mở cổng' [13]='Chặn speedtest' [20]='Ép MSS 1400'
    [21]='Chống OOM' [22]='Tối ưu mạng' [23]='Dọn KN chết' [24]='Chuyển tiếp VN'
    [19]='Cert LE' [16]='Cert tự ký' [15]='Khóa X25519' [17]='Cập nhật geo'
    [25]='Chống DDoS' [26]='Sức khoẻ' [27]='Tự cập nhật'
    [0]='Thoát'
)
MENU_GROUPS=(
    'DỊCH VỤ|1 2 27 3 4 5 6 9 10'
    'THEO DÕI|7 26 8 14 18'
    'MẠNG & HIỆU NĂNG|11 12 13 20 21 22 23 24 25'
    'CHỨNG CHỈ & DỮ LIỆU|19 16 15 17'
)
MENU_TOTAL=28
# Nhãn số: nền gradient, chữ đen đậm
pill() { printf '%s%s%s%3s %s' "${GB[$(( $2 * NG / MENU_TOTAL % NG ))]}" "${B1}" "${ESC}[38;5;16m" "$1" "$R0"; }
menu_item() {   # menu_item <số> <thứ tự> → "▌ 1  Cài đặt      " đúng bề ngang ô
    local cell=$(( (W - 2) / UI_COLS )) lbl="${LABEL[$1]}" pad
    pad=$(( cell - 5 - ${#lbl} )); [ "$pad" -lt 1 ] && pad=1
    printf '%s %s%*s' "$(pill "$1" "$2")" "$lbl" "$pad" ''
}
draw_menu() {
    local grp title nums n idx=0 line col
    for grp in "${MENU_GROUPS[@]}"; do
        title="${grp%%|*}"; nums="${grp#*|}"
        hline '╭' '╮' "$title"
        line=""; col=0
        for n in $nums; do
            line+="$(menu_item "$n" "$idx")"; idx=$(( idx + 1 )); col=$(( col + 1 ))
            if [ "$col" -eq "$UI_COLS" ]; then brow "$line"; line=""; col=0; fi
        done
        [ -n "$line" ] && brow "$line"
        hline '╰' '╯'
    done
    printf '  %s %b%s%b\n' "$(pill 0 $(( MENU_TOTAL - 1 )))" "$dim" "${LABEL[0]}" "$plain"
}

# Tên lửa nhỏ nằm ngang: lửa ░▒▓ → thân █ → mũi ► ; mini_rocket <cột> <khung lửa>
mini_rocket() {
    local p=$1 f=$2 pad tail
    printf -v pad '%*s' "$p" ''
    case $(( f % 3 )) in 0) tail="${FLC[3]}░${FLC[2]}▒${FLC[1]}▓" ;; 1) tail="${FLC[3]}·${FLC[2]}░${FLC[1]}▒" ;; *) tail="${FLC[2]}░${FLC[1]}▒${FLC[0]}▓" ;; esac
    printf '\r  %s%s%s██%s►%s\033[K' "$pad" "$tail" "${GC[$(( p % NG ))]}" "$HLC" "$R0"
}
# Hiệu ứng khi chọn mục: tên lửa nhỏ bay ngang, rồi tên mục hiện ra màu chạy
flash() {
    local t="$1" f p
    if anim_ok; then
        SKIP=0; cur_off
        for (( p=0; p<=26; p+=2 )); do mini_rocket "$p" "$p"; nap 0.018; done
        for (( f=0; f<NG; f++ )); do printf '\r  %s▸ %s%s%s\033[K' "${GC[$f]}" "$B1" "$(gtext "$t" "$f")" "$R0"; nap 0.022; done
        printf '\n\n'; cur_on
    else
        printf '  ▸ %s\n\n' "$t"
    fi
}
toast_err() { printf '  %b✗ %s%b\n' "$red" "$1" "$plain"; }

show_menu() {
    show_header
    echo ""
    draw_menu
    UI_FIRST=0; UI_REVEAL=0
    echo ""
    local prompt
    prompt="  ${GC[0]}❯${GC[$(( NG / 4 ))]}❯${GC[$(( NG / 2 ))]}❯${R0} "
    cur_on
    read -r -p "$prompt" choice
    choice="${choice//[[:space:]]/}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ -n "${LABEL[$choice]+x}" ] && [ "$choice" != 0 ]; then flash "${LABEL[$choice]}"; fi
    handle_choice "$choice"
}

handle_choice() {
    case "$1" in
    1)  install_v2bx ;;
    2)  update_v2bx ;;
    3)  uninstall_v2bx ;;
    4)  start_v2bx ;;
    5)  stop_v2bx ;;
    6)  restart_v2bx ;;
    7)  status_v2bx ;;
    8)  log_v2bx ;;
    9)  enable_autostart ;;
    10) disable_autostart ;;
    11) install_bbr ;;
    12) open_ports ;;
    13) block_speedtest ;;
    14) show_config ;;
    15) gen_x25519 ;;
    16) gen_ssl ;;
    17) update_geo ;;
    18) check_device_limit ;;
    19) gen_le_ssl ;;
    20) setup_mss_clamp ;;
    21) setup_mem_guard ;;
    22) tune_net ;;
    23) setup_conn_reaper ;;
    24) setup_relay_vn ;;
    25) ddos_menu ;;
    26) check_health ;;
    27) autoupdate_menu ;;
    0)  bye ;;
    *)  toast_err "Không có mục này"; sleep 0.8; show_menu ;;
    esac
}

# ── Các hàm xử lý ───────────────────────

install_v2bx() {
    bash <(curl -fLs "$INSTALL_SCRIPT")
    press_any_key
}

# ══════════════════════════════════════════
#   Cập nhật V2bX có kiểm tra + tự lùi (menu 2 · lệnh: hyx update [--force])
# ══════════════════════════════════════════
HX_REPO="${V2BX_REPO:-Tubetna/hypex-x}"
cur_ver()    { "$BINARY" version 2>/dev/null | grep -o 'v[0-9][0-9.]*' | head -1; }
# latest_info → LAT_TAG (vd v1.0.12) + LAT_AGE (số giây kể từ lúc phát hành; -1 nếu không rõ)
latest_info() {
    local j pub
    LAT_TAG=""; LAT_AGE=-1
    j=$(curl -fsSL --connect-timeout 8 -m 15 "https://api.github.com/repos/${HX_REPO}/releases/latest" 2>/dev/null) || return 1
    LAT_TAG=$(grep -o '"tag_name": *"[^"]*"' <<<"$j" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    pub=$(grep -o '"published_at": *"[^"]*"' <<<"$j" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    pub=$(date -d "$pub" +%s 2>/dev/null) && LAT_AGE=$(( $(date +%s) - pub ))
    [ -n "$LAT_TAG" ]
}
latest_ver() { latest_info; echo "$LAT_TAG"; }
# Cổng TCP V2bX đang nghe (để so trước/sau khi nâng)
node_ports() {   # bỏ cổng chỉ nghe nội bộ (vd pprof 127.0.0.1:6060)
    ss -Hltnp 2>/dev/null | grep '"V2bX"' | awk '{print $4}' | grep -vE '^(127\.|\[::1\]|::1)' \
        | sed 's/.*://' | sort -un | tr '\n' ' ' | sed 's/ $//'
}
unzip_to() {   # unzip_to <zip> <thư mục>
    if command -v unzip &>/dev/null; then unzip -oq "$1" -d "$2"
    else python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$1" "$2"; fi
}
update_hyx_script() {
    if curl -fsL --connect-timeout 15 -o /usr/local/bin/hyx.new "${SCRIPT_URL}/v2bx.sh" \
       && bash -n /usr/local/bin/hyx.new 2>/dev/null; then
        mv -f /usr/local/bin/hyx.new /usr/local/bin/hyx; chmod +x /usr/local/bin/hyx
        ln -sf /usr/local/bin/hyx /usr/local/bin/v2bx; ln -sf /usr/local/bin/hyx /usr/local/bin/hypex-x
        echo -e "  ${green}✓${plain} lệnh hyx: bản mới nhất"
    else
        rm -f /usr/local/bin/hyx.new
    fi
    # hx-ddos (nếu máy có) cũng kéo bản mới — chỉ thay file, luật đang chạy giữ nguyên
    if [ -x /usr/local/sbin/hx-ddos ] && curl -fsL --connect-timeout 15 -o /usr/local/sbin/hx-ddos.new "${SCRIPT_URL}/hx-ddos.sh" \
       && bash -n /usr/local/sbin/hx-ddos.new 2>/dev/null; then
        install -m 755 /usr/local/sbin/hx-ddos.new /usr/local/sbin/hx-ddos
    fi
    rm -f /usr/local/sbin/hx-ddos.new
}

# do_update <ask|yes|auto|force> → 0 xong · 1 lỗi (đã tự lùi) · 2 huỷ
#   auto = chạy theo lịch: như yes, nhưng chỉ cài bản đã phát hành ≥ AUTO_MIN_AGE giây (mặc định 24 giờ)
#   — bản lỗi không lan ra mọi máy ngay, còn thời gian thử tay trên 1 máy.
AUTO_MIN_AGE="${HYX_AUTO_MIN_AGE:-86400}"
do_update() {
    local mode="${1:-ask}" cur lat url tmp src d g a since i ok=0 why="" pb pa p
    detect_arch
    if [ -z "$ARCH_SUFFIX" ]; then echo -e "  ${red}✗ Không nhận ra kiến trúc CPU ($(uname -m)).${plain}"; return 1; fi
    cur=$(cur_ver); latest_info; lat="$LAT_TAG"
    echo -e "  Đang chạy ${B1}${cur:-?}${R0}   ·   Mới nhất ${B1}${lat:-không hỏi được GitHub}${R0}"
    if [ "$mode" = auto ]; then
        [ -z "$lat" ] && { echo "  không hỏi được GitHub — để lần sau"; return 0; }
        if [ "$cur" != "$lat" ] && [ "$LAT_AGE" -lt 0 ]; then
            echo "  không đọc được ngày phát hành ${lat} — để lần sau (không tự cài khi chưa chắc đủ 24 giờ)"
            update_hyx_script; return 0
        fi
        if [ "$cur" != "$lat" ] && [ "$LAT_AGE" -lt "$AUTO_MIN_AGE" ]; then
            echo "  ${lat} mới phát hành $(fmt_dur "$LAT_AGE") trước — chờ đủ $(( AUTO_MIN_AGE / 3600 )) giờ mới tự cài"
            update_hyx_script; return 0
        fi
        mode=yes
    fi
    if [ -n "$lat" ] && [ "$cur" = "$lat" ] && [ "$mode" != force ]; then
        if [ "$mode" = yes ]; then echo -e "  ${green}✓${plain} đã là bản mới nhất"; update_hyx_script; return 0; fi
        read -rp "  Đã là bản mới nhất. Cài lại? [y/N]: " a
        [[ "$a" =~ ^[yY]$ ]] || return 2
    fi
    if [ "$mode" = ask ] && [ "$cur" != "$lat" ]; then
        read -rp "  Nâng ${cur:-?} → ${lat:-bản mới nhất}? Node khởi động lại ~10 giây. [Y/n]: " a
        [[ "$a" =~ ^[nN]$ ]] && return 2
    fi
    if [ -n "$lat" ]; then url="https://github.com/${HX_REPO}/releases/download/${lat}/V2bX-${ARCH_SUFFIX}.zip"
    else url="${BASE_URL}/V2bX-${ARCH_SUFFIX}.zip"; fi

    tmp=$(mktemp -d /tmp/v2bx-up.XXXXXX) || return 1
    if ! spin "Tải V2bX ${lat:-mới nhất} · ${ARCH_SUFFIX}..." curl -fL --retry 3 --connect-timeout 15 -s -o "${tmp}/v.zip" "$url"; then
        echo -e "  ${red}✗ Tải thất bại — node không bị đụng tới.${plain}"; rm -rf "$tmp"; return 1
    fi
    if ! unzip_to "${tmp}/v.zip" "${tmp}/x" >/dev/null 2>&1; then
        echo -e "  ${red}✗ Giải nén thất bại (file hỏng?) — node không bị đụng tới.${plain}"; rm -rf "$tmp"; return 1
    fi
    src=$(find "${tmp}/x" -maxdepth 2 -type f -name 'V2bX' | head -1)
    [ -n "$src" ] && chmod +x "$src"
    # Thử binary mới TRƯỚC khi dừng dịch vụ — tránh tải nhầm kiến trúc rồi chết node
    if [ -z "$src" ] || ! "$src" version &>/dev/null; then
        echo -e "  ${red}✗ Binary mới không chạy được trên máy này — huỷ, node vẫn chạy bình thường.${plain}"; rm -rf "$tmp"; return 1
    fi
    if [ -n "$lat" ] && ! "$src" version 2>/dev/null | grep -q -- "$lat"; then
        echo -e "  ${red}✗ Gói tải về không phải ${lat} — huỷ.${plain}"; rm -rf "$tmp"; return 1
    fi

    # Sao lưu: binary cũ giữ hẳn theo tên phiên bản, geo cũ để trong thư mục tạm (dùng khi lùi)
    pb=$(node_ports)
    mkdir -p "$BIN_DIR" "${tmp}/geo_old"
    [ -f "$BINARY" ] && cp -pf "$BINARY" "${BIN_DIR}/V2bX.${cur:-old}.bak"
    d=$(dirname "$src")
    for g in geoip.dat geosite.dat geoip.db geosite.db; do [ -f "${CONF_DIR}/${g}" ] && cp -p "${CONF_DIR}/${g}" "${tmp}/geo_old/"; done

    since=$(date '+%Y-%m-%d %H:%M:%S')
    svc stop &>/dev/null
    install -m 755 "$src" "$BINARY"
    for g in geoip.dat geosite.dat geoip.db geosite.db; do
        [ -s "${d}/${g}" ] && install -m 644 "${d}/${g}" "${CONF_DIR}/${g}"
    done
    svc start
    svc enable &>/dev/null

    # Kiểm tối đa 40 s: dịch vụ chạy + đủ cổng như trước + log báo node đã lên, không panic
    for (( i=0; i<20; i++ )); do
        sleep 2
        anim_ok && printf '\r  %s%s%s Kiểm tra node mới... %ds\033[K' "${GC[$(( i % NG ))]}" "${SPF:$(( i % 10 )):1}" "$R0" $(( i * 2 + 2 ))
        if [ "$INIT_SYSTEM" = systemd ] && journalctl -u "$SERVICE" --since "$since" -o cat 2>/dev/null | grep -qiE 'panic|fatal error'; then
            why="log có panic"; break
        fi
        svc_active || { why="dịch vụ không chạy"; continue; }
        pa=" $(node_ports) "; why=""
        for p in $pb; do [[ "$pa" == *" $p "* ]] || why="thiếu cổng $p"; done
        [ -n "$why" ] && continue
        if [ "$INIT_SYSTEM" = systemd ] && ! journalctl -u "$SERVICE" --since "$since" -o cat 2>/dev/null \
               | grep -qE 'khởi động xong|Added [0-9]+ new users'; then
            why="node chưa báo đã lên"; continue
        fi
        ok=1; break
    done
    anim_ok && printf '\r\033[K'

    if [ "$ok" = 1 ]; then
        echo -e "  ${green}✓${plain} V2bX ${B1}$(cur_ver)${R0} chạy · cổng ${pb:-$(node_ports)} · bản cũ giữ ở ${dim}${BIN_DIR}/V2bX.${cur:-old}.bak${plain}"
        update_hyx_script
        rm -rf "$tmp"; return 0
    fi
    echo -e "  ${red}✗ Bản mới không ổn (${why:-quá thời gian}) — tự lùi về ${cur:-bản cũ}...${plain}"
    [ "$INIT_SYSTEM" = systemd ] && journalctl -u "$SERVICE" --since "$since" -o cat --no-pager 2>/dev/null | grep -v accepted | tail -8 | sed 's/^/    /'
    svc stop &>/dev/null
    [ -f "${BIN_DIR}/V2bX.${cur:-old}.bak" ] && install -m 755 "${BIN_DIR}/V2bX.${cur:-old}.bak" "$BINARY"
    for g in "${tmp}"/geo_old/*; do [ -f "$g" ] && install -m 644 "$g" "${CONF_DIR}/"; done
    svc start; sleep 5
    if svc_active; then echo -e "  ${yellow}↺${plain} đã về ${B1}$(cur_ver)${R0}, node chạy lại · cổng $(node_ports)"
    else echo -e "  ${red}✗ Lùi xong nhưng dịch vụ vẫn không chạy — xem log: menu 8.${plain}"; fi
    rm -rf "$tmp"; return 1
}
update_v2bx() { do_update ask; press_any_key; }

# ── Tự cập nhật theo lịch (menu 27 · lệnh: hyx autoupdate on|off|status) ──
# 20:30 UTC = 03:30 VN = 04:30 TQ (vắng khách), mỗi máy lệch ngẫu nhiên ≤ 30 phút để 2 máy cùng node
# không khởi động lại một lúc. Không có bản mới thì không đụng gì; có thì như menu 2 (kiểm tra + tự lùi).
AU=/etc/systemd/system/hyx-autoupdate
autoupdate_is_on() { systemctl is-enabled -q hyx-autoupdate.timer 2>/dev/null; }
autoupdate_on() {
    [ "$INIT_SYSTEM" = systemd ] || { echo "  Chỉ hỗ trợ máy dùng systemd."; return 1; }
    cat > "${AU}.service" <<'UNIT'
[Unit]
Description=hypex-x: tự cập nhật V2bX (chỉ bản đã phát hành >= 24 giờ; hỏng thì tự lùi)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=HYX_NOANIM=1
ExecStart=/usr/local/bin/hyx update --auto
UNIT
    cat > "${AU}.timer" <<'UNIT'
[Unit]
Description=hypex-x: lịch tự cập nhật V2bX (03:30 giờ VN, lệch ngẫu nhiên <= 30 phút)

[Timer]
OnCalendar=*-*-* 20:30:00 UTC
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload && systemctl enable --now hyx-autoupdate.timer >/dev/null 2>&1
    autoupdate_is_on && echo -e "  ${green}✓${plain} tự cập nhật: BẬT · lần tới $(autoupdate_next)"
}
autoupdate_off() {
    systemctl disable --now hyx-autoupdate.timer >/dev/null 2>&1
    echo -e "  ${yellow}○${plain} tự cập nhật: TẮT (cập nhật tay bằng menu 2)"
}
autoupdate_next() {   # đọc dạng epoch: `date` bản Rust (Ubuntu 26.04) đọc sai chuỗi "… UTC" → lệch 7 giờ
    local e; e=$(systemctl show hyx-autoupdate.timer -p NextElapseUSecRealtime --value --timestamp=unix 2>/dev/null | tr -d '@')
    [[ "$e" =~ ^[0-9]+$ ]] && TZ=Asia/Ho_Chi_Minh date -d "@$e" '+%H:%M %d/%m (giờ VN)' 2>/dev/null || echo "?"
}
autoupdate_last() {   # dòng kết quả của lần chạy gần nhất
    journalctl -u hyx-autoupdate.service -n 30 -o cat --no-pager 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' | grep -E '✓|✗|↺|chờ đủ|không hỏi|không đọc được' | tail -1 | sed 's/^ *//'
}
autoupdate_status() {
    if autoupdate_is_on; then echo -e "  ${green}●${plain} tự cập nhật: BẬT · lần tới $(autoupdate_next)"
    else echo -e "  ${yellow}○${plain} tự cập nhật: TẮT"; fi
    local l; l=$(autoupdate_last); [ -n "$l" ] && echo -e "  ${dim}lần gần nhất: ${l}${plain}"
}
autoupdate_menu() {
    local x
    autoupdate_status
    echo -e "  ${dim}Chạy 03:30 sáng giờ VN, chỉ cài bản đã phát hành ≥ 24 giờ; node lỗi thì tự lùi bản cũ.${plain}"
    echo ""
    if autoupdate_is_on; then read -rp "  Tắt tự cập nhật? [y/N]: " x; [[ "$x" =~ ^[yY]$ ]] && autoupdate_off
    else read -rp "  Bật tự cập nhật? [Y/n]: " x; [[ "$x" =~ ^[nN]$ ]] || autoupdate_on; fi
    press_any_key
}

# ══════════════════════════════════════════
#   Chống DDoS (menu 25) — bọc lệnh hx-ddos: bật/tắt, IP được SSH
# ══════════════════════════════════════════
HXD=/usr/local/sbin/hx-ddos
HXD_CONF=/etc/hx-ddos.conf
ddos_is_on() { iptables -S HX-DDOS &>/dev/null; }
ddos_conf_get() { ( PORT=""; ALLOW_SSH=""; [ -f "$HXD_CONF" ] && . "$HXD_CONF"; eval "printf '%s' \"\${$1}\"" ); }
ddos_conf_set() {   # ddos_conf_set KEY "giá trị" — giữ nguyên các dòng khác của file
    touch "$HXD_CONF"
    if grep -q "^$1=" "$HXD_CONF"; then sed -i "s|^$1=.*|$1=\"$2\"|" "$HXD_CONF"
    else echo "$1=\"$2\"" >> "$HXD_CONF"; fi
}
my_ssh_ip() {   # IP máy đang SSH vào (để không tự khoá mình)
    local ip="${SSH_CLIENT%% *}"
    [ -z "$ip" ] && ip=$(who -m 2>/dev/null | grep -oE '\(([0-9]{1,3}\.){3}[0-9]{1,3}\)' | tr -d '()')
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && echo "$ip"
}
ddos_get_script() {   # luôn lấy bản mới nhất (bản cũ không nhận nhiều cổng)
    if curl -fsL --connect-timeout 15 -o "${HXD}.new" "${SCRIPT_URL}/hx-ddos.sh" && bash -n "${HXD}.new" 2>/dev/null; then
        install -m 755 "${HXD}.new" "$HXD"
    fi
    rm -f "${HXD}.new"
    [ -x "$HXD" ]
}
ddos_menu() {
    local c ip ips port me n x new pk by
    while true; do
        clear; echo ""
        port=$(ddos_conf_get PORT); ips=$(ddos_conf_get ALLOW_SSH); me=$(my_ssh_ip)
        [ -z "$port" ] && port=$(node_ports)
        [ -z "$ips" ] && ips="43.133.42.80 103.5.209.17 103.5.209.20"
        BROW=0
        hline '╭' '╮' 'CHỐNG DDOS'
        if ddos_is_on; then
            read -r pk by < <(iptables -L HX-DDOS -nvx 2>/dev/null | tail -1 | awk '{print $1, $2}')
            brow "${green}● Đang bật${plain}   $(systemctl is-enabled hx-ddos.service &>/dev/null && echo "${dim}· tự bật khi khởi động${plain}")"
            brow "${dim}Đã chặn${plain}  ${B1}${pk:-0}${R0} gói · $(( ${by:-0} / 1048576 )) MB rác ${dim}(từ lúc bật)${plain}"
        else
            brow "${yellow}○ Đang tắt${plain}   ${dim}máy nhận mọi kết nối${plain}"
        fi
        brow "${dim}Cổng node${plain}  ${port:-?}"
        brow "${dim}SSH được phép từ$([ -f "$HXD_CONF" ] || echo ' (mặc định khi bật)'):${plain}"
        n=0
        for ip in $ips; do
            n=$((n+1))
            brow "   ${GC[$(( n % NG ))]}${n}.${R0} ${ip}$([ "$ip" = "$me" ] && echo "  ${green}← bạn đang ở đây${plain}")"
        done
        [ -n "$me" ] && [[ " $ips " != *" $me "* ]] && brow "   ${yellow}! IP bạn đang SSH (${me}) chưa có trong danh sách${plain}"
        hline '╰' '╯'
        echo ""
        printf '  %s Bật / áp lại   %s Tắt   %s Thêm IP SSH   %s Xoá IP SSH   %s Xem luật   %s Về menu\n' \
            "$(pill 1 0)" "$(pill 2 5)" "$(pill 3 10)" "$(pill 4 15)" "$(pill 5 20)" "$(pill 0 24)"
        echo ""
        cur_on; read -rp "  ${GC[0]}❯${GC[$(( NG / 2 ))]}❯${R0} " c
        case "$c" in
        1)
            ddos_get_script || { toast_err "Không tải được hx-ddos"; sleep 1.5; continue; }
            [ -n "$me" ] && [[ " $ips " != *" $me "* ]] && { ips="$ips $me"; echo -e "  ${green}+${plain} tự thêm IP của bạn ${me} để khỏi tự khoá"; }
            ddos_conf_set PORT "$port"; ddos_conf_set ALLOW_SSH "$ips"
            touch /root/hx-ddos.keep
            "$HXD" on; "$HXD" boot
            sleep 1.2 ;;
        2)
            read -rp "  Tắt chống DDoS? Máy sẽ nhận mọi kết nối. [y/N]: " x
            if [[ "$x" =~ ^[yY]$ ]] && [ -x "$HXD" ]; then "$HXD" off; "$HXD" unboot; rm -f /root/hx-ddos.keep; sleep 1.2; fi ;;
        3)
            [ -n "$me" ] && echo -e "  ${dim}IP bạn đang SSH: ${me}${plain}"
            read -rp "  IP được phép SSH thêm (IPv4): " new
            if [[ "$new" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                [[ " $ips " == *" $new "* ]] || ips="$ips $new"
                ddos_conf_set ALLOW_SSH "$ips"; [ -n "$(ddos_conf_get PORT)" ] || ddos_conf_set PORT "$port"
                ddos_is_on && { ddos_get_script; "$HXD" on >/dev/null; }
                echo -e "  ${green}✓${plain} đã thêm ${new}"; sleep 1
            else toast_err "IP không hợp lệ"; sleep 1; fi ;;
        4)
            read -rp "  Số thứ tự IP muốn xoá: " x
            set -- $ips
            if [[ "$x" =~ ^[0-9]+$ ]] && [ "$x" -ge 1 ] && [ "$x" -le $# ]; then
                ip="${!x}"
                if [ $# -le 1 ]; then toast_err "Phải giữ ít nhất 1 IP"; sleep 1.2; continue; fi
                if [ "$ip" = "$me" ]; then
                    read -rp "  ${ip} là IP bạn đang SSH — xoá là tự khoá mình khi đăng nhập lại. Vẫn xoá? [y/N]: " c
                    [[ "$c" =~ ^[yY]$ ]] || continue
                fi
                new=""; for x in $ips; do [ "$x" = "$ip" ] || new="$new $x"; done
                ddos_conf_set ALLOW_SSH "${new# }"
                ddos_is_on && { ddos_get_script; "$HXD" on >/dev/null; }
                echo -e "  ${green}✓${plain} đã xoá ${ip}"; sleep 1
            else toast_err "Không có số đó"; sleep 1; fi ;;
        5)
            echo ""; iptables -L HX-DDOS -nv --line-numbers 2>/dev/null || echo "  (chưa bật)"
            echo ""; read -rp "  Enter để quay lại " x ;;
        0|"") show_menu; return ;;
        *) toast_err "Không có mục này"; sleep 0.8 ;;
        esac
    done
}

# ══════════════════════════════════════════
#   Kiểm tra sức khoẻ (menu 26 · lệnh: hyx check)
# ══════════════════════════════════════════
HC_OK=0; HC_WARN=0; HC_BAD=0
hc() {   # hc ok|warn|bad|info "Nhãn" "chi tiết"
    local m c l="$2"
    case "$1" in
        ok)   m='✓'; c="$green";  HC_OK=$((HC_OK+1)) ;;
        warn) m='!'; c="$yellow"; HC_WARN=$((HC_WARN+1)) ;;
        bad)  m='✗'; c="$red";    HC_BAD=$((HC_BAD+1)) ;;
        *)    m='·'; c="$dim" ;;
    esac
    printf '  %b%s%b %s%*s %b\n' "$c" "$m" "$plain" "$l" $(( 15 - ${#l} )) '' "$3"
}
health_check() {
    local x y z n lat cur ports est act rss lim av sw dk jd old ago ct ctm orp orpm cert days ld cores lim1h top ram
    HC_OK=0; HC_WARN=0; HC_BAD=0
    echo ""; hline '╭' '╮' 'KIỂM TRA SỨC KHOẺ NODE'; echo ""
    # Dịch vụ
    if svc_active; then
        x=$(ps -o etimes= -C V2bX 2>/dev/null | head -1 | tr -d ' ')
        n=$(systemctl show "$SERVICE" -p NRestarts --value 2>/dev/null)
        hc ok "Dịch vụ" "đang chạy · lên $(fmt_dur "${x:-0}")$([ "${n:-0}" -gt 0 ] 2>/dev/null && echo " · đã tự khởi động lại ${n} lần")"
    else hc bad "Dịch vụ" "V2bX KHÔNG chạy → menu 4 bật, menu 8 xem log"; fi
    # Phiên bản
    cur=$(cur_ver); lat=$(latest_ver)
    if [ -z "$lat" ]; then hc info "Phiên bản" "${cur:-?} ${dim}(không hỏi được GitHub)${plain}"
    elif [ "$cur" = "$lat" ]; then hc ok "Phiên bản" "${cur} · mới nhất"
    else hc warn "Phiên bản" "${cur:-?} → đã có ${lat} · menu 2 để nâng"; fi
    # Cổng + kết nối
    ports=$(node_ports)
    if [ -n "$ports" ]; then
        est=0; for x in $ports; do est=$(( est + $(ss -Htn state established "( sport = :$x )" 2>/dev/null | wc -l) )); done
        hc ok "Cổng node" "${ports} · ${est} kết nối khách"
    else hc bad "Cổng node" "V2bX không nghe cổng nào (node chưa kéo được cấu hình từ panel?)"; fi
    # Panel API
    if [ "$INIT_SYSTEM" = systemd ]; then
        x=$(journalctl -u "$SERVICE" --since -10min -o cat 2>/dev/null | grep -v accepted | grep -v -i deprecated             | grep -ciE 'level=(error|fatal)|deadline exceeded|i/o timeout|status code: [45][0-9][0-9]')
        if [ "${x:-0}" -eq 0 ]; then hc ok "Panel API" "10 phút qua không lỗi"
        else
            y=$(journalctl -u "$SERVICE" --since -10min -o cat 2>/dev/null | grep -v accepted | grep -v -i deprecated                 | grep -iE 'level=(error|fatal)|deadline exceeded|i/o timeout|status code: [45][0-9][0-9]' | tail -1 | cut -c1-70)
            hc warn "Panel API" "${x} lỗi/10 phút · ${dim}${y}${plain}"
        fi
        # Chặn thiết bị
        lim1h=$(journalctl -u "$SERVICE" --since -1h --grep Limited -o cat 2>/dev/null | wc -l)
        if [ "$lim1h" -eq 0 ]; then hc ok "Chặn thiết bị" "1 giờ qua 0 lượt"
        else
            top=$(journalctl -u "$SERVICE" --since -1h --grep Limited -o cat 2>/dev/null | grep -oE '\|[0-9a-f-]{36}' | sort | uniq -c | sort -rn | head -1 | awk '{print substr($2,2,8)"… "$1" lượt"}')
            [ "$lim1h" -gt 500 ] && x=warn || x=info
            hc "$x" "Chặn thiết bị" "${lim1h} lượt/1 giờ · nhiều nhất ${top} ${dim}(menu 18 xem khách)${plain}"
        fi
    fi
    # RAM / OOM / tải
    av=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    sw=$(awk '/SwapTotal/{t=$2}/SwapFree/{f=$2}END{print int((t-f)/1024)"/"int(t/1024)}' /proc/meminfo)
    rss=$(ps -o rss= -C V2bX 2>/dev/null | head -1 | tr -d ' '); rss=$(( ${rss:-0} / 1024 ))
    lim=$(grep -ohE 'GOMEMLIMIT=[0-9]+MiB' /etc/systemd/system/V2bX.service.d/*.conf 2>/dev/null | head -1 | cut -d= -f2)
    ram="còn ${av} MB · V2bX ${rss} MB${lim:+ / trần ${lim}} · swap ${sw} MB"
    if   [ "$av" -lt 80 ];  then hc bad  "RAM" "$ram"
    elif [ "$av" -lt 150 ]; then hc warn "RAM" "$ram"
    else hc ok "RAM" "$ram"; fi
    [ -z "$lim" ] && hc warn "Chống OOM" "chưa đặt GOMEMLIMIT → menu 21"
    x=$(journalctl -k --since -24h -o cat 2>/dev/null | grep -c 'Killed process')
    y=$(journalctl -k --since -24h -o cat 2>/dev/null | grep 'Killed process' | grep -c 'V2bX')
    if [ "${y:-0}" -gt 0 ]; then hc bad "OOM 24 giờ" "V2bX bị kernel giết ${y} lần → khách đứt mạng; menu 21"
    elif [ "${x:-0}" -gt 0 ]; then hc warn "OOM 24 giờ" "${x} tiến trình khác bị giết"
    else hc ok "OOM 24 giờ" "không"; fi
    ld=$(cut -d' ' -f1 /proc/loadavg); cores=$(nproc 2>/dev/null || echo 1)
    if awk "BEGIN{exit !($ld > $cores * 1.5)}"; then hc warn "Tải CPU" "${ld} trên ${cores} nhân — quá tải"
    else hc ok "Tải CPU" "${ld} trên ${cores} nhân"; fi
    # Đĩa + log
    dk=$(df -P / | awk 'NR==2{print $5}' | tr -d '%')
    if   [ "$dk" -ge 90 ]; then hc bad  "Đĩa" "${dk}% — sắp đầy (log rsyslog/journal?)"
    elif [ "$dk" -ge 80 ]; then hc warn "Đĩa" "${dk}%"
    else hc ok "Đĩa" "${dk}% đã dùng"; fi
    if [ "$INIT_SYSTEM" = systemd ]; then
        jd=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]' | head -1)
        old=$(journalctl -u "$SERVICE" -o short-unix --no-pager -q 2>/dev/null | head -1 | cut -d. -f1)
        if [[ "$old" =~ ^[0-9]+$ ]]; then
            ago=$(( $(date +%s) - old ))
            if [ "$ago" -lt 21600 ]; then hc warn "Log giữ được" "$(fmt_dur "$ago") (journal ${jd:-?}) — tra khách quá xa không được; nâng SystemMaxUse"
            else hc ok "Log giữ được" "$(fmt_dur "$ago") · journal ${jd:-?}"; fi
        fi
        [ -f /etc/rsyslog.d/10-drop-v2bx.conf ] || { systemctl is-active -q rsyslog 2>/dev/null && hc warn "rsyslog" "đang chép log V2bX ra /var/log (dễ đầy đĩa)"; }
    fi
    # conntrack / orphan
    if [ -r /proc/sys/net/netfilter/nf_conntrack_max ]; then
        ct=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0); ctm=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
        x=$(journalctl -k --since -24h -o cat 2>/dev/null | grep -c 'table full')
        if [ "$(( ct * 100 / ctm ))" -ge 90 ] || [ "${x:-0}" -gt 0 ]; then
            hc bad "Conntrack" "${ct}/${ctm}$([ "${x:-0}" -gt 0 ] && echo " · ${x} lần 'table full' 24 giờ (rớt gói)")"
        elif [ "$(( ct * 100 / ctm ))" -ge 70 ]; then hc warn "Conntrack" "${ct}/${ctm}"
        else hc ok "Conntrack" "${ct}/${ctm}"; fi
    fi
    orp=$(awk '/^TCP:/{for(i=1;i<=NF;i++) if($i=="orphan") print $(i+1)}' /proc/net/sockstat)
    orpm=$(cat /proc/sys/net/ipv4/tcp_max_orphans 2>/dev/null)
    x=$(journalctl -k --since -24h -o cat 2>/dev/null | grep -c 'too many orphaned')
    if [ "${x:-0}" -gt 0 ]; then hc warn "Socket mồ côi" "${orp}/${orpm} · ${x} lần 'too many orphaned' 24 giờ"
    else hc ok "Socket mồ côi" "${orp:-0}/${orpm:-?}"; fi
    # Cấu hình
    x=$(grep -oE '"connIdle": *[0-9]+' "$CONFIG" 2>/dev/null | grep -oE '[0-9]+$')
    if [ -z "$x" ]; then hc warn "connIdle" "chưa đặt (mặc định Xray cắt kết nối im sớm) → nên 300"
    elif [ "$x" -lt 300 ]; then hc warn "connIdle" "${x} s — app chat/WeChat bị cắt, nên 300"
    else hc ok "connIdle" "${x} s"; fi
    iptables -t mangle -S INPUT 2>/dev/null | grep -q TCPMSS && hc ok "Ép MSS" "1400" || hc warn "Ép MSS" "chưa bật → menu 20 (web AWS/Xanh SM treo)"
    # Cert (chỉ khi file có thật)
    cert=$(grep -oE '"CertFile": *"[^"]+"' "$CONFIG" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    if [ -n "$cert" ] && [ -f "$cert" ]; then
        x=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
        if [ -n "$x" ]; then
            days=$(( ( $(date -d "$x" +%s) - $(date +%s) ) / 86400 ))
            y=$(openssl x509 -subject -noout -in "$cert" 2>/dev/null | sed 's/.*CN *= *//')
            if   [ "$days" -lt 0 ];  then hc bad  "Chứng chỉ" "${y} hết hạn ${days#-} ngày trước"
            elif [ "$days" -lt 15 ]; then hc warn "Chứng chỉ" "${y} còn ${days} ngày"
            else hc ok "Chứng chỉ" "${y} còn ${days} ngày"; fi
        fi
    fi
    # Giờ hệ thống (lệch giờ làm hỏng TLS/Reality)
    x=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    [ "$x" = yes ] && hc ok "Đồng bộ giờ" "NTP ổn" || { [ -n "$x" ] && hc warn "Đồng bộ giờ" "chưa đồng bộ NTP — lệch giờ làm hỏng TLS/Reality"; }
    ddos_is_on && hc info "Chống DDoS" "đang bật (menu 25)" || hc info "Chống DDoS" "tắt (menu 25)"
    if autoupdate_is_on; then hc ok "Tự cập nhật" "bật · lần tới $(autoupdate_next)"
    else hc info "Tự cập nhật" "tắt (menu 27)"; fi
    echo ""
    printf '  %b%d ổn%b  ·  %b%d cảnh báo%b  ·  %b%d lỗi%b\n' "$green" "$HC_OK" "$plain" "$yellow" "$HC_WARN" "$plain" "$red" "$HC_BAD" "$plain"
    [ "$HC_BAD" -gt 0 ] && return 2; [ "$HC_WARN" -gt 0 ] && return 1; return 0
}
check_health() { health_check; press_any_key; }

uninstall_v2bx() {
    read -p "$(echo -e "${red}Bạn có chắc muốn gỡ cài đặt V2bX không? [y/n]: ${plain}")" confirm
    if [[ "$confirm" =~ ^[yY] ]]; then
        svc stop &>/dev/null
        svc disable &>/dev/null
        rm -f /etc/systemd/system/$SERVICE.service /etc/init.d/$SERVICE
        rm -rf "$BIN_DIR" "$CONF_DIR"
        [ "${INIT_SYSTEM}" = "systemd" ] && systemctl daemon-reload
        echo -e "${green}Đã gỡ cài đặt V2bX thành công!${plain}"
    else
        echo -e "${yellow}Đã hủy.${plain}"
    fi
    press_any_key
}

start_v2bx()   { svc start;   echo -e "${green}Đã khởi động V2bX!${plain}";      press_any_key; }
stop_v2bx()    { svc stop;    echo -e "${yellow}Đã dừng V2bX!${plain}";          press_any_key; }
restart_v2bx() { svc restart; echo -e "${green}Đã khởi động lại V2bX!${plain}";  press_any_key; }

status_v2bx() {
    echo -e "  Dịch vụ      $(get_status)"
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        local since mem
        since=$(systemctl show $SERVICE -p ActiveEnterTimestamp --value 2>/dev/null | cut -d' ' -f2-3)
        mem=$(systemctl show $SERVICE -p MemoryCurrent --value 2>/dev/null)
        [ -n "$since" ] && echo -e "  Chạy từ      ${since}"
        [[ "$mem" =~ ^[0-9]+$ ]] && echo -e "  RAM          $((mem/1024/1024)) MB"
    fi
    echo -e "  Phiên bản    $(get_version | sed 's/ (.*//')"
    echo -e "  Node         ${yellow}$(get_nodes)${plain}"
    echo -e "  Panel        $(grep -oE '"ApiHost"[^,]*' "$CONFIG" 2>/dev/null | head -1 | cut -d'"' -f4)"
    echo -e "  Chứng chỉ    $(get_cert_info)"
    echo -e "  MSS/MTU      $(get_mss_status)"
    echo -e "  RAM/OOM      $(get_mem_status)"
    echo -e "  Dọn KN chết  $(get_reaper_status)"
    local ports
    ports=$( { ss -lntp 2>/dev/null | grep -i v2bx | awk '{print $4}'; ss -lnup 2>/dev/null | grep -i v2bx | awk '{print $5}'; } \
             | sed 's/.*://' | awk '$1 ~ /^[0-9]+$/ && $1<32768' | sort -un | tr '\n' ' ')
    echo -e "  Cổng nghe    ${ports:-${red}không có — node chưa lên hoặc chưa kéo được cấu hình${plain}}"
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        local conn errs
        rlog "journalctl -u $SERVICE --since -5min -o cat --grep accepted 2>/dev/null | wc -l; \
              journalctl -u $SERVICE --since -1h -o cat --grep 'level=error|failed|thất bại|panic' 2>/dev/null | wc -l" >/dev/null
        conn=$(sed -n 1p "$SPIN_OUT"); errs=$(sed -n 2p "$SPIN_OUT"); errs=${errs:-0}
        echo -e "  5 phút qua   ${conn} kết nối khách"
        if [ "$errs" -gt 0 ]; then
            echo -e "  1 giờ qua    ${red}${errs} dòng lỗi${plain} ${dim}(8 → 3)${plain}"
        else
            echo -e "  1 giờ qua    ${green}không lỗi${plain}"
        fi
    fi
    check_port_rivals
    press_any_key
}

# Linux cho nhieu tien trinh cung bind mot cong (SO_REUSEPORT) ma khong bao loi,
# nhung ket noi vao bi chia ngau nhien. Da gap tren 4 may: XrayR / x-ui chay song
# song V2bX, Node chi nhan duoc mot phan traffic, phan con lai roi vao tien trinh
# sai roi chet — ma khong co dau hieu gi trong log.
check_port_rivals() {
    local rivals="" port proc
    for port in 80 443; do
        while read -r proc; do
            case "$proc" in
                ""|*V2bX*) continue ;;
                *) rivals="${rivals}\n   cổng ${port}: ${proc}" ;;
            esac
        done <<< "$(ss -lntp 2>/dev/null | awk -v p=":${port}\$" '$4 ~ p {print $NF}' | sort -u)"
    done
    if [ -n "$rivals" ]; then
        echo -e "\n${red}⚠ Có tiến trình khác đang giữ cổng của Node:${plain}"
        echo -e "${yellow}${rivals}${plain}"
        echo -e "${yellow}Kết nối của khách sẽ bị chia ngẫu nhiên với nó. Nên dừng hẳn:${plain}"
        echo -e "${cyan}   systemctl stop XrayR && systemctl disable XrayR${plain}"
        echo -e "${cyan}   systemctl stop x-ui  && systemctl disable x-ui${plain}"
    else
        echo -e "\n${green}✓ Cổng 80/443 không bị tiến trình nào khác giành.${plain}"
    fi
}

# Log V2bX 95% là dòng "accepted" của khách — journal vài trăm MB, đọc 6 h mất >30 s.
# Dùng --grep của journalctl (lọc lúc đọc), phạm vi ngắn, và spinner cho khỏi tưởng treo.
JL="journalctl -q -u $SERVICE --no-pager -o short"
log_v2bx() {
    local isd=1; [ "${INIT_SYSTEM}" = "systemd" ] || isd=0
    echo -e "  $(m 0 1 'Trực tiếp')$(m 1 2 'Gần nhất')$(m 2 3 'Lỗi 1h')$(m 3 4 'Theo khách')$(m 4 5 'Lúc khởi động')"
    read -p "  ❯ [2] " c
    echo ""
    case "${c:-2}" in
        1)  echo -e "  ${dim}Ctrl+C để thoát${plain}"
            if [ $isd = 1 ]; then journalctl -u $SERVICE -f -o short; else tail -f /var/log/V2bX.log; fi ;;
        2)  if [ $isd = 1 ]; then rlog "$JL -n 3000 | grep -v accepted | tail -60 | cut -c1-170"
            else grep -v accepted /var/log/V2bX.log | tail -60; fi ;;
        3)  if [ $isd = 1 ]; then
                rlog "$JL --since -1h --grep 'level=error|level=warn|failed|panic|Limited|thất bại' | tail -60 | cut -c1-170"
            else grep -iE "error|warn|failed|panic|Limited" /var/log/V2bX.log | tail -60; fi
            echo -e "\n  ${dim}'Limited … by conn or ip' = khách vượt giới hạn thiết bị, không phải lỗi node.${plain}" ;;
        4)  read -p "  UUID / email: " who
            [ -z "$who" ] && { press_any_key; return; }
            if [ $isd = 1 ]; then
                spin "Đọc log..." bash -c "$JL --since -30min --grep '$who'"
                if [ ! -s "$SPIN_OUT" ]; then echo -e "  ${dim}Không thấy '$who' trong 30 phút qua trên node này.${plain}"
                else
                    echo -e "  ${dim}Kết nối theo phút (30 phút qua):${plain}"
                    awk '{print $3}' "$SPIN_OUT" | cut -c1-5 | sort | uniq -c | tail -20
                    echo -e "\n  ${dim}20 dòng gần nhất:${plain}"
                    tail -20 "$SPIN_OUT" | sed -E 's/\[\[[^]]*\]-//; s/email: .*//' | cut -c1-150
                fi
            else grep -F "$who" /var/log/V2bX.log | tail -20; fi ;;
        5)  if [ $isd = 1 ]; then
                local ts; ts=$(systemctl show $SERVICE -p ActiveEnterTimestamp --value 2>/dev/null)
                rlog "$JL --since '${ts:-1 day ago}' | grep -v accepted | head -30 | cut -c1-170"
            else grep -v accepted /var/log/V2bX.log | head -30; fi
            echo -e "\n  ${dim}Phải có 'Các Node đã khởi động xong' — thiếu = chưa kéo được cấu hình từ Panel.${plain}" ;;
    esac
    press_any_key
}

enable_autostart()  { svc enable;  echo -e "${green}Đã bật tự khởi động cùng hệ thống!${plain}";  press_any_key; }
disable_autostart() { svc disable; echo -e "${yellow}Đã tắt tự khởi động cùng hệ thống!${plain}"; press_any_key; }

install_bbr() {
    echo -e "${yellow}Đang bật BBR...${plain}"
    if ! grep -q "tcp_bbr" /proc/modules 2>/dev/null; then
        modprobe tcp_bbr 2>/dev/null
    fi
    if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
        echo -e "${red}Kernel này không hỗ trợ BBR (cần kernel >= 4.9).${plain}"
        press_any_key; return
    fi
    # Ghi vào file riêng và xoá dòng cũ để chạy nhiều lần không bị trùng
    cat > /etc/sysctl.d/99-v2bx-bbr.conf << 'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sed -i '/tcp_congestion_control\s*=\s*bbr/d;/default_qdisc\s*=\s*fq/d' /etc/sysctl.conf 2>/dev/null
    sysctl --system > /dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-v2bx-bbr.conf > /dev/null 2>&1
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        echo -e "${green}BBR đã được kích hoạt thành công!${plain}"
    else
        echo -e "${red}Kích hoạt BBR thất bại.${plain}"
    fi
    press_any_key
}

open_ports() {
    echo -e "${yellow}Mở cổng cho Node${plain}"
    echo -e "  1. Mở một dải cổng cụ thể (khuyên dùng)"
    echo -e "  2. Tắt hẳn tường lửa (mở tất cả — rủi ro)"
    read -p "  Chọn [1-2]: " fw_choice

    if [ "$fw_choice" = "1" ]; then
        read -p "  Nhập cổng hoặc dải cổng (VD: 443 hoặc 10000-20000): " prange
        if ! [[ "$prange" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
            echo -e "${red}Cổng không hợp lệ.${plain}"; press_any_key; return
        fi
        if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
            # firewalld dùng dấu gạch ngang cho dải cổng: 10000-20000
            firewall-cmd --permanent --add-port="${prange}/tcp" >/dev/null
            firewall-cmd --permanent --add-port="${prange}/udp" >/dev/null
            firewall-cmd --reload >/dev/null
            echo -e "${green}Đã mở ${prange} (tcp+udp) trên firewalld.${plain}"
        elif command -v ufw &>/dev/null; then
            ufw allow "${prange//-/:}/tcp" >/dev/null
            ufw allow "${prange//-/:}/udp" >/dev/null
            echo -e "${green}Đã mở ${prange} (tcp+udp) trên UFW.${plain}"
        elif command -v iptables &>/dev/null; then
            iptables -I INPUT -p tcp --dport "${prange/-/:}" -j ACCEPT
            iptables -I INPUT -p udp --dport "${prange/-/:}" -j ACCEPT
            echo -e "${green}Đã thêm rule iptables (chưa lưu vĩnh viễn).${plain}"
        else
            echo -e "${yellow}Không tìm thấy tường lửa nào đang chạy.${plain}"
        fi
    elif [ "$fw_choice" = "2" ]; then
        read -p "$(echo -e "${red}  Tắt hẳn tường lửa sẽ phơi toàn bộ cổng ra Internet. Chắc chưa? [y/n]: ${plain}")" c
        if [[ "$c" =~ ^[yY] ]]; then
            if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
                systemctl stop firewalld; systemctl disable firewalld
                echo -e "${green}Đã tắt firewalld.${plain}"
            elif command -v ufw &>/dev/null; then
                ufw disable
                echo -e "${green}Đã tắt UFW.${plain}"
            else
                echo -e "${yellow}Không có firewalld/ufw. Không đụng vào iptables để tránh phá rule Docker.${plain}"
            fi
        else
            echo -e "${yellow}Đã hủy.${plain}"
        fi
    else
        echo -e "${red}Lựa chọn không hợp lệ.${plain}"
    fi
    press_any_key
}

block_speedtest() {
    echo -e "${yellow}Đang chặn Speedtest...${plain}"
    echo -e "${yellow}  (chỉ khớp được tên miền trong SNI của gói ClientHello — không chặn được 100%)${plain}"
    for s in speedtest fast.com speed.cloudflare.com; do
        iptables -C OUTPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null \
            || iptables -I OUTPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null
    done
    echo -e "${green}Đã chặn các trang Speedtest phổ biến!${plain}"
    press_any_key
}

# 12/09/2026: đường node -> AWS Việt Nam (166.117.0.0/16, Global Accelerator) rớt gói
# 1500 byte mà không trả ICMP frag-needed -> app đặt trên AWS (Xanh SM...) treo ở logo,
# Google/Facebook vẫn chạy nên rất khó nhận ra. PMTU đo được 1482. Phải ép ở CẢ INPUT:
# rule OUTPUT chỉ ép cỡ gói server gửi về, cỡ gói node gửi đi theo SYN-ACK của server.
# 12/09/2026: máy 1 GB không swap, ~1.500 kết nối -> V2bX 700-800 MB -> OOM killer giết
# 10 lần/ngày, mỗi lần mọi khách trên máy đứt 10 s ("FB lúc load ảnh lúc không").
# Ba lớp: bufferSize 16 KB/kết nối, GOMEMLIMIT (Go dọn rác gắt trước trần), swap 1 GB.
# 13/09/2026: BBR+fq, buffer TCP 32 MB, TFO/NoDelay, DNS cache Xray, bufferSize 32,
# journald 300M, V2bX Nice -10. Script riêng tune-net.sh trong repo, tải về rồi chạy.
tune_net() {
    echo -e "${yellow}Đang tải và chạy bộ tối ưu mạng (tune-net.sh)...${plain}"
    if ! curl -fsSL -o /usr/local/sbin/hyx-tune-net.sh "https://raw.githubusercontent.com/Tubetna/hypex-x/main/tune-net.sh"; then
        echo -e "${red}Không tải được tune-net.sh.${plain}"; press_any_key; return
    fi
    chmod 755 /usr/local/sbin/hyx-tune-net.sh
    echo -e "${yellow}⚠ Node GAME thì đừng áp: khách Liên Quân từng báo khựng hơn (13/09). Node duyệt web/tải thì có lợi.${plain}"
    echo -e "${yellow}V2bX sẽ khởi động lại (khách rớt ~2 giây).${plain}"
    if bash /usr/local/sbin/hyx-tune-net.sh; then
        echo -e "${green}Xong. Kiểm: sysctl net.ipv4.tcp_congestion_control (bbr), tc qdisc show (fq).${plain}"
    else
        echo -e "${red}Script báo lỗi — xem dòng trên.${plain}"
    fi
    press_any_key
}

# 17/09/2026: node Reality trực tiếp (CHINA 1/2) giữ 7.000 ESTABLISHED với ~22 khách — phiên
# UDP 443 (QUIC) qua VLESS bị route block, Xray không đóng kết nối vào, app khách giữ socket
# mãi -> RAM vượt GOMEMLIMIT -> GC ăn 100% CPU. `ss -K` ngắt kết nối im > 15 phút, Xray nhận
# lỗi đọc và tự dọn, không cần restart. CN1: 7.089 -> 915 kết nối, CPU 100% -> 6%.
setup_conn_reaper() {
    echo -e "${yellow}Đang cài bộ dọn kết nối chết (conn-reaper, timer 5 phút)...${plain}"
    if ! command -v systemctl &>/dev/null || ! command -v ss &>/dev/null; then
        echo -e "${red}Cần systemd và iproute2 (ss).${plain}"; press_any_key; return
    fi
    if ! curl -fsSL -o /usr/local/sbin/v2bx-conn-reaper.sh "${SCRIPT_URL}/conn-reaper.sh"; then
        echo -e "${red}Không tải được conn-reaper.sh.${plain}"; press_any_key; return
    fi
    chmod 755 /usr/local/sbin/v2bx-conn-reaper.sh
    cat > /etc/systemd/system/v2bx-conn-reaper.service << 'EOF'
[Unit]
Description=V2bX: ngat ket noi TCP vao cong node da im qua 15 phut

[Service]
Type=oneshot
Nice=10
ExecStart=/usr/local/sbin/v2bx-conn-reaper.sh
EOF
    cat > /etc/systemd/system/v2bx-conn-reaper.timer << 'EOF'
[Unit]
Description=V2bX: don ket noi chet moi 5 phut

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now v2bx-conn-reaper.timer &>/dev/null
    local kcfg=/boot/config-$(uname -r)
    if [ -r "$kcfg" ] && ! grep -q '^CONFIG_INET_DIAG_DESTROY=y' "$kcfg"; then
        echo -e "${red}Kernel thiếu CONFIG_INET_DIAG_DESTROY — ss -K không ngắt được kết nối trên máy này.${plain}"
    fi
    # Chạy ngay một lượt và báo số trước/sau để thấy có tác dụng không
    local ports before after
    ports=$(ss -tlnpH 2>/dev/null | grep '"V2bX"' | awk '{split($4,a,":"); print a[length(a)]}' | sort -u | tr '\n' ' ')
    before=$(for p in $ports; do ss -tnH state established "( sport = :$p )" 2>/dev/null; done | wc -l)
    /usr/local/sbin/v2bx-conn-reaper.sh
    after=$(for p in $ports; do ss -tnH state established "( sport = :$p )" 2>/dev/null; done | wc -l)
    echo -e "${green}Đã bật timer 5 phút.${plain} Cổng node: ${ports:-?}· kết nối vào: ${before} → ${after}"
    echo -e "${dim}Log: journalctl -t v2bx-reaper · tắt: systemctl disable --now v2bx-conn-reaper.timer${plain}"
    press_any_key
}

# 24. Chuyển tiếp dịch vụ (TikTok/YouTube/.vn/AI…) sang node VN qua tài khoản relay — relay.sh
setup_relay_vn() {
    echo -e "${yellow}Chuyển tiếp dịch vụ sang node VN (relay-vn)${plain}"
    echo -e "  ${dim}1) Đặt / cập nhật   2) Gỡ   0) Quay lại${plain}"
    read -p "  ❯ " c
    case "$c" in
    1) ;;
    2) RELAY_REMOVE=1 bash /usr/local/sbin/v2bx-relay.sh 2>/dev/null || echo -e "${red}Chưa có relay.sh trên máy.${plain}"; press_any_key; return ;;
    *) return ;;
    esac
    if ! curl -fsSL -o /usr/local/sbin/v2bx-relay.sh "${SCRIPT_URL}/relay.sh"; then
        echo -e "${red}Không tải được relay.sh.${plain}"; press_any_key; return
    fi
    chmod 755 /usr/local/sbin/v2bx-relay.sh
    bash /usr/local/sbin/v2bx-relay.sh
    press_any_key
}

setup_mem_guard() {
    echo -e "${yellow}Đang đặt trần bộ nhớ + swap chống OOM cho V2bX...${plain}"
    local tot lim killed
    tot=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
    lim=$(( tot * 55 / 100 )); [ "$lim" -lt 256 ] && lim=256
    killed=$(journalctl -k --since -2days --grep 'Killed process .*V2bX' 2>/dev/null | grep -c Killed)
    echo -e "  RAM ${tot} MB · OOM giết V2bX ${killed} lần trong 2 ngày qua"
    if [ "$INIT_SYSTEM" = "systemd" ] 2>/dev/null || command -v systemctl &>/dev/null; then
        mkdir -p /etc/systemd/system/V2bX.service.d
        cat > /etc/systemd/system/V2bX.service.d/memory.conf << EOF
[Service]
# Go don rac gat gao khi heap cham ${lim} MiB (55% RAM) thay vi de OOM killer giet
Environment=GOMEMLIMIT=${lim}MiB
Environment=GOGC=100
EOF
        systemctl daemon-reload
        echo -e "  ${green}✓${plain} GOMEMLIMIT=${lim}MiB"
    fi
    if [ "$tot" -lt 2048 ] && [ "$(awk '/SwapTotal/{print $2}' /proc/meminfo)" = "0" ]; then
        if fallocate -l 1G /swapfile 2>/dev/null && chmod 600 /swapfile && mkswap /swapfile &>/dev/null && swapon /swapfile 2>/dev/null; then
            grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
            echo 'vm.swappiness=10' > /etc/sysctl.d/91-v2bx-swappiness.conf; sysctl -q -w vm.swappiness=10
            echo -e "  ${green}✓${plain} swap 1 GB"
        else
            rm -f /swapfile; echo -e "  ${yellow}!${plain} không tạo được swap"
        fi
    fi
    if [ -f "$CONFIG" ]; then
        cp -f "$CONFIG" "${CONFIG}.bak.mem.$(date +%Y%m%d%H%M%S)"
        if command -v python3 &>/dev/null; then
            python3 - "$CONFIG" << 'EOF'
import json, sys
p = sys.argv[1]; c = json.load(open(p))
for core in c.get("Cores", []):
    if core.get("Type") == "xray":
        core["XrayConnectionConfig"] = {"handshake": 4, "connIdle": 30, "uplinkOnly": 2, "downlinkOnly": 4, "bufferSize": 16}
json.dump(c, open(p, "w"), indent=2, ensure_ascii=False)
EOF
        elif grep -q '"XrayConnectionConfig"' "$CONFIG"; then
            sed -i -E 's/("bufferSize"[[:space:]]*:[[:space:]]*)[0-9]+/\116/' "$CONFIG"
        else
            # Không có python3: chèn ngay sau dòng "Type": "xray" (bộ cài luôn viết dòng này riêng)
            sed -i -E '0,/"Type"[[:space:]]*:[[:space:]]*"xray"[[:space:]]*,/s//&\n      "XrayConnectionConfig": {"handshake": 4, "connIdle": 30, "uplinkOnly": 2, "downlinkOnly": 4, "bufferSize": 16},/' "$CONFIG"
        fi
        if grep -q '"bufferSize"[[:space:]]*:[[:space:]]*16' "$CONFIG"; then
            echo -e "  ${green}✓${plain} bufferSize 16 KB/kết nối (config.json)"
        else
            echo -e "  ${yellow}!${plain} không sửa được bufferSize trong config.json — thêm tay khối XrayConnectionConfig"
        fi
    fi
    echo -e "${yellow}Khởi động lại V2bX để áp dụng (khách rớt ~2 giây)...${plain}"
    systemctl restart V2bX 2>/dev/null || service V2bX restart 2>/dev/null
    sleep 3
    if systemctl is-active --quiet V2bX 2>/dev/null; then
        local pid; pid=$(systemctl show V2bX -p MainPID --value)
        echo -e "${green}V2bX đang chạy, RSS $(( $(ps -o rss= -p "$pid") / 1024 )) MB. Trần ${lim} MiB, kiểm lại sau vài giờ bằng menu 7.${plain}"
    else
        echo -e "${red}V2bX không lên — xem log (menu 8).${plain}"
    fi
    press_any_key
}

setup_mss_clamp() {
    echo -e "${yellow}Đang ép MSS 1400 + bật dò MTU (tcp_mtu_probing)...${plain}"
    if ! command -v iptables &>/dev/null; then
        echo -e "${red}Máy không có iptables.${plain}"; press_any_key; return
    fi
    cat > /etc/sysctl.d/90-v2bx-mtu.conf << 'EOF'
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1200
EOF
    sysctl -q -p /etc/sysctl.d/90-v2bx-mtu.conf 2>/dev/null
    cat > /usr/local/sbin/mss-clamp.sh << 'EOF'
#!/bin/sh
# Ep MSS moi ket noi TCP qua node xuong 1400 (PMTU toi AWS VN = 1482 -> toi da 1442).
for t in iptables ip6tables; do
    command -v "$t" >/dev/null 2>&1 || continue
    for c in INPUT OUTPUT FORWARD; do
        "$t" -t mangle -C "$c" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400 2>/dev/null || \
        "$t" -t mangle -A "$c" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400 2>/dev/null
    done
done
exit 0
EOF
    chmod 755 /usr/local/sbin/mss-clamp.sh
    if command -v systemctl &>/dev/null; then
        cat > /etc/systemd/system/mss-clamp.service << 'EOF'
[Unit]
Description=Clamp TCP MSS to 1400 (V2bX - duong toi AWS VN rot goi 1500)
After=network-pre.target
Wants=network-pre.target
Before=network.target V2bX.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mss-clamp.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now mss-clamp.service &>/dev/null
    else
        /usr/local/sbin/mss-clamp.sh
    fi
    if iptables -t mangle -S INPUT 2>/dev/null | grep -q TCPMSS; then
        echo -e "${green}Đã ép MSS 1400 ở INPUT/OUTPUT/FORWARD, bền qua reboot.${plain}"
    else
        echo -e "${red}Không thêm được rule TCPMSS (thiếu module xt_TCPMSS?).${plain}"
        press_any_key; return
    fi
    # Nghiệm thu đúng bệnh: GET nhỏ luôn qua, chỉ POST > 1,4 KB mới lộ — phải về trong < 1 s
    if command -v curl &>/dev/null; then
        echo -e "${yellow}Kiểm thử POST 3 KB tới AWS Việt Nam (api-ub.vn.gsm-api.net)...${plain}"
        local body t
        body=$(head -c 3000 /dev/zero | tr '\0' 'a')
        t=$(curl -4 -s -o /dev/null -m 8 -X POST --data-binary "$body" -w '%{time_total}' \
            https://api-ub.vn.gsm-api.net/ 2>/dev/null)
        case "$t" in
            0.*|1.*) echo -e "${green}  ✓ ${t}s — đường tới AWS VN thông.${plain}" ;;
            "")      echo -e "${yellow}  ⚠ Không đo được (không ra internet?).${plain}" ;;
            *)       echo -e "${red}  ✗ ${t}s — vẫn chậm/treo, kiểm 'ping -M do -s 1452 166.117.34.35'.${plain}" ;;
        esac
    fi
    press_any_key
}

show_config() {
    if [ -f "$CONFIG" ]; then
        echo -e "${cyan}══ Nội dung file $CONFIG ══${plain}"
        cat "$CONFIG"
    else
        echo -e "${red}Không tìm thấy file cấu hình!${plain}"
    fi
    press_any_key
}

gen_x25519() {
    echo -e "${yellow}Đang tạo cặp khóa X25519...${plain}"
    if [ -f "$BINARY" ]; then
        $BINARY x25519
    else
        echo -e "${red}V2bX chưa được cài đặt!${plain}"
    fi
    press_any_key
}

# Cert va key tren dia phai cung mot cap khoa (public key giong nhau) va khong rong.
# acme.sh --install-cert chay reloadcmd ngay; service chua co thi no tra exit 1 du
# cert da chep xong -> ket qua that phai kiem tren dia, khong tin exit code.
cert_key_match() {
    [ -s "$1" ] && [ -s "$2" ] || return 1
    local a b
    a=$(openssl x509 -in "$1" -pubkey -noout 2>/dev/null | md5sum)
    b=$(openssl pkey -in "$2" -pubout 2>/dev/null | md5sum)
    [ -n "$a" ] && [ "$a" = "$b" ]
}

# Cấp chứng chỉ thật từ Let's Encrypt cho node chạy cổng 443.
#
# Cert tự ký không còn dùng được trong thực tế: xray-core 26.x đã xoá tuỳ chọn
# allowInsecure nên client mới từ chối nạp cấu hình có nó; CloudFront từ chối
# thẳng origin HTTPS không có cert hợp lệ; còn Cloudflare thì không chịu tải
# luồng dài (XHTTP stream-one) qua origin cert tự ký.
# Kiểm tên miền TRƯỚC khi xin cert. Bẫy ngày 11/09/2026: nhập `cloudaz1.hypexcloud.com`
# (tên Host header WS, đang bật proxy Cloudflare) thay vì tên origin `cloudvip1az…`
# trỏ thẳng IP máy → HTTP-01 hỏng → bộ cài âm thầm rơi về cert tự ký → CloudFront 502,
# node 443 chết với khách mà không ai biết. Giờ phải chỉ ra ngay và không được im lặng.
#   0 = trỏ thẳng về máy này    10 = đang qua proxy Cloudflare
#  20 = trỏ về IP khác           30 = không phân giải được
DOMAIN_POINTS_TO=""
MY_PUBLIC_IP=""
check_cert_domain() {
    local domain="$1" ips first
    [ -z "$MY_PUBLIC_IP" ] && MY_PUBLIC_IP=$(curl -fsS -4 --max-time 8 https://api.ipify.org 2>/dev/null \
        || curl -fsS -4 --max-time 8 https://ifconfig.me 2>/dev/null)
    MY_PUBLIC_IP=$(echo "$MY_PUBLIC_IP" | tr -d '[:space:]')
    ips=$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
    [ -z "$ips" ] && return 30
    first=$(echo "$ips" | head -1); DOMAIN_POINTS_TO="$first"
    [ -n "$MY_PUBLIC_IP" ] && echo "$ips" | grep -qx "$MY_PUBLIC_IP" && return 0
    # Proxy Cloudflare (đám mây cam) trả header "server: cloudflare" ở mọi IP của nó
    if curl -sI -4 --max-time 6 -H "Host: $domain" "http://$first/" 2>/dev/null \
            | grep -qi '^server: *cloudflare'; then
        return 10
    fi
    return 20
}

# acme.sh nhớ token Cloudflare của lần trước trong account.conf; có nó thì DNS-01 chạy được
# dù người cài không dán lại token.
has_saved_cf_token() {
    grep -q '^SAVED_CF_Token=' /root/.acme.sh/account.conf 2>/dev/null
}

# In kết luận của check_cert_domain cho người cài. $1 = mã trả về, $2 = tên miền
explain_cert_domain() {
    case "$1" in
        0)  echo -e "${green}  ✓ ${2} trỏ thẳng về máy này (${MY_PUBLIC_IP}).${plain}" ;;
        10) echo -e "${red}  ✗ ${2} đang bật PROXY Cloudflare (đám mây cam), trỏ tới ${DOMAIN_POINTS_TO}.${plain}"
            echo -e "${yellow}    Xác thực qua cổng 80 chắc chắn thất bại. Và quan trọng hơn: nếu node đứng${plain}"
            echo -e "${yellow}    sau CloudFront thì tên cần cấp là tên ORIGIN trỏ thẳng IP máy (DNS-only),${plain}"
            echo -e "${yellow}    KHÔNG phải tên trong Host header WebSocket. Kiểm lại tên trước khi tiếp.${plain}" ;;
        20) echo -e "${red}  ✗ ${2} trỏ về ${DOMAIN_POINTS_TO}, còn máy này là ${MY_PUBLIC_IP:-?}.${plain}"
            echo -e "${yellow}    Cert vẫn cấp được qua DNS Cloudflare, nhưng khách/CDN sẽ nối tới IP kia${plain}"
            echo -e "${yellow}    chứ không phải máy này. Thường là chưa đổi bản ghi DNS sang máy mới.${plain}" ;;
        30) echo -e "${red}  ✗ Không phân giải được ${2}. Bản ghi DNS chưa có hoặc gõ sai.${plain}" ;;
    esac
}

gen_le_ssl() {
    local domain cf_token acme=/root/.acme.sh/acme.sh

    read -p "Nhập tên miền trỏ về máy này (VD: node1.domain.com): " domain
    if [ -z "$domain" ]; then
        echo -e "${red}Chưa nhập tên miền.${plain}"; press_any_key; return
    fi

    echo -e "${yellow}Nếu tên miền nằm trên Cloudflare (nhất là khi đang bật proxy),${plain}"
    echo -e "${yellow}dán API Token có quyền Zone:DNS:Edit để xác thực qua DNS.${plain}"
    echo -e "${yellow}Bỏ trống thì xác thực qua cổng 80 — tên miền phải trỏ thẳng về IP máy này.${plain}"
    if has_saved_cf_token; then
        echo -e "${green}(acme.sh đã lưu token Cloudflare từ lần trước — Enter để dùng lại)${plain}"
    fi
    read -p "Cloudflare API Token (bỏ trống để dùng cổng 80): " cf_token

    command -v curl &>/dev/null || {
        echo -e "${red}Máy chưa có curl.${plain}"; press_any_key; return; }

    # Kiểm tên miền trước khi xin — sai tên (proxy Cloudflare, trỏ máy khác) thì
    # phải biết ngay, không để acme thất bại rồi node 443 chạy cert tự ký.
    echo -e "${cyan}Kiểm tra ${domain}...${plain}"
    check_cert_domain "$domain"; local rc=$?
    explain_cert_domain "$rc" "$domain"
    if [ "$rc" -ne 0 ]; then
        if [ "$rc" -eq 30 ] || { [ -z "$cf_token" ] && ! has_saved_cf_token; }; then
            echo -e "${red}Không cấp được với tên này. Sửa DNS hoặc dùng API Token rồi chạy lại.${plain}"
            press_any_key; return
        fi
        read -p "Vẫn cấp cert cho tên này qua DNS Cloudflare? [y/N]: " ok
        [[ "$ok" =~ ^[yY] ]] || { press_any_key; return; }
    fi

    if [ ! -f "$acme" ]; then
        echo -e "${yellow}Đang cài acme.sh...${plain}"
        curl -fsS https://get.acme.sh | sh -s email="admin@${domain}" &>/dev/null || {
            echo -e "${red}Cài acme.sh thất bại.${plain}"; press_any_key; return; }
    fi
    "$acme" --set-default-ca --server letsencrypt &>/dev/null

    mkdir -p "$CONF_DIR"
    local issued=false

    if [ -n "$cf_token" ] || has_saved_cf_token; then
        [ -z "$cf_token" ] && echo -e "${yellow}Dùng lại token Cloudflare đã lưu trong acme.sh.${plain}"
        echo -e "${yellow}Đang xin chứng chỉ cho ${domain} (xác thực qua DNS Cloudflare)...${plain}"
        CF_Token="$cf_token" "$acme" --issue --dns dns_cf -d "$domain" \
            --keylength ec-256 && issued=true
    else
        local stopped=false
        if ss -lnt 2>/dev/null | grep -q ':80 '; then
            echo -e "${yellow}Tạm dừng V2bX để giải phóng cổng 80...${plain}"
            svc stop &>/dev/null && stopped=true
            sleep 2
        fi
        # Cổng 80 có thể do tiến trình khác giữ (xray rời, nginx, XrayR...),
        # dừng V2bX không giải phóng được. Báo rõ tên tiến trình cho khỏi mò.
        if ss -lnt 2>/dev/null | grep -q ':80 '; then
            local holder
            holder=$(ss -lntp 2>/dev/null | awk '$4 ~ /:80$/ {print $NF; exit}')
            echo -e "${red}Cổng 80 vẫn đang bị chiếm: ${holder:-không rõ tiến trình}${plain}"
            echo -e "${yellow}Dừng tiến trình đó rồi chạy lại, hoặc dùng Cloudflare API Token${plain}"
            echo -e "${yellow}để xác thực qua DNS (không cần cổng 80).${plain}"
            [ "$stopped" = true ] && svc start &>/dev/null
            press_any_key; return
        fi
        echo -e "${yellow}Đang xin chứng chỉ cho ${domain} (xác thực qua cổng 80)...${plain}"
        "$acme" --issue --standalone -d "$domain" --keylength ec-256 && issued=true
        [ "$stopped" = true ] && svc start &>/dev/null
    fi

    # acme.sh trả mã lỗi khi cert còn hạn ("Skipping. Next renewal time is...").
    # Đó không phải lỗi — cert đã có sẵn, cứ đem đi cài là được.
    if [ "$issued" != true ] && [ -s "/root/.acme.sh/${domain}_ecc/fullchain.cer" ]; then
        echo -e "${yellow}Tên miền này đã có chứng chỉ còn hạn, dùng lại chứng chỉ cũ.${plain}"
        issued=true
    fi

    if [ "$issued" != true ]; then
        echo -e "${red}Xin chứng chỉ thất bại cho ${domain}.${plain}"
        echo -e "${yellow}  • Qua DNS Cloudflare: API Token phải có quyền Zone:DNS:Edit.${plain}"
        echo -e "${yellow}  • Qua cổng 80: tên miền phải trỏ đúng IP máy này và cổng 80 phải mở.${plain}"
        press_any_key; return
    fi

    local reload="systemctl restart ${SERVICE}"
    [ "$INIT_SYSTEM" = "openrc" ] && reload="rc-service ${SERVICE} restart"

    # reloadcmd: mỗi lần acme.sh tự gia hạn thì V2bX nạp lại cert mới
    "$acme" --install-cert -d "$domain" --ecc \
            --fullchain-file "${CONF_DIR}/cert.crt" \
            --key-file "${CONF_DIR}/private.key" \
            --reloadcmd "$reload 2>/dev/null || true" &>/dev/null
    if ! cert_key_match "${CONF_DIR}/cert.crt" "${CONF_DIR}/private.key"; then
        echo -e "${red}Cài chứng chỉ vào ${CONF_DIR} thất bại.${plain}"
        press_any_key; return
    fi

    chmod 600 "${CONF_DIR}/private.key"
    echo -e "${green}✓ Đã cấp chứng chỉ thật cho ${domain}${plain}"
    openssl x509 -in "${CONF_DIR}/cert.crt" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/  /'
    echo -e "  Cert : ${white}${CONF_DIR}/cert.crt${plain}"
    echo -e "  Key  : ${white}${CONF_DIR}/private.key${plain}"
    echo -e "${green}  Tự động gia hạn đã bật sẵn (cron của acme.sh).${plain}"
    echo -e "${yellow}  Nhớ tắt allowInsecure của node này trên Panel.${plain}"

    read -p "Khởi động lại V2bX để dùng cert mới ngay? (y/n): " yn
    [[ "$yn" =~ ^[yY] ]] && svc restart
    press_any_key
}

gen_ssl() {
    SERVER_IP=$(curl -s --max-time 10 https://api.ipify.org || echo "127.0.0.1")
    echo -e "${yellow}Đang tạo chứng chỉ SSL tự ký cho IP: ${SERVER_IP}${plain}"
    mkdir -p "$CONF_DIR"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "${CONF_DIR}/private.key" \
        -out "${CONF_DIR}/cert.crt" \
        -subj "/C=VN/ST=Server/L=Server/O=V2bX/OU=Node/CN=${SERVER_IP}" 2>/dev/null
    chmod 600 "${CONF_DIR}/private.key"
    echo -e "${green}Đã tạo chứng chỉ SSL tại:${plain}"
    echo -e "  Cert : ${white}${CONF_DIR}/cert.crt${plain}"
    echo -e "  Key  : ${white}${CONF_DIR}/private.key${plain}"
    press_any_key
}

update_geo() {
    # Xray đọc geo từ AssetPath (/etc/V2bX/), sing-box đọc geoip.db/geosite.db
    # từ thư mục làm việc — cũng là /etc/V2bX. Thiếu là rule geoip:/geosite: lỗi.
    echo -e "${yellow}Đang cập nhật dữ liệu geo vào ${CONF_DIR}...${plain}"
    mkdir -p "$CONF_DIR"
    local base="https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release"
    local sing="https://github.com/SagerNet/sing-geoip/releases/latest/download"
    local site="https://github.com/SagerNet/sing-geosite/releases/latest/download"
    local ok=0
    for pair in "geoip.dat:${base}/geoip.dat" "geosite.dat:${base}/geosite.dat" \
                "geoip.db:${sing}/geoip.db"   "geosite.db:${site}/geosite.db"; do
        local name="${pair%%:*}" url="${pair#*:}"
        echo -ne "  ${name} ... "
        if curl -fL --retry 2 --connect-timeout 20 -s -o "${CONF_DIR}/${name}.tmp" "$url" \
           && [ -s "${CONF_DIR}/${name}.tmp" ]; then
            mv -f "${CONF_DIR}/${name}.tmp" "${CONF_DIR}/${name}"
            chmod 644 "${CONF_DIR}/${name}"
            echo -e "${green}xong${plain}"; ok=$((ok+1))
        else
            rm -f "${CONF_DIR}/${name}.tmp"
            echo -e "${red}lỗi${plain}"
        fi
    done
    echo -e "${green}Đã cập nhật ${ok}/4 file.${plain}"
    if [ "$ok" -gt 0 ] && svc_active; then
        read -p "  Khởi động lại V2bX để nạp geo mới? [y/n]: " c
        [[ "$c" =~ ^[yY] ]] && { svc restart; echo -e "${green}Đã khởi động lại.${plain}"; }
    fi
    press_any_key
}

check_device_limit() {
    echo -e "${cyan}══ Kiểm tra giới hạn thiết bị ══${plain}\n"

    # Giới hạn thiết bị KHÔNG cấu hình ở Node. Node chỉ thực thi:
    #   Node báo IP đang online  → POST /api/v1/server/UniProxy/alive
    #   Panel đếm rồi trả về     → GET  /api/v1/server/UniProxy/alivelist
    #   Node chặn khi số IP >= device_limit của user
    # Giá trị device_limit đặt trong Panel, theo Gói cước hoặc theo từng User.
    echo -e "${yellow}Cách hoạt động:${plain}"
    echo -e "  Node báo IP online → Panel đếm → Panel trả alivelist → Node chặn."
    echo -e "  ${white}Số thiết bị đặt trong PANEL${plain} (Gói cước hoặc User), không đặt ở đây."
    echo -e "  Khoá 'DeviceLimit' trong config.json của Node ${red}không có tác dụng${plain}.\n"

    if [ ! -f "$CONFIG" ]; then
        echo -e "${red}Chưa có config.json.${plain}"; press_any_key; return
    fi

    local host key
    host=$(grep -oE '"ApiHost"[^,]*' "$CONFIG" | head -1 | cut -d'"' -f4)
    key=$(grep -oE '"ApiKey"[^,]*'  "$CONFIG" | head -1 | cut -d'"' -f4)
    local nid
    nid=$(grep -oE '"NodeID"\s*:\s*[0-9]+' "$CONFIG" | head -1 | grep -oE '[0-9]+')
    local ntype
    ntype=$(grep -oE '"NodeType"[^,]*' "$CONFIG" | head -1 | cut -d'"' -f4)

    if [ -z "$host" ] || [ -z "$key" ] || [ -z "$nid" ]; then
        echo -e "${red}Không đọc được ApiHost/ApiKey/NodeID từ config.json.${plain}"
        press_any_key; return
    fi

    echo -e "${yellow}Panel   :${plain} ${host}"
    echo -e "${yellow}Node    :${plain} #${nid} (${ntype})\n"

    # Panel nhận node_type viết thường, và V2ray phải đổi thành "vmess"
    # (giống api/panel/panel.go làm khi Node gọi Panel)
    local ntype_q
    ntype_q=$(echo "$ntype" | tr 'A-Z' 'a-z')
    [ "$ntype_q" = "v2ray" ] && ntype_q="vmess"
    local q="node_id=${nid}&node_type=${ntype_q}&token=${key}"

    echo -ne "  1) Panel có endpoint alivelist  ... "
    local body code
    body=$(curl -s -m 20 -w '\n%{http_code}' "${host}/api/v1/server/UniProxy/alivelist?${q}")
    code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    if [ "$code" = "200" ]; then
        echo -e "${green}OK (200)${plain}"
        local n
        n=$(echo "$body" | grep -oE '"[0-9]+":[0-9]+' | wc -l)
        echo -e "     Đang có ${white}${n}${plain} user bị đếm thiết bị."
        [ "$n" -gt 0 ] && echo -e "     ${cyan}$(echo "$body" | head -c 300)${plain}"
    else
        echo -e "${red}HTTP ${code}${plain}"
        echo -e "     ${red}→ Panel không trả alivelist thì Node KHÔNG chặn được thiết bị.${plain}"
    fi

    echo -ne "  2) Panel có trả device_limit    ... "
    body=$(curl -s -m 20 -w '\n%{http_code}' "${host}/api/v1/server/UniProxy/user?${q}")
    code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    if [ "$code" = "200" ]; then
        if echo "$body" | grep -q '"device_limit"'; then
            local limited
            limited=$(echo "$body" | grep -oE '"device_limit":[1-9][0-9]*' | wc -l)
            echo -e "${green}OK — ${limited} user có giới hạn > 0${plain}"
            [ "$limited" = "0" ] && \
                echo -e "     ${yellow}⚠ Tất cả user đang device_limit = 0 (không giới hạn). Đặt trong Panel → Gói cước.${plain}"
        else
            echo -e "${red}Thiếu trường device_limit${plain}"
        fi
    else
        echo -e "${red}HTTP ${code}${plain}"
    fi

    echo -ne "  3) Node đang báo IP online      ... "
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        local rep
        rep=$(journalctl -u $SERVICE --since "-10 min" --no-pager 2>/dev/null | grep -c "online users")
        if [ "$rep" -gt 0 ]; then
            echo -e "${green}có (${rep} lần trong 10 phút qua)${plain}"
            journalctl -u $SERVICE --since "-10 min" --no-pager 2>/dev/null \
                | grep "online users" | tail -2 | sed 's/^/     /'
        else
            echo -e "${yellow}chưa thấy${plain}"
            echo -e "     Bình thường nếu chưa có ai dùng Node. Nếu đã có khách mà vẫn trống"
            echo -e "     thì kiểm tra DeviceOnlineMinTraffic trong config.json."
        fi
    else
        grep -c "online users" /var/log/V2bX.log 2>/dev/null | sed 's/^/     /'
    fi

    echo ""
    press_any_key
}

press_any_key() {
    echo ""
    hline '╶' '╴'
    read -r -p "  ${GC[2]}↵${R0} ${D1}Enter để về menu${R0} " dummy
    show_menu
}

bye() {
    echo ""
    if anim_ok; then
        local f p end=$(( W - 4 ))
        SKIP=0; cur_off
        for (( p=0; p<=end; p+=3 )); do mini_rocket "$p" "$p"; nap 0.016; done   # bay khỏi màn
        for (( f=0; f<NG; f++ )); do printf '\r  %s▸ %s\033[K' "${GC[$f]}" "$(gtext 'Tạm biệt · hẹn gặp lại!' "$f")"; nap 0.03; done
        printf '\n\n'; cur_on
    else
        echo "  Tạm biệt!"
    fi
    exit 0
}

# ── Khởi chạy ────────────────────────────
# Lệnh không cần menu (chạy hàng loạt qua SSH):
#   hyx update [--force]   nâng V2bX lên bản mới nhất, hỏng thì tự lùi (mã thoát 0 ổn · 1 lỗi đã lùi)
#   hyx check              kiểm tra sức khoẻ node (mã thoát 0 ổn · 1 có cảnh báo · 2 có lỗi)
case "${1:-}" in
    update|-u) case "${2:-}" in --force) do_update force ;; --auto) do_update auto ;; *) do_update yes ;; esac; exit $? ;;
    autoupdate) case "${2:-status}" in on) autoupdate_on ;; off) autoupdate_off ;; *) autoupdate_status ;; esac; exit $? ;;
    check|health) health_check; exit $? ;;
    help|-h|--help) echo "hyx            mở menu"; echo "hyx update     nâng V2bX (tự lùi nếu hỏng)  ·  hyx update --force"; echo "hyx autoupdate on|off|status   tự cập nhật 03:30 VN"; echo "hyx check      kiểm tra sức khoẻ node"; exit 0 ;;
esac
show_menu
