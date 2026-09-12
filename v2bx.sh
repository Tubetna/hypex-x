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

# Bảng màu gradient 256-color: xanh ngọc → xanh dương → tím → hồng.
# MobaXterm/xterm/Windows Terminal đều hiểu; terminal 16 màu thì hạ về cyan.
GRAD=(51 45 39 33 27 63 99 135 171 207)
if [ "$(tput colors 2>/dev/null || echo 8)" -lt 256 ]; then GRAD=(36 36 36 34 34 35 35 35 35 35); fi
g()  { printf '\033[38;5;%sm' "${GRAD[$(( $1 % ${#GRAD[@]} ))]}"; }   # g <i> → mã màu thứ i
# Tô một chuỗi theo gradient, mỗi ký tự một màu (offset $2 để làm hiệu ứng chạy)
gtext() {
    local str="$1" off="${2:-0}" i ch
    for (( i=0; i<${#str}; i++ )); do
        ch="${str:$i:1}"; printf '%s%s' "$(g $((i+off)))" "$ch"
    done; printf '%s' "$plain"
}
# Hiệu ứng: chỉ khi có tty và không đặt HYX_NOANIM (SSH script/cron thì tắt)
anim_ok() { [ -t 1 ] && [ -z "$HYX_NOANIM" ]; }
# Spinner: spin "việc đang làm" lệnh... — chạy lệnh nền, quay cho tới khi xong
SPIN_OUT=/tmp/.hyx_spin.log
spin() {
    local msg="$1"; shift
    if ! anim_ok; then "$@" >"$SPIN_OUT" 2>&1; return $?; fi
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 rc
    "$@" >"$SPIN_OUT" 2>&1 & local pid=$!
    while kill -0 $pid 2>/dev/null; do
        printf '\r  %s%s%s %s' "$(g $i)" "${frames:$((i%10)):1}" "$plain" "$msg"
        i=$((i+1)); sleep 0.08
    done
    wait $pid; rc=$?
    printf '\r\033[K'
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

# ── Header ───────────────────────────────
HYX_FIRST=1
show_header() {
    clear
    detect_arch
    local title='HYX'
    local sub=' · node V2bX'
    if [ "$HYX_FIRST" = 1 ] && anim_ok; then
        # Quét gradient qua chữ 8 khung hình rồi dừng — chỉ lần mở đầu
        local f
        for f in 7 6 5 4 3 2 1 0; do
            printf '\r  %s%s%s%s' "$bold" "$(gtext "$title" $f)" "$dim" "$sub"
            sleep 0.05
        done; echo -e "$plain"
    else
        echo -e "  ${bold}$(gtext "$title")${dim}${sub}${plain}"
    fi
    HYX_FIRST=0
    echo -e "  $(g 0)────────────────────────────────────────────────────${plain}"
    echo -e "  $(get_status)  ${dim}$(get_version | sed 's/ (.*//') · ${ARCH_SUFFIX:-?}${plain}"
    echo -e "  ${dim}Node${plain}  ${yellow}$(get_nodes)${plain}"
    echo -e "  ${dim}Cert${plain}  $(get_cert_info)"
    echo -e "  ${dim}MSS ${plain}  $(get_mss_status)"
    echo -e "  $(g 9)────────────────────────────────────────────────────${plain}"
}

# Một mục menu: số tô gradient, chữ ngắn. Đệm bằng tay theo số ký tự — printf %-Ns
# đệm theo byte nên chữ có dấu bị hụt, cột lệch.
m() {
    local w=${4:-16} pad
    pad=$(( w - ${#3} )); [ $pad -lt 1 ] && pad=1
    printf '%s%s%2s%s %s%*s' "$bold" "$(g $1)" "$2" "$plain" "$3" "$pad" ''
}

# ── Menu chính ───────────────────────────
show_menu() {
    show_header
    echo -e "  $(m 0 1 'Cài')$(m 1 2 'Cập nhật')$(m 2 3 'Gỡ')"
    echo -e "  $(m 3 4 'Bật')$(m 4 5 'Dừng')$(m 5 6 'Khởi động lại')"
    echo -e "  $(m 6 7 'Trạng thái')$(m 7 8 'Log')$(m 8 14 'Config')"
    echo ""
    echo -e "  $(m 1 9 'Tự chạy: bật')$(m 2 10 'Tự chạy: tắt')$(m 3 11 'BBR')"
    echo -e "  $(m 4 12 'Mở cổng')$(m 5 13 'Chặn speedtest')$(m 6 20 'Ép MSS 1400')"
    echo ""
    echo -e "  $(m 7 19 'Cert LE')$(m 8 16 'Cert tự ký')$(m 9 15 'Khóa X25519')"
    echo -e "  $(m 0 17 'Geo')$(m 1 18 'Giới hạn TB')$(m 2 0 'Thoát')"
    echo ""
    read -p "  ❯ " choice
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
    0)  echo -e "${green}Tạm biệt!${plain}"; exit 0 ;;
    *)  echo -e "  ${red}Không có mục này.${plain}"; sleep 0.7; show_menu ;;
    esac
}

# ── Các hàm xử lý ───────────────────────

install_v2bx() {
    bash <(curl -fLs "$INSTALL_SCRIPT")
    press_any_key
}

update_v2bx() {
    detect_arch
    if [ -z "$ARCH_SUFFIX" ]; then
        echo -e "${red}Không nhận ra kiến trúc CPU ($(uname -m)) — không cập nhật được.${plain}"
        press_any_key; return
    fi

    local tmp; tmp=$(mktemp -d /tmp/v2bx-up.XXXXXX) || { echo -e "${red}Lỗi thư mục tạm.${plain}"; press_any_key; return; }

    if ! spin "Tải V2bX ${ARCH_SUFFIX}..." curl -fL --retry 3 --connect-timeout 15 -s \
            -o "${tmp}/v2bx.zip" "${BASE_URL}/V2bX-${ARCH_SUFFIX}.zip"; then
        echo -e "${red}Tải file thất bại!${plain}"; rm -rf "$tmp"; press_any_key; return
    fi

    if ! unzip -oq "${tmp}/v2bx.zip" -d "${tmp}/x"; then
        echo -e "${red}Giải nén thất bại (file hỏng?)${plain}"; rm -rf "$tmp"; press_any_key; return
    fi

    local src; src=$(find "${tmp}/x" -maxdepth 2 -type f -name 'V2bX' | head -1)
    if [ -z "$src" ]; then
        echo -e "${red}Không tìm thấy binary trong gói tải về.${plain}"; rm -rf "$tmp"; press_any_key; return
    fi

    # Thử binary mới TRƯỚC khi dừng dịch vụ — tránh tải nhầm kiến trúc rồi chết node
    chmod +x "$src"
    if ! "$src" version &>/dev/null; then
        echo -e "${red}Binary mới không chạy được trên máy này — huỷ cập nhật, Node vẫn chạy bình thường.${plain}"
        rm -rf "$tmp"; press_any_key; return
    fi

    mkdir -p "$BIN_DIR"
    [ -f "$BINARY" ] && cp -f "$BINARY" "${BINARY}.bak"
    svc stop &>/dev/null
    install -m 755 "$src" "$BINARY"

    # Cập nhật luôn geo nếu gói có kèm
    local d; d=$(dirname "$src")
    for g in geoip.dat geosite.dat geoip.db geosite.db; do
        [ -f "${d}/${g}" ] && install -m 644 "${d}/${g}" "${CONF_DIR}/${g}"
    done

    svc start
    spin "Khởi động lại V2bX..." sleep 3
    if svc_active; then
        rm -f "${BINARY}.bak"
        echo -e "  ${green}✓ Cập nhật xong · $(get_version | sed 's/ (.*//')${plain}"
        # Kéo luôn script menu mới để có các mục vừa thêm (mss, log...)
        if curl -fsL --connect-timeout 15 -o /usr/local/bin/hyx.new "${SCRIPT_URL}/v2bx.sh" \
           && bash -n /usr/local/bin/hyx.new 2>/dev/null; then
            mv -f /usr/local/bin/hyx.new /usr/local/bin/hyx
            chmod +x /usr/local/bin/hyx
            ln -sf /usr/local/bin/hyx /usr/local/bin/v2bx
            ln -sf /usr/local/bin/hyx /usr/local/bin/hypex-x
            echo -e "${green}Đã cập nhật lệnh hyx.${plain}"
        else
            rm -f /usr/local/bin/hyx.new
        fi
    else
        if [ -f "${BINARY}.bak" ]; then
            mv -f "${BINARY}.bak" "$BINARY"
            svc start
            echo -e "${red}Bản mới không khởi động được — đã tự lùi về bản cũ.${plain}"
        else
            echo -e "${red}Cập nhật xong nhưng dịch vụ không chạy. Xem log: menu 8 → 5.${plain}"
        fi
    fi
    rm -rf "$tmp"
    press_any_key
}

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
    read -p "  ${dim}Enter để về menu${plain} " dummy
    show_menu
}

# ── Khởi chạy ────────────────────────────
show_menu
