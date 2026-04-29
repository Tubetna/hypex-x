#!/bin/bash

# ==========================================
# Script cài đặt V2bX Tự động (Multi-Node + Auto SSL)
# ==========================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo -e "${red}Lỗi: Script này phải được chạy dưới quyền root!${plain}" 
   exit 1
fi

echo -e "${green}=========================================="
echo -e " Cài đặt V2bX - Multi-Node & Auto SSL IP"
echo -e "==========================================${plain}"

# 1. Thu thập thông tin từ người dùng
read -p "Nhập link Panel (VD: https://panel.com): " API_HOST
read -p "Nhập API Key của Panel: " API_KEY

echo ""
read -p "Bạn có muốn tự động tạo và cài SSL (Self-signed) cho IP máy chủ không? (y/n): " AUTO_SSL
if [[ "$AUTO_SSL" == "y" || "$AUTO_SSL" == "Y" ]]; then
    HAS_SSL=true
    echo -e "${green}==> Sẽ tự động cấu hình SSL cho các Node.${plain}"
else
    HAS_SSL=false
fi

echo ""
read -p "Bạn muốn chạy bao nhiêu Node trên máy chủ này? (VD: 2): " NUM_NODES
if ! [[ "$NUM_NODES" =~ ^[1-9][0-9]*$ ]]; then
    echo -e "${red}Số lượng không hợp lệ, mặc định sẽ tạo 1 Node.${plain}"
    NUM_NODES=1
fi

declare -a NODE_CONFIGS

for (( i=1; i<=NUM_NODES; i++ ))
do
    echo -e "\n${yellow}--- Cấu hình cho Node thứ $i ---${plain}"
    read -p "Nhập Node ID cho Node thứ $i: " NODE_ID

    echo "Chọn loại Giao thức (Node Type):"
    echo "1. V2ray"
    echo "2. Trojan"
    echo "3. Shadowsocks"
    echo "4. Hysteria2"
    read -p "Nhập số (1-4): " TYPE_CHOICE

    case $TYPE_CHOICE in
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
        \"NodeID\": ${NODE_ID},
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
    if ! command -v openssl &> /dev/null; then
        apt-get update && apt-get install -y openssl || yum install -y openssl
    fi
    SERVER_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/V2bX/private.key \
        -out /etc/V2bX/cert.crt \
        -subj "/C=VN/ST=Server/L=Server/O=V2bX/OU=Node/CN=${SERVER_IP}" 2>/dev/null
    echo -e "${green}Đã tạo SSL tại /etc/V2bX/cert.crt${plain}"
fi

# 3. Tải file thực thi (Binary)
BINARY_URL="https://github.com/Tubetna/v2bx/releases/latest/download/V2bX"

echo -e "${yellow}Đang chuẩn bị file V2bX...${plain}"
# Tự động tải từ Github Release của anh
wget -N --no-check-certificate -O /usr/bin/V2bX-bin/V2bX $BINARY_URL

# Nếu tải lỗi, thử tìm file V2bX trong thư mục /root
if [ ! -s "/usr/bin/V2bX-bin/V2bX" ]; then
    if [ -f "/root/V2bX" ]; then
        echo -e "${yellow}Tải qua mạng thất bại, dùng file /root/V2bX...${plain}"
        mv /root/V2bX /usr/bin/V2bX-bin/V2bX
    else
        echo -e "${red}Lỗi: Không thể tải V2bX từ Github và cũng không tìm thấy file ở /root/V2bX!${plain}"
        echo -e "${red}Vui lòng tải file V2bX (Linux) lên phần Releases của repo Tubetna/v2bx!${plain}"
        exit 1
    fi
fi

chmod +x /usr/bin/V2bX-bin/V2bX

# 4. Tạo file cấu hình config.json
echo -e "${yellow}Đang tạo file cấu hình config.json...${plain}"
cat > /etc/V2bX/config.json << EOF
{
  "LogConfig": {
    "Level": "info",
    "Output": ""
  },
  "Nodes": [
${NODES_JSON_ARRAY}
  ]
}
EOF

# 5. Cài đặt Systemd Service
echo -e "${yellow}Đang cấu hình Systemd...${plain}"
cat > /etc/systemd/system/V2bX.service << EOF
[Unit]
Description=V2bX Service
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/V2bX-bin/V2bX server -c /etc/V2bX/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

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
    if journalctl -u V2bX -n 50 | grep -qi "Nodes started"; then
        echo -e "Kết nối Panel: ${green}Thành công! Đã tải và thiết lập cấu hình từ Panel.${plain}"
    else
        echo -e "Kết nối Panel: ${yellow}Đang chờ... (Chưa thấy log báo thành công, hãy gõ 'journalctl -u V2bX -f' để theo dõi)${plain}"
    fi
else
    echo -e "Trạng thái: ${red}Thất bại (Failed/Inactive)${plain}"
    echo -e "Log lỗi gần nhất:"
    journalctl -u V2bX -n 10 --no-pager
fi
echo -e "==========================================${plain}"
