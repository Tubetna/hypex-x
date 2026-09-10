#!/usr/bin/env bash

# ==========================================
#   V2bX Manager - Quản lý V2bX
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
plain='\033[0m'

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
        echo -e "${green}● Đang chạy (Active)${plain}"
    elif [ -f "$BINARY" ]; then
        echo -e "${red}● Đã dừng (Inactive)${plain}"
    else
        echo -e "${yellow}● Chưa cài đặt${plain}"
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

# ── Header ───────────────────────────────
show_header() {
    clear
    detect_arch
    echo -e "${cyan}╔══════════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║${white}${bold}         V2bX Manager - Quản lý V2bX             ${plain}${cyan}║${plain}"
    echo -e "${cyan}║${plain}         https://github.com/Tubetna/hypex-x          ${cyan}║${plain}"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain}  Trạng thái : $(get_status)"
    echo -e "${cyan}║${plain}  Phiên bản  : ${yellow}$(get_version)${plain}"
    echo -e "${cyan}║${plain}  Kiến trúc  : ${yellow}${ARCH_SUFFIX:-không nhận ra}${plain}"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
}

# ── Menu chính ───────────────────────────
show_menu() {
    show_header
    echo -e "${cyan}║${plain}  ${white}${bold}⚙  Cài đặt & Cập nhật${plain}"
    echo -e "${cyan}║${plain}  ${green}1.${plain}  Cài đặt V2bX"
    echo -e "${cyan}║${plain}  ${green}2.${plain}  Cập nhật V2bX"
    echo -e "${cyan}║${plain}  ${green}3.${plain}  Gỡ cài đặt V2bX"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain}  ${white}${bold}▶  Điều khiển dịch vụ${plain}"
    echo -e "${cyan}║${plain}  ${blue}4.${plain}  Khởi động V2bX"
    echo -e "${cyan}║${plain}  ${blue}5.${plain}  Dừng V2bX"
    echo -e "${cyan}║${plain}  ${blue}6.${plain}  Khởi động lại V2bX"
    echo -e "${cyan}║${plain}  ${blue}7.${plain}  Kiểm tra trạng thái"
    echo -e "${cyan}║${plain}  ${blue}8.${plain}  Xem nhật ký (log) realtime"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain}  ${white}${bold}⚡ Hệ thống & Tối ưu${plain}"
    echo -e "${cyan}║${plain}  ${purple}9.${plain}  Bật tự khởi động cùng hệ thống"
    echo -e "${cyan}║${plain}  ${purple}10.${plain} Tắt tự khởi động cùng hệ thống"
    echo -e "${cyan}║${plain}  ${purple}11.${plain} Cài BBR (tăng tốc mạng)"
    echo -e "${cyan}║${plain}  ${purple}12.${plain} Mở cổng cho Node (tường lửa)"
    echo -e "${cyan}║${plain}  ${purple}13.${plain} Chặn Speedtest"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain}  ${white}${bold}🔧 Cấu hình${plain}"
    echo -e "${cyan}║${plain}  ${yellow}14.${plain} Xem file cấu hình config.json"
    echo -e "${cyan}║${plain}  ${yellow}15.${plain} Tạo cặp khóa X25519 (VLESS Reality)"
    echo -e "${cyan}║${plain}  ${yellow}16.${plain} Tạo chứng chỉ SSL tự ký"
    echo -e "${cyan}║${plain}  ${yellow}17.${plain} Cập nhật dữ liệu geo (geoip/geosite)"
    echo -e "${cyan}║${plain}  ${yellow}18.${plain} Kiểm tra giới hạn thiết bị"
    echo -e "${cyan}║${plain}  ${yellow}19.${plain} Cấp chứng chỉ SSL thật (Let's Encrypt)"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain}  ${red}0.${plain}  Thoát"
    echo -e "${cyan}╚══════════════════════════════════════════════════╝${plain}"
    echo ""
    read -p "  Vui lòng nhập tùy chọn [0-19]: " choice
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
    0)  echo -e "${green}Tạm biệt!${plain}"; exit 0 ;;
    *)  echo -e "${red}Lựa chọn không hợp lệ!${plain}"; sleep 1; show_menu ;;
    esac
}

# ── Các hàm xử lý ───────────────────────

install_v2bx() {
    echo -e "${yellow}Đang tải script cài đặt...${plain}"
    bash <(curl -fLs "$INSTALL_SCRIPT")
    press_any_key
}

update_v2bx() {
    detect_arch
    if [ -z "$ARCH_SUFFIX" ]; then
        echo -e "${red}Không nhận ra kiến trúc CPU ($(uname -m)) — không cập nhật được.${plain}"
        press_any_key; return
    fi

    echo -e "${yellow}Đang cập nhật V2bX cho ${ARCH_SUFFIX}...${plain}"
    local tmp; tmp=$(mktemp -d /tmp/v2bx-up.XXXXXX) || { echo -e "${red}Lỗi thư mục tạm.${plain}"; press_any_key; return; }

    if ! curl -fL --retry 3 --connect-timeout 15 --progress-bar \
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
    sleep 3
    if svc_active; then
        rm -f "${BINARY}.bak"
        echo -e "${green}Cập nhật thành công! $(get_version)${plain}"
    else
        if [ -f "${BINARY}.bak" ]; then
            mv -f "${BINARY}.bak" "$BINARY"
            svc start
            echo -e "${red}Bản mới không khởi động được — đã tự lùi về bản cũ.${plain}"
        else
            echo -e "${red}Cập nhật xong nhưng dịch vụ không chạy. Xem log ở mục 8.${plain}"
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
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        systemctl status $SERVICE --no-pager
    else
        rc-service $SERVICE status
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

log_v2bx() {
    echo -e "${yellow}Đang xem log... (nhấn Ctrl+C để thoát)${plain}"
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        journalctl -u $SERVICE -f
    else
        tail -f /var/log/V2bX.log
    fi
    show_menu
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

# Cấp chứng chỉ thật từ Let's Encrypt cho node chạy cổng 443.
#
# Cert tự ký không còn dùng được trong thực tế: xray-core 26.x đã xoá tuỳ chọn
# allowInsecure nên client mới từ chối nạp cấu hình có nó; CloudFront từ chối
# thẳng origin HTTPS không có cert hợp lệ; còn Cloudflare thì không chịu tải
# luồng dài (XHTTP stream-one) qua origin cert tự ký.
gen_le_ssl() {
    local domain cf_token acme=/root/.acme.sh/acme.sh

    read -p "Nhập tên miền trỏ về máy này (VD: node1.domain.com): " domain
    if [ -z "$domain" ]; then
        echo -e "${red}Chưa nhập tên miền.${plain}"; press_any_key; return
    fi

    echo -e "${yellow}Nếu tên miền nằm trên Cloudflare (nhất là khi đang bật proxy),${plain}"
    echo -e "${yellow}dán API Token có quyền Zone:DNS:Edit để xác thực qua DNS.${plain}"
    echo -e "${yellow}Bỏ trống thì xác thực qua cổng 80 — tên miền phải trỏ thẳng về IP máy này.${plain}"
    read -p "Cloudflare API Token (bỏ trống để dùng cổng 80): " cf_token

    command -v curl &>/dev/null || {
        echo -e "${red}Máy chưa có curl.${plain}"; press_any_key; return; }

    if [ ! -f "$acme" ]; then
        echo -e "${yellow}Đang cài acme.sh...${plain}"
        curl -fsS https://get.acme.sh | sh -s email="admin@${domain}" &>/dev/null || {
            echo -e "${red}Cài acme.sh thất bại.${plain}"; press_any_key; return; }
    fi
    "$acme" --set-default-ca --server letsencrypt &>/dev/null

    mkdir -p "$CONF_DIR"
    local issued=false

    if [ -n "$cf_token" ]; then
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
    if ! "$acme" --install-cert -d "$domain" --ecc \
            --fullchain-file "${CONF_DIR}/cert.crt" \
            --key-file "${CONF_DIR}/private.key" \
            --reloadcmd "$reload" &>/dev/null; then
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
    read -p "  Nhấn Enter để quay lại menu..." dummy
    show_menu
}

# ── Khởi chạy ────────────────────────────
show_menu
