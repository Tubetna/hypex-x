#!/bin/bash

# ==========================================
# Script cài đặt V2bX Tự động (Multi-Node + Auto SSL)
# Hỗ trợ: Ubuntu/Debian, CentOS/RHEL, EulerOS/openEuler (Huawei)
# ==========================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo -e "${red}Lỗi: Script này phải được chạy dưới quyền root!${plain}"
   exit 1
fi

# ==========================================
# Phát hiện hệ điều hành và kiến trúc
# ==========================================
detect_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_ID="${ID}"
        OS_ID_LIKE="${ID_LIKE}"
        OS_VERSION="${VERSION_ID}"
        OS_NAME="${NAME}"
    elif [ -f /etc/system-release ]; then
        OS_NAME=$(cat /etc/system-release)
        OS_ID="centos"
    else
        OS_ID="unknown"
    fi

    # Phân loại package manager
    case "${OS_ID}" in
        ubuntu|debian|linuxmint|raspbian)
            PKG_MANAGER="apt"
            PKG_UPDATE="apt-get update -y"
            PKG_INSTALL="apt-get install -y"
            ;;
        centos|rhel|rocky|almalinux|fedora|kylin|opencloudos)
            PKG_MANAGER="dnf"
            PKG_UPDATE="dnf makecache -y"
            PKG_INSTALL="dnf install -y"
            ;;
        euler|euleros|openeuler)
            # EulerOS / openEuler (Huawei)
            PKG_MANAGER="dnf"
            PKG_UPDATE="dnf makecache -y"
            PKG_INSTALL="dnf install -y"
            IS_EULER=true
            ;;
        *)
            # Fallback: kiểm tra ID_LIKE
            if echo "${OS_ID_LIKE}" | grep -qiE "rhel|centos|fedora"; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf makecache -y"
                PKG_INSTALL="dnf install -y"
                # Phát hiện EulerOS qua ID_LIKE hoặc tên
                if echo "${OS_NAME}" | grep -qiE "euler|huawei"; then
                    IS_EULER=true
                fi
            elif echo "${OS_ID_LIKE}" | grep -qi "debian"; then
                PKG_MANAGER="apt"
                PKG_UPDATE="apt-get update -y"
                PKG_INSTALL="apt-get install -y"
            else
                # Fallback cuối: kiểm tra lệnh có sẵn
                if command -v dnf &>/dev/null; then
                    PKG_MANAGER="dnf"
                    PKG_UPDATE="dnf makecache -y"
                    PKG_INSTALL="dnf install -y"
                elif command -v yum &>/dev/null; then
                    PKG_MANAGER="yum"
                    PKG_UPDATE="yum makecache -y"
                    PKG_INSTALL="yum install -y"
                else
                    PKG_MANAGER="apt"
                    PKG_UPDATE="apt-get update -y"
                    PKG_INSTALL="apt-get install -y"
                fi
            fi
            ;;
    esac
}

detect_arch() {
    MACHINE_ARCH=$(uname -m)
    case "${MACHINE_ARCH}" in
        x86_64|amd64)
            ARCH="64"
            GOARCH_NAME="linux-amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            GOARCH_NAME="linux-arm64"
            ;;
        armv7l|armv7)
            ARCH="arm"
            GOARCH_NAME="linux-arm32-v7"
            ;;
        *)
            echo -e "${yellow}Cảnh báo: Kiến trúc ${MACHINE_ARCH} chưa được kiểm tra, thử dùng binary amd64.${plain}"
            ARCH="64"
            GOARCH_NAME="linux-amd64"
            ;;
    esac
}

detect_os
detect_arch

echo -e "${blue}===========================================${plain}"
echo -e "${green} Cài đặt V2bX - Multi-Node & Auto SSL IP${plain}"
echo -e "${blue}===========================================${plain}"
echo -e "${yellow}  Hệ điều hành : ${OS_NAME:-Unknown}${plain}"
echo -e "${yellow}  Kiến trúc    : ${MACHINE_ARCH} (${GOARCH_NAME})${plain}"
echo -e "${yellow}  Package Mgr  : ${PKG_MANAGER}${plain}"
if [ "${IS_EULER}" = "true" ]; then
    echo -e "${green}  ✓ Phát hiện EulerOS/openEuler (Huawei) - Đã bật chế độ tương thích${plain}"
fi
echo -e "${blue}===========================================${plain}"
echo ""


# 1. Thu thập thông tin từ người dùng (Hỗ trợ cấu hình nhanh qua lệnh export)
if [ -z "$API_HOST" ]; then
    read -p "Nhập link Panel (VD: https://panel.com): " API_HOST
fi

if [ -z "$API_KEY" ]; then
    read -p "Nhập API Key của Panel: " API_KEY
fi

echo ""
if [ -z "$AUTO_SSL" ]; then
    read -p "Bạn có muốn tự động tạo và cài SSL (Self-signed) cho IP máy chủ không? (y/n): " AUTO_SSL
fi

if [[ "$AUTO_SSL" == "y" || "$AUTO_SSL" == "Y" ]]; then
    HAS_SSL=true
    echo -e "${green}==> Sẽ tự động cấu hình SSL cho các Node.${plain}"
else
    HAS_SSL=false
fi

echo ""
if [ -z "$NUM_NODES" ]; then
    read -p "Bạn muốn chạy bao nhiêu Node trên máy chủ này? (VD: 2): " NUM_NODES
fi

if ! [[ "$NUM_NODES" =~ ^[1-9][0-9]*$ ]]; then
    echo -e "${red}Số lượng không hợp lệ, mặc định sẽ tạo 1 Node.${plain}"
    NUM_NODES=1
fi

declare -a NODE_CONFIGS

for (( i=1; i<=NUM_NODES; i++ ))
do
    echo -e "\n${yellow}--- Cấu hình cho Node thứ $i ---${plain}"
    
    read -p "Nhập Node ID cho Node thứ $i: " CURRENT_NODE_ID

    echo "Chọn loại Giao thức (Node Type):"
    echo "1. V2ray"
    echo "2. Trojan"
    echo "3. Shadowsocks"
    echo "4. Hysteria2"
    read -p "Nhập số (1-4): " CURRENT_TYPE_CHOICE

    case $CURRENT_TYPE_CHOICE in
        1) NODE_TYPE="V2ray"; CORE="xray" ;;
        2) NODE_TYPE="Trojan"; CORE="xray" ;;
        3) NODE_TYPE="Shadowsocks"; CORE="sing" ;;
        4) NODE_TYPE="Hysteria2"; CORE="hysteria2" ;;
        *) echo -e "${red}Lựa chọn không hợp lệ. Mặc định dùng V2ray (Core: xray).${plain}"; NODE_TYPE="V2ray"; CORE="xray" ;;
    esac

    echo -e "${green}==> Đã tự động gán Core [ ${CORE} ] cho giao thức [ ${NODE_TYPE} ]${plain}"

    # Cấu hình SSL (nếu có)
    if [ "$HAS_SSL" = true ]; then
        CERT_JSON=",
        \"CertConfig\": {
          \"CertMode\": \"file\",
          \"CertFile\": \"/etc/V2bX/cert.crt\",
          \"KeyFile\": \"/etc/V2bX/private.key\"
        }"
    else
        CERT_JSON=""
    fi

    NODE_JSON="    {
      \"ApiConfig\": {
        \"ApiHost\": \"${API_HOST}\",
        \"ApiKey\": \"${API_KEY}\",
        \"NodeID\": ${CURRENT_NODE_ID},
        \"NodeType\": \"${NODE_TYPE}\"
      },
      \"Options\": {
        \"Core\": \"${CORE}\",
        \"ListenIP\": \"0.0.0.0\",
        \"SendIP\": \"0.0.0.0\"${CERT_JSON}
      }
    }"

    NODE_CONFIGS+=("$NODE_JSON")
done

NODES_JSON_ARRAY=""
for (( i=0; i<${#NODE_CONFIGS[@]}; i++ )); do
    if [ $i -gt 0 ]; then
        NODES_JSON_ARRAY+=","
    fi
    NODES_JSON_ARRAY+="${NODE_CONFIGS[$i]}"
done

# 2. Tạo thư mục làm việc và chứng chỉ SSL
echo -e "\n${yellow}Đang tạo thư mục và môi trường...${plain}"
mkdir -p /etc/V2bX
mkdir -p /usr/bin/V2bX-bin

if [ "$HAS_SSL" = true ]; then
    echo -e "${yellow}Đang tạo chứng chỉ SSL (Self-signed) cho IP...${plain}"
    # Cài openssl nếu chưa có
    if ! command -v openssl &>/dev/null; then
        eval "${PKG_UPDATE}" && eval "${PKG_INSTALL} openssl"
    fi
    # Cài curl nếu chưa có
    if ! command -v curl &>/dev/null; then
        eval "${PKG_INSTALL} curl"
    fi
    SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/V2bX/private.key \
        -out /etc/V2bX/cert.crt \
        -subj "/C=VN/ST=Server/L=Server/O=V2bX/OU=Node/CN=${SERVER_IP}" 2>/dev/null
    echo -e "${green}Đã tạo SSL tại /etc/V2bX/cert.crt${plain}"
fi

# 3. Tải file thực thi (Binary) từ Github của anh
echo -e "${yellow}Đang tải V2bX tùy chỉnh từ Github của anh...${plain}"

# Chọn URL binary theo kiến trúc CPU
case "${ARCH}" in
    arm64)
        BINARY_URL="https://raw.githubusercontent.com/Tubetna/v2bx/main/V2bX-linux-arm64.zip"
        ;;
    arm)
        BINARY_URL="https://raw.githubusercontent.com/Tubetna/v2bx/main/V2bX-linux-arm32-v7.zip"
        ;;
    *)
        BINARY_URL="https://raw.githubusercontent.com/Tubetna/v2bx/main/V2bX-linux-64.zip"
        ;;
esac

echo -e "${yellow}  Binary URL: ${BINARY_URL}${plain}"

# Đảm bảo wget có sẵn
if ! command -v wget &>/dev/null; then
    eval "${PKG_INSTALL} wget"
fi

wget --no-check-certificate -O /root/V2bX-linux.zip "${BINARY_URL}"

if [ -s "/root/V2bX-linux.zip" ]; then
    echo -e "${yellow}Đang giải nén...${plain}"
    if ! command -v unzip &>/dev/null; then
        eval "${PKG_INSTALL} unzip"
    fi
    unzip -o /root/V2bX-linux.zip -d /usr/bin/V2bX-bin/ > /dev/null
    rm -f /root/V2bX-linux.zip
else
    echo -e "${red}Lỗi: Không tải được file V2bX từ Github!${plain}"
    rm -f /root/V2bX-linux.zip
    exit 1
fi

chmod +x /usr/bin/V2bX-bin/V2bX

# Xử lý SELinux trên EulerOS / openEuler / RHEL-based
if [ "${IS_EULER}" = "true" ] || command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
    if [ "${SELINUX_STATUS}" != "Disabled" ] && [ "${SELINUX_STATUS}" != "" ]; then
        echo -e "${yellow}Phát hiện SELinux (${SELINUX_STATUS}), đang gán nhãn bảo mật cho binary...${plain}"
        if command -v chcon &>/dev/null; then
            chcon -t bin_t /usr/bin/V2bX-bin/V2bX 2>/dev/null && \
                echo -e "${green}✓ SELinux context đã được gán.${plain}" || \
                echo -e "${yellow}⚠ Không thể gán SELinux context, bỏ qua.${plain}"
        fi
    fi
fi

# 4. Tạo file cấu hình config.json
echo -e "${yellow}Đang tạo file cấu hình config.json...${plain}"
cat > /etc/V2bX/config.json << EOF
{
  "Log": {
    "Level": "info",
    "Output": ""
  },
  "Cores": [
    {
      "Type": "xray",
      "Log": {
        "Level": "info"
      }
    },
    {
      "Type": "sing",
      "Log": {
        "Level": "info"
      }
    },
    {
      "Type": "hysteria2",
      "Log": {
        "Level": "info"
      }
    }
  ],
  "Nodes": [
${NODES_JSON_ARRAY}
  ]
}
EOF

# 5. Cài đặt Systemd Service
echo -e "${yellow}Đang cấu hình Systemd...${plain}"
cat > /etc/systemd/system/V2bX.service << 'SVCEOF'
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/V2bX
ExecStart=/usr/bin/V2bX-bin/V2bX server -c /etc/V2bX/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
LimitNPROC=65535
# Tương thích EulerOS / openEuler (tắt các tính năng sandbox không hỗ trợ)
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
SVCEOF

# 6. Khởi động và kiểm tra
systemctl daemon-reload
systemctl enable V2bX
systemctl restart V2bX

echo -e "\n${yellow}Đang kiểm tra tiến trình hoạt động (vui lòng đợi 3 giây)...${plain}"
sleep 3

echo -e "${green}=========================================="
if systemctl is-active --quiet V2bX; then
    echo -e "Trạng thái: ${green}Đang chạy (Active)${plain}"
    
    # Check log để xem có kết nối panel thành công không
    if journalctl -u V2bX -n 50 | grep -qi "Các Node đã khởi động xong"; then
        echo -e "Kết nối Panel: ${green}Thành công! Đã tải và thiết lập cấu hình từ Panel.${plain}"
    else
        echo -e "Kết nối Panel: ${yellow}Đang chờ... (hãy gõ 'journalctl -u V2bX -f' để theo dõi)${plain}"
    fi
else
    echo -e "Trạng thái: ${red}Thất bại (Failed/Inactive)${plain}"
    echo -e "Log lỗi gần nhất:"
    journalctl -u V2bX -n 10 --no-pager
fi
echo -e "==========================================${plain}"

# 7. Cài lệnh quản lý 'v2bx'
echo -e "\n${yellow}Đang cài lệnh quản lý 'v2bx'...${plain}"
wget --no-check-certificate -O /usr/local/bin/v2bx \
    "https://raw.githubusercontent.com/Tubetna/v2bx/main/v2bx.sh"
chmod +x /usr/local/bin/v2bx
echo -e "${green}✓ Đã cài xong! Gõ lệnh 'v2bx' bất cứ lúc nào để quản lý.${plain}"
