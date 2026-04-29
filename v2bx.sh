#!/bin/bash

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
BINARY="/usr/bin/V2bX-bin/V2bX"
CONFIG="/etc/V2bX/config.json"
INSTALL_SCRIPT="https://raw.githubusercontent.com/Tubetna/v2bx/main/install.sh"

# ── Kiểm tra quyền root ──────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}Lỗi: Cần chạy bằng quyền root!${plain}"
    exit 1
fi

# ── Lấy trạng thái dịch vụ ──────────────
get_status() {
    if systemctl is-active --quiet $SERVICE 2>/dev/null; then
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
        $BINARY version 2>/dev/null | head -1 || echo "Không xác định"
    else
        echo "Chưa cài đặt"
    fi
}

# ── Header đẹp ───────────────────────────
show_header() {
    clear
    echo -e "${cyan}╔══════════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║${white}${bold}         V2bX Manager - Quản lý V2bX             ${plain}${cyan}║${plain}"
    echo -e "${cyan}║${plain}         https://github.com/Tubetna/v2bx          ${cyan}║${plain}"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain}  Trạng thái : $(get_status)"
    echo -e "${cyan}║${plain}  Phiên bản  : ${yellow}$(get_version)${plain}"
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
    echo -e "${cyan}║${plain}  ${purple}12.${plain} Mở tất cả cổng mạng (UFW)"
    echo -e "${cyan}║${plain}  ${purple}13.${plain} Chặn Speedtest"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain}  ${white}${bold}🔧 Cấu hình${plain}"
    echo -e "${cyan}║${plain}  ${yellow}14.${plain} Xem file cấu hình config.json"
    echo -e "${cyan}║${plain}  ${yellow}15.${plain} Tạo cặp khóa X25519 (VLESS Reality)"
    echo -e "${cyan}║${plain}  ${yellow}16.${plain} Tạo chứng chỉ SSL tự ký"
    echo -e "${cyan}╠══════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain}  ${red}0.${plain}  Thoát"
    echo -e "${cyan}╚══════════════════════════════════════════════════╝${plain}"
    echo ""
    read -p "  Vui lòng nhập tùy chọn [0-16]: " choice
    handle_choice "$choice"
}

# ── Xử lý lựa chọn ───────────────────────
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
    0)  echo -e "${green}Tạm biệt!${plain}"; exit 0 ;;
    *)  echo -e "${red}Lựa chọn không hợp lệ!${plain}"; sleep 1; show_menu ;;
    esac
}

# ── Các hàm xử lý ───────────────────────

install_v2bx() {
    echo -e "${yellow}Đang tải script cài đặt...${plain}"
    bash <(curl -Ls "$INSTALL_SCRIPT")
    press_any_key
}

update_v2bx() {
    echo -e "${yellow}Đang cập nhật V2bX...${plain}"
    BINARY_URL="https://raw.githubusercontent.com/Tubetna/v2bx/main/V2bX-linux-64.zip"
    wget --no-check-certificate -O /root/V2bX-linux.zip "$BINARY_URL"
    if [ -s "/root/V2bX-linux.zip" ]; then
        systemctl stop $SERVICE 2>/dev/null
        unzip -o /root/V2bX-linux.zip -d /usr/bin/V2bX-bin/ > /dev/null
        chmod +x $BINARY
        rm -f /root/V2bX-linux.zip
        systemctl start $SERVICE
        echo -e "${green}Cập nhật thành công!${plain}"
    else
        echo -e "${red}Tải file thất bại!${plain}"
    fi
    press_any_key
}

uninstall_v2bx() {
    read -p "$(echo -e "${red}Bạn có chắc muốn gỡ cài đặt V2bX không? [y/n]: ${plain}")" confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        systemctl stop $SERVICE 2>/dev/null
        systemctl disable $SERVICE 2>/dev/null
        rm -f /etc/systemd/system/$SERVICE.service
        rm -rf /usr/bin/V2bX-bin
        rm -rf /etc/V2bX
        systemctl daemon-reload
        echo -e "${green}Đã gỡ cài đặt V2bX thành công!${plain}"
    else
        echo -e "${yellow}Đã hủy.${plain}"
    fi
    press_any_key
}

start_v2bx() {
    systemctl start $SERVICE
    echo -e "${green}Đã khởi động V2bX!${plain}"
    press_any_key
}

stop_v2bx() {
    systemctl stop $SERVICE
    echo -e "${yellow}Đã dừng V2bX!${plain}"
    press_any_key
}

restart_v2bx() {
    systemctl restart $SERVICE
    echo -e "${green}Đã khởi động lại V2bX!${plain}"
    press_any_key
}

status_v2bx() {
    systemctl status $SERVICE --no-pager
    press_any_key
}

log_v2bx() {
    echo -e "${yellow}Đang xem log... (nhấn Ctrl+C để thoát)${plain}"
    journalctl -u $SERVICE -f
    show_menu
}

enable_autostart() {
    systemctl enable $SERVICE
    echo -e "${green}Đã bật tự khởi động cùng hệ thống!${plain}"
    press_any_key
}

disable_autostart() {
    systemctl disable $SERVICE
    echo -e "${yellow}Đã tắt tự khởi động cùng hệ thống!${plain}"
    press_any_key
}

install_bbr() {
    echo -e "${yellow}Đang bật BBR...${plain}"
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo -e "${green}BBR đã được kích hoạt thành công!${plain}"
    else
        echo -e "${red}Kích hoạt BBR thất bại, hệ thống có thể chưa hỗ trợ.${plain}"
    fi
    press_any_key
}

open_ports() {
    echo -e "${yellow}Đang mở tất cả cổng mạng...${plain}"
    if command -v ufw &>/dev/null; then
        ufw disable
        echo -e "${green}Đã tắt UFW firewall (mở tất cả cổng)!${plain}"
    elif command -v iptables &>/dev/null; then
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -F
        echo -e "${green}Đã xóa toàn bộ quy tắc iptables!${plain}"
    fi
    press_any_key
}

block_speedtest() {
    echo -e "${yellow}Đang chặn Speedtest...${plain}"
    iptables -I OUTPUT -m string --string "speedtest" --algo bm -j DROP 2>/dev/null
    iptables -I OUTPUT -m string --string "fast.com" --algo bm -j DROP 2>/dev/null
    iptables -I OUTPUT -m string --string "speed.cloudflare.com" --algo bm -j DROP 2>/dev/null
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

gen_ssl() {
    SERVER_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
    echo -e "${yellow}Đang tạo chứng chỉ SSL tự ký cho IP: ${SERVER_IP}${plain}"
    mkdir -p /etc/V2bX
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/V2bX/private.key \
        -out /etc/V2bX/cert.crt \
        -subj "/C=VN/ST=Server/L=Server/O=V2bX/OU=Node/CN=${SERVER_IP}" 2>/dev/null
    echo -e "${green}Đã tạo chứng chỉ SSL tại:${plain}"
    echo -e "  Cert : ${white}/etc/V2bX/cert.crt${plain}"
    echo -e "  Key  : ${white}/etc/V2bX/private.key${plain}"
    press_any_key
}

press_any_key() {
    echo ""
    read -p "  Nhấn Enter để quay lại menu..." dummy
    show_menu
}

# ── Khởi chạy ────────────────────────────
show_menu
