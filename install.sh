#!/usr/bin/env bash

# ==========================================
# Script cài đặt V2bX Tự động (Multi-Node + Auto SSL)
# Hỗ trợ đầy đủ: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma/Fedora,
#                EulerOS/openEuler (Huawei), Kylin, OpenCloudOS,
#                openSUSE, Arch, Alpine (OpenRC)
# Kiến trúc    : amd64, 386, arm64, arm32 v5/v6/v7,
#                mips32/mips32le/mips64/mips64le, ppc64/ppc64le, s390x
# ==========================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
plain='\033[0m'

# Cho phép trỏ sang GitHub Releases hoặc mirror riêng khi cần
BASE_URL="${V2BX_BASE_URL:-https://github.com/Tubetna/hypex-x/releases/latest/download}"
SCRIPT_URL="${V2BX_SCRIPT_URL:-https://raw.githubusercontent.com/Tubetna/hypex-x/main}"

CONF_DIR="/etc/V2bX"
BIN_DIR="/usr/bin/V2bX-bin"
BIN="${BIN_DIR}/V2bX"

die() { echo -e "${red}Lỗi: $1${plain}" >&2; exit 1; }

# ==========================================
# Cấp chứng chỉ SSL thật (Let's Encrypt) qua acme.sh
# ==========================================
# Vì sao cần: cert tự ký chỉ dùng được khi Panel bật allowInsecure, mà tuỳ chọn
# này đã bị xoá khỏi xray-core 26.x — client mới từ chối nạp cấu hình có nó.
# Nặng hơn: CloudFront từ chối thẳng origin HTTPS không có cert hợp lệ, còn
# Cloudflare thì không chịu tải luồng dài (XHTTP stream-one) qua origin cert
# tự ký. Node chạy 443 muốn dùng thật thì phải có cert thật.

# Lệnh điều khiển dịch vụ, hợp cho cả systemd lẫn OpenRC
svc_cmd() {
    if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
        echo "systemctl $1 V2bX"
    else
        echo "rc-service V2bX $1"
    fi
}

issue_le_cert() {
    local domain="$1" cf_token="$2"
    [ -z "$domain" ] && { echo -e "${red}Chưa nhập tên miền.${plain}"; return 1; }

    ensure_pkg curl || { echo -e "${red}Không cài được curl.${plain}"; return 1; }
    ensure_pkg socat &>/dev/null

    local acme=/root/.acme.sh/acme.sh
    if [ ! -f "$acme" ]; then
        echo -e "${yellow}Đang cài acme.sh...${plain}"
        curl -fsS https://get.acme.sh | sh -s email="admin@${domain}" &>/dev/null \
            || { echo -e "${red}Cài acme.sh thất bại.${plain}"; return 1; }
    fi
    "$acme" --set-default-ca --server letsencrypt &>/dev/null

    mkdir -p "${CONF_DIR}"
    local issued=false

    if [ -n "$cf_token" ]; then
        # DNS-01: chạy được cả khi tên miền đang bật proxy Cloudflare,
        # và không cần cổng 80 rảnh
        echo -e "${yellow}Đang xin chứng chỉ cho ${domain} (xác thực qua DNS Cloudflare)...${plain}"
        CF_Token="$cf_token" "$acme" --issue --dns dns_cf -d "$domain" \
            --keylength ec-256 && issued=true
    else
        # HTTP-01: cần cổng 80 rảnh nên tạm dừng V2bX nếu nó đang giữ cổng
        local stopped=false
        if ss -lnt 2>/dev/null | grep -q ':80 '; then
            echo -e "${yellow}Tạm dừng V2bX để giải phóng cổng 80...${plain}"
            eval "$(svc_cmd stop)" &>/dev/null && stopped=true
            sleep 2
        fi
        echo -e "${yellow}Đang xin chứng chỉ cho ${domain} (xác thực qua cổng 80)...${plain}"
        "$acme" --issue --standalone -d "$domain" --keylength ec-256 && issued=true
        [ "$stopped" = true ] && eval "$(svc_cmd start)" &>/dev/null
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
        return 1
    fi

    # reloadcmd: mỗi lần acme.sh tự gia hạn thì V2bX nạp lại cert mới
    "$acme" --install-cert -d "$domain" --ecc \
        --fullchain-file "${CONF_DIR}/cert.crt" \
        --key-file "${CONF_DIR}/private.key" \
        --reloadcmd "$(svc_cmd restart)" &>/dev/null \
        || { echo -e "${red}Cài chứng chỉ vào ${CONF_DIR} thất bại.${plain}"; return 1; }

    chmod 600 "${CONF_DIR}/private.key"
    CERT_DOMAIN="$domain"
    echo -e "${green}✓ Đã cấp chứng chỉ thật cho ${domain}${plain}"
    openssl x509 -in "${CONF_DIR}/cert.crt" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/  /'
    echo -e "${green}  Tự động gia hạn đã bật sẵn (cron của acme.sh).${plain}"
    return 0
}

# Kiểm tra quyền root
[[ $EUID -ne 0 ]] && die "Script này phải được chạy dưới quyền root!"

# ==========================================
# Phát hiện hệ điều hành
# ==========================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_ID_LIKE="${ID_LIKE}"
        OS_VERSION="${VERSION_ID}"
        OS_NAME="${NAME}"
    elif [ -f /etc/system-release ]; then
        OS_NAME=$(cat /etc/system-release)
        OS_ID="centos"
    else
        OS_ID="unknown"
        OS_NAME="Unknown Linux"
    fi

    case "${OS_ID}" in
        ubuntu|debian|linuxmint|raspbian|devuan|deepin|kali|armbian)
            PKG_MANAGER="apt" ;;
        centos|rhel|rocky|almalinux|fedora|kylin|opencloudos|anolis|tencentos|amzn|ol)
            PKG_MANAGER="dnf" ;;
        euler|euleros|openeuler|uos|culinux)
            PKG_MANAGER="dnf"; IS_EULER=true ;;
        opensuse*|sles|sled)
            PKG_MANAGER="zypper" ;;
        arch|manjaro|endeavouros)
            PKG_MANAGER="pacman" ;;
        alpine)
            PKG_MANAGER="apk" ;;
        *)
            if echo "${OS_ID_LIKE}" | grep -qiE "rhel|centos|fedora"; then
                PKG_MANAGER="dnf"
                echo "${OS_NAME}" | grep -qiE "euler|huawei" && IS_EULER=true
            elif echo "${OS_ID_LIKE}" | grep -qi "suse"; then
                PKG_MANAGER="zypper"
            elif echo "${OS_ID_LIKE}" | grep -qi "arch"; then
                PKG_MANAGER="pacman"
            elif echo "${OS_ID_LIKE}" | grep -qi "debian"; then
                PKG_MANAGER="apt"
            else
                for m in apt dnf yum zypper pacman apk; do
                    command -v "$m" &>/dev/null && { PKG_MANAGER="$m"; break; }
                done
                PKG_MANAGER="${PKG_MANAGER:-apt}"
            fi ;;
    esac

    # EulerOS 2.x đời cũ chỉ có yum, không có dnf
    if [ "${PKG_MANAGER}" = "dnf" ] && ! command -v dnf &>/dev/null; then
        command -v yum &>/dev/null && PKG_MANAGER="yum"
    fi

    case "${PKG_MANAGER}" in
        apt)    PKG_UPDATE="apt-get update -y";      PKG_INSTALL="apt-get install -y" ;;
        dnf)    PKG_UPDATE="dnf makecache -y";       PKG_INSTALL="dnf install -y" ;;
        yum)    PKG_UPDATE="yum makecache -y";       PKG_INSTALL="yum install -y" ;;
        zypper) PKG_UPDATE="zypper --gpg-auto-import-keys refresh"; PKG_INSTALL="zypper install -y" ;;
        pacman) PKG_UPDATE="pacman -Sy --noconfirm"; PKG_INSTALL="pacman -S --noconfirm --needed" ;;
        apk)    PKG_UPDATE="apk update";             PKG_INSTALL="apk add --no-cache" ;;
    esac
}

# ==========================================
# Phát hiện kiến trúc CPU
# ==========================================
# Đọc byte EI_DATA trong header ELF để biết máy big-endian hay little-endian
# (cần cho họ MIPS, vì uname -m không phân biệt được)
detect_endian() {
    local probe
    for probe in /bin/sh /bin/busybox /proc/self/exe; do
        [ -r "$probe" ] || continue
        local d
        d=$(od -An -tu1 -j5 -N1 "$probe" 2>/dev/null | tr -d ' ')
        [ "$d" = "1" ] && { echo "le"; return; }
        [ "$d" = "2" ] && { echo "be"; return; }
    done
    echo "le"
}

detect_arch() {
    MACHINE_ARCH=$(uname -m)
    # Kernel 64-bit nhưng userland 32-bit (Raspberry Pi OS, một số image ARM)
    USERLAND_BITS=$(getconf LONG_BIT 2>/dev/null || echo 64)

    case "${MACHINE_ARCH}" in
        x86_64|amd64)
            if [ "${USERLAND_BITS}" = "32" ]; then ARCH_SUFFIX="linux-386"
            else ARCH_SUFFIX="linux-amd64"; fi ;;
        i386|i486|i586|i686|x86|x86pc)
            ARCH_SUFFIX="linux-386" ;;
        aarch64|arm64|armv8*|armv9*)
            if [ "${USERLAND_BITS}" = "32" ]; then ARCH_SUFFIX="linux-arm32-v7"
            else ARCH_SUFFIX="linux-arm64"; fi ;;
        armv7*|armhf)
            ARCH_SUFFIX="linux-arm32-v7" ;;
        armv6*)
            ARCH_SUFFIX="linux-arm32-v6" ;;
        armv5*|armv4*|arm)
            ARCH_SUFFIX="linux-arm32-v5" ;;
        mips64el|mips64le)
            ARCH_SUFFIX="linux-mips64le" ;;
        mips64)
            [ "$(detect_endian)" = "le" ] && ARCH_SUFFIX="linux-mips64le" || ARCH_SUFFIX="linux-mips64" ;;
        mipsel|mipsle)
            ARCH_SUFFIX="linux-mips32le" ;;
        mips)
            [ "$(detect_endian)" = "le" ] && ARCH_SUFFIX="linux-mips32le" || ARCH_SUFFIX="linux-mips32" ;;
        ppc64le|powerpc64le)
            ARCH_SUFFIX="linux-ppc64le" ;;
        ppc64|powerpc64)
            [ "$(detect_endian)" = "le" ] && ARCH_SUFFIX="linux-ppc64le" || ARCH_SUFFIX="linux-ppc64" ;;
        s390x)
            ARCH_SUFFIX="linux-s390x" ;;
        riscv64)
            die "Kiến trúc riscv64 chưa có bản build sẵn. Hãy tự build bằng ./build.sh rồi cài tay." ;;
        *)
            die "Không nhận ra kiến trúc '${MACHINE_ARCH}'. Hãy tự build bằng ./build.sh." ;;
    esac
}

# ==========================================
# Phát hiện hệ thống init
# ==========================================
detect_init() {
    if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif command -v rc-update &>/dev/null; then
        INIT_SYSTEM="openrc"
    else
        die "Máy không có systemd lẫn OpenRC — không tự cài dịch vụ được."
    fi
}

ensure_pkg() {
    # ensure_pkg <lệnh> [tên gói]
    local cmd="$1" pkg="${2:-$1}"
    command -v "$cmd" &>/dev/null && return 0
    echo -e "${yellow}  Đang cài '${pkg}'...${plain}"
    eval "${PKG_UPDATE}" &>/dev/null
    eval "${PKG_INSTALL} ${pkg}" &>/dev/null
    command -v "$cmd" &>/dev/null
}

detect_os
detect_arch
detect_init

echo -e "${blue}===========================================${plain}"
echo -e "${green} Cài đặt V2bX - Multi-Node & Auto SSL IP${plain}"
echo -e "${blue}===========================================${plain}"
echo -e "${yellow}  Hệ điều hành : ${OS_NAME:-Unknown} ${OS_VERSION}${plain}"
echo -e "${yellow}  Kiến trúc    : ${MACHINE_ARCH} → ${ARCH_SUFFIX}${plain}"
echo -e "${yellow}  Package Mgr  : ${PKG_MANAGER}${plain}"
echo -e "${yellow}  Init         : ${INIT_SYSTEM}${plain}"
[ "${IS_EULER}" = "true" ] && echo -e "${green}  ✓ EulerOS/openEuler (Huawei) — đã bật chế độ tương thích${plain}"
echo -e "${blue}===========================================${plain}"
echo ""

# ==========================================
# 1. Thu thập thông tin (bỏ qua được bằng export biến môi trường)
# ==========================================
# Nhận cả tên biến ngắn HXapiHost/HXapiKey lẫn API_HOST/API_KEY, để viết được
# lệnh cài một dòng:
#   export HXapiHost="panel.com" && export HXapiKey="KEY" && export NODE_ID=5 \
#     && bash <(curl -Ls .../install.sh)
API_HOST="${API_HOST:-${HXapiHost:-}}"
API_KEY="${API_KEY:-${HXapiKey:-}}"

# Đặt sẵn NODE_ID nghĩa là cài đúng một node, không hỏi gì nữa
if [ -n "${NODE_ID}" ]; then
    NUM_NODES=1
    NODE_TYPE="${NODE_TYPE:-V2ray}"
    AUTO_SSL="${AUTO_SSL:-y}"
fi

if [ -z "$API_HOST" ]; then
    read -p "Nhập link Panel (VD: https://panel.com): " API_HOST
fi
[ -z "$API_HOST" ] && die "Chưa nhập link Panel."
# Bỏ dấu / thừa ở cuối, tự thêm https:// nếu người dùng chỉ gõ tên miền
API_HOST="${API_HOST%/}"
[[ "$API_HOST" =~ ^https?:// ]] || API_HOST="https://${API_HOST}"

if [ -z "$API_KEY" ]; then
    read -p "Nhập API Key của Panel: " API_KEY
fi
[ -z "$API_KEY" ] && die "Chưa nhập API Key."

echo ""
# Cho phép cài không cần hỏi: đặt sẵn HXdomain (và HXcfToken nếu xác thực qua DNS)
SSL_DOMAIN="${SSL_DOMAIN:-${HXdomain:-}}"
CF_TOKEN="${CF_TOKEN:-${HXcfToken:-}}"

if [ -n "$SSL_DOMAIN" ]; then
    SSL_MODE=1
elif [ -n "$AUTO_SSL" ]; then
    # Giữ tương thích ngược với biến AUTO_SSL cũ (y = cert tự ký theo IP)
    [[ "$AUTO_SSL" =~ ^[yY] ]] && SSL_MODE=2 || SSL_MODE=3
else
    echo -e "${cyan}Chọn kiểu chứng chỉ SSL cho Node:${plain}"
    echo -e "  ${green}1.${plain} Cert thật Let's Encrypt theo tên miền ${green}(khuyên dùng cho cổng 443)${plain}"
    echo -e "  ${yellow}2.${plain} Cert tự ký theo IP  ${yellow}(chỉ dùng được khi Panel bật allowInsecure)${plain}"
    echo -e "  ${blue}3.${plain} Bỏ qua, không tạo chứng chỉ"
    read -p "Nhập số (1-3) [mặc định 1]: " SSL_MODE
    SSL_MODE="${SSL_MODE:-1}"
fi

HAS_SSL=false
USE_LE=false
case "$SSL_MODE" in
    1)
        USE_LE=true
        if [ -z "$SSL_DOMAIN" ]; then
            read -p "Nhập tên miền trỏ về máy này (VD: node1.domain.com): " SSL_DOMAIN
        fi
        [ -z "$SSL_DOMAIN" ] && die "Chưa nhập tên miền cho chứng chỉ."
        if [ -z "$CF_TOKEN" ]; then
            echo -e "${yellow}Nếu tên miền nằm trên Cloudflare (nhất là khi đang bật proxy),${plain}"
            echo -e "${yellow}dán API Token có quyền Zone:DNS:Edit để xác thực qua DNS.${plain}"
            echo -e "${yellow}Bỏ trống thì sẽ xác thực qua cổng 80 (tên miền phải trỏ thẳng về IP máy này).${plain}"
            read -p "Cloudflare API Token (bỏ trống để dùng cổng 80): " CF_TOKEN
        fi
        echo -e "${green}==> Sẽ cấp chứng chỉ thật cho ${SSL_DOMAIN}.${plain}"
        ;;
    2)
        HAS_SSL=true
        echo -e "${green}==> Sẽ tạo chứng chỉ tự ký theo IP máy chủ.${plain}"
        ;;
    *)
        echo -e "${blue}==> Bỏ qua bước tạo chứng chỉ.${plain}"
        ;;
esac

echo ""
if [ -z "$NUM_NODES" ]; then
    read -p "Bạn muốn chạy bao nhiêu Node trên máy chủ này? (VD: 2): " NUM_NODES
fi
if ! [[ "$NUM_NODES" =~ ^[1-9][0-9]*$ ]]; then
    echo -e "${red}Số lượng không hợp lệ, mặc định sẽ tạo 1 Node.${plain}"
    NUM_NODES=1
fi

declare -a NODE_CONFIGS

for (( i=1; i<=NUM_NODES; i++ )); do
    echo -e "\n${yellow}--- Cấu hình cho Node thứ $i ---${plain}"

    # Cài một dòng: NODE_ID + NODE_TYPE lấy thẳng từ biến môi trường, không hỏi
    if [ -n "${NODE_ID}" ]; then
        CURRENT_NODE_ID="${NODE_ID}"
        [[ "$CURRENT_NODE_ID" =~ ^[0-9]+$ ]] || die "NODE_ID phải là số, đang nhận '${NODE_ID}'."
    else
        CURRENT_NODE_ID=""
        while ! [[ "$CURRENT_NODE_ID" =~ ^[0-9]+$ ]]; do
            read -p "Nhập Node ID cho Node thứ $i: " CURRENT_NODE_ID
            [[ "$CURRENT_NODE_ID" =~ ^[0-9]+$ ]] || echo -e "${red}  Node ID phải là số.${plain}"
        done

        echo "Chọn loại Giao thức (Node Type):"
        echo "  1. VMess          (nhân xray)"
        echo "  2. VLESS          (nhân xray)"
        echo "  3. Trojan         (nhân xray)"
        echo "  4. Shadowsocks    (nhân sing)"
        echo "  5. Hysteria2      (nhân hysteria2)"
        echo "  6. Hysteria v1    (nhân sing)"
        echo "  7. TUIC           (nhân sing)"
        echo "  8. AnyTLS         (nhân sing)"
        read -p "Nhập số (1-8): " CURRENT_TYPE_CHOICE

        case $CURRENT_TYPE_CHOICE in
            1) NODE_TYPE="VMess" ;;
            2) NODE_TYPE="VLESS" ;;
            3) NODE_TYPE="Trojan" ;;
            4) NODE_TYPE="Shadowsocks" ;;
            5) NODE_TYPE="Hysteria2" ;;
            6) NODE_TYPE="Hysteria" ;;
            7) NODE_TYPE="TUIC" ;;
            8) NODE_TYPE="AnyTLS" ;;
            *) echo -e "${red}Lựa chọn không hợp lệ. Mặc định dùng VMess.${plain}"
               NODE_TYPE="VMess" ;;
        esac
    fi

    # Loại nào chạy trên nhân nào — theo đúng bảng dispatch trong mã nguồn:
    #   core/xray/inbound.go : vmess, vless, trojan, shadowsocks
    #   core/sing/node.go    : cả 8 loại (superset)
    #   core/hy2             : riêng hysteria2
    NODE_TYPE_LC=$(echo "${NODE_TYPE}" | tr 'A-Z' 'a-z')
    case "${NODE_TYPE_LC}" in
        vmess|v2ray)             NODE_TYPE="VMess";       CORE="xray" ;;
        vless)                   NODE_TYPE="VLESS";       CORE="xray" ;;
        trojan)                  NODE_TYPE="Trojan";      CORE="xray" ;;
        shadowsocks|ss)          NODE_TYPE="Shadowsocks"; CORE="sing" ;;
        hysteria2|hy2)           NODE_TYPE="Hysteria2";   CORE="hysteria2" ;;
        hysteria|hysteria1|hy)   NODE_TYPE="Hysteria";    CORE="sing" ;;
        tuic)                    NODE_TYPE="TUIC";        CORE="sing" ;;
        anytls)                  NODE_TYPE="AnyTLS";      CORE="sing" ;;
        socks|naive|http|mieru)
            die "V2bX không chạy được loại '${NODE_TYPE}'.
    Panel có sẵn loại này nhưng V2bX không có nhân dựng inbound cho nó
    (api/panel/panel.go chỉ nhận 8 loại). Chọn loại khác, hoặc dùng
    phần mềm node khác cho riêng node đó." ;;
        *)
            die "NODE_TYPE không hợp lệ: '${NODE_TYPE}'.
    Chỉ nhận: VMess, VLESS, Trojan, Shadowsocks, Hysteria2, Hysteria, TUIC, AnyTLS" ;;
    esac

    echo -e "${green}==> Đã tự động gán Core [ ${CORE} ] cho giao thức [ ${NODE_TYPE} ]${plain}"

    if [ "$HAS_SSL" = true ] || [ "$USE_LE" = true ]; then
        CERT_JSON=",
        \"CertConfig\": {
          \"CertMode\": \"file\",
          \"CertFile\": \"${CONF_DIR}/cert.crt\",
          \"KeyFile\": \"${CONF_DIR}/private.key\"
        }"
    else
        CERT_JSON=""
    fi

    NODE_JSON="    {
      \"ApiConfig\": {
        \"ApiHost\": \"${API_HOST}\",
        \"ApiKey\": \"${API_KEY}\",
        \"NodeID\": ${CURRENT_NODE_ID},
        \"NodeType\": \"${NODE_TYPE}\",
        \"Timeout\": 30
      },
      \"Options\": {
        \"Core\": \"${CORE}\",
        \"ListenIP\": \"0.0.0.0\",
        \"SendIP\": \"0.0.0.0\",
        \"DeviceOnlineMinTraffic\": 100${CERT_JSON}
      }
    }"

    NODE_CONFIGS+=("$NODE_JSON")
done

NODES_JSON_ARRAY=""
for (( i=0; i<${#NODE_CONFIGS[@]}; i++ )); do
    [ $i -gt 0 ] && NODES_JSON_ARRAY+=","
    NODES_JSON_ARRAY+="${NODE_CONFIGS[$i]}"
done

# ==========================================
# 2. Chuẩn bị thư mục + chứng chỉ SSL
# ==========================================
echo -e "\n${yellow}Đang tạo thư mục và môi trường...${plain}"
mkdir -p "${CONF_DIR}" "${BIN_DIR}"

ensure_pkg curl || die "Không cài được curl."
ensure_pkg unzip || die "Không cài được unzip."

if [ "$USE_LE" = true ]; then
    ensure_pkg openssl || die "Không cài được openssl."
    if ! issue_le_cert "$SSL_DOMAIN" "$CF_TOKEN"; then
        echo -e "${yellow}Chuyển sang tạo chứng chỉ tự ký để Node vẫn chạy được.${plain}"
        echo -e "${yellow}Cấp lại cert thật sau bằng: ${cyan}v2bx${yellow} → chọn 19.${plain}"
        HAS_SSL=true
    fi
fi

if [ "$HAS_SSL" = true ]; then
    ensure_pkg openssl || die "Không cài được openssl."
    echo -e "${yellow}Đang tạo chứng chỉ SSL (Self-signed) cho IP...${plain}"
    # -f để curl trả lỗi khi HTTP 4xx/5xx, không thì nó trả chuỗi rỗng mà vẫn exit 0
    # và CN của chứng chỉ sẽ trống -> openssl từ chối
    SERVER_IP=$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null \
             || curl -fsS --max-time 10 https://ifconfig.me 2>/dev/null)
    SERVER_IP=$(echo "${SERVER_IP}" | tr -d '[:space:]')
    [ -z "${SERVER_IP}" ] && SERVER_IP="127.0.0.1"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "${CONF_DIR}/private.key" \
        -out "${CONF_DIR}/cert.crt" \
        -subj "/C=VN/ST=Server/L=Server/O=V2bX/OU=Node/CN=${SERVER_IP}" 2>/dev/null \
        || die "Tạo chứng chỉ SSL thất bại."
    chmod 600 "${CONF_DIR}/private.key"
    echo -e "${green}Đã tạo SSL cho IP ${SERVER_IP} tại ${CONF_DIR}/cert.crt${plain}"
    echo -e "${yellow}  Lưu ý: cert tự ký cho IP — trên Panel phải bật 'allowInsecure' cho node này.${plain}"
fi

# ==========================================
# 3. Tải và cài binary + dữ liệu geo
# ==========================================
ZIP_NAME="V2bX-${ARCH_SUFFIX}.zip"
BINARY_URL="${BASE_URL}/${ZIP_NAME}"
TMP_DIR=$(mktemp -d /tmp/v2bx-install.XXXXXX) || die "Không tạo được thư mục tạm."
trap 'rm -rf "${TMP_DIR}"' EXIT

echo -e "\n${yellow}Đang tải V2bX cho ${ARCH_SUFFIX}...${plain}"
echo -e "${cyan}  ${BINARY_URL}${plain}"

# Dùng curl có kiểm chứng chỉ TLS (KHÔNG dùng --insecure: đây là binary chạy quyền root)
if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 \
        --progress-bar -o "${TMP_DIR}/v2bx.zip" "${BINARY_URL}"; then
    die "Không tải được ${ZIP_NAME}. Kiểm tra mạng, hoặc đặt V2BX_BASE_URL trỏ sang mirror khác."
fi

[ -s "${TMP_DIR}/v2bx.zip" ] || die "File tải về rỗng."

echo -e "${yellow}Đang giải nén...${plain}"
unzip -oq "${TMP_DIR}/v2bx.zip" -d "${TMP_DIR}/x" || die "Giải nén thất bại (file hỏng?)."

# Zip build ra có thể phẳng hoặc nằm trong 1 thư mục con — tìm binary ở cả hai kiểu
SRC_BIN=$(find "${TMP_DIR}/x" -maxdepth 2 -type f -name 'V2bX' | head -1)
[ -n "${SRC_BIN}" ] || die "Không tìm thấy file thực thi V2bX trong gói tải về."
SRC_DIR=$(dirname "${SRC_BIN}")

# Giữ lại binary cũ để lùi nếu bản mới không chạy
[ -f "${BIN}" ] && cp -f "${BIN}" "${BIN}.bak"

# Cài đè lên máy đã có V2bX: Linux không cho ghi lên file đang chạy (ETXTBSY).
# Phải dừng dịch vụ, rồi rm -f để cắt liên kết tên file — tiến trình cũ vẫn giữ
# inode nên không sao, còn tên file thì trống chỗ cho binary mới.
if [ "${INIT_SYSTEM}" = "systemd" ] && [ -f /etc/systemd/system/V2bX.service ]; then
    systemctl stop V2bX &>/dev/null
elif [ "${INIT_SYSTEM}" = "openrc" ] && [ -f /etc/init.d/V2bX ]; then
    rc-service V2bX stop &>/dev/null
fi
rm -f "${BIN}"

install -m 755 "${SRC_BIN}" "${BIN}" || die "Không chép được binary vào ${BIN}."

# --- SELinux (EulerOS / openEuler / RHEL) ---------------------------------
if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo Disabled)
    if [ "${SELINUX_STATUS}" != "Disabled" ]; then
        echo -e "${yellow}Phát hiện SELinux (${SELINUX_STATUS}), đang gán nhãn cho binary...${plain}"
        # semanage ghi vào policy nên nhãn sống sót qua relabel; chcon chỉ tạm thời
        if command -v semanage &>/dev/null; then
            semanage fcontext -a -t bin_t "${BIN_DIR}(/.*)?" 2>/dev/null
            restorecon -R "${BIN_DIR}" 2>/dev/null \
                && echo -e "${green}  ✓ Đã gán nhãn bền vững bằng semanage.${plain}"
        elif command -v chcon &>/dev/null; then
            chcon -R -t bin_t "${BIN_DIR}" 2>/dev/null \
                && echo -e "${yellow}  ✓ Đã gán nhãn tạm bằng chcon (mất sau khi relabel hệ thống).${plain}"
        fi
    fi
fi

# --- Dữ liệu geo ----------------------------------------------------------
# Xray đọc geo từ AssetPath, mặc định là /etc/V2bX/ (conf/xray.go).
# sing-box dùng geoip.db/geosite.db trong thư mục làm việc, cũng là /etc/V2bX.
# Thiếu mấy file này thì mọi rule geoip:/geosite: từ Panel đều lỗi.
echo -e "${yellow}Đang cài dữ liệu geo vào ${CONF_DIR}...${plain}"
GEO_OK=0
for g in geoip.dat geosite.dat geoip.db geosite.db; do
    if [ -f "${SRC_DIR}/${g}" ]; then
        install -m 644 "${SRC_DIR}/${g}" "${CONF_DIR}/${g}" && GEO_OK=$((GEO_OK+1))
    fi
done
if [ "${GEO_OK}" -gt 0 ]; then
    echo -e "${green}  ✓ Đã cài ${GEO_OK}/4 file geo.${plain}"
else
    echo -e "${yellow}  ⚠ Gói tải về không kèm geo — rule geoip:/geosite: từ Panel sẽ không chạy.${plain}"
fi

# File mẫu, chỉ chép khi chưa có, không đè của người dùng
for f in route.json dns.json custom_inbound.json custom_outbound.json; do
    [ -f "${SRC_DIR}/${f}" ] && [ ! -f "${CONF_DIR}/${f}" ] && \
        install -m 644 "${SRC_DIR}/${f}" "${CONF_DIR}/${f}"
done

# Kiểm tra binary chạy được trên máy này (bắt lỗi tải nhầm kiến trúc)
if ! "${BIN}" version &>/dev/null; then
    if [ -f "${BIN}.bak" ]; then
        mv -f "${BIN}.bak" "${BIN}"
        die "Binary ${ARCH_SUFFIX} không chạy được trên máy này — đã lùi về bản cũ."
    fi
    die "Binary ${ARCH_SUFFIX} không chạy được trên máy này (sai kiến trúc?)."
fi
rm -f "${BIN}.bak"
echo -e "${green}✓ Binary hoạt động: $(${BIN} version 2>/dev/null | tail -1)${plain}"

# ==========================================
# 4. Ghi file cấu hình
# ==========================================
if [ -f "${CONF_DIR}/config.json" ]; then
    cp -f "${CONF_DIR}/config.json" "${CONF_DIR}/config.json.bak.$(date +%Y%m%d%H%M%S)"
    echo -e "${yellow}Đã sao lưu config.json cũ.${plain}"
fi

echo -e "${yellow}Đang tạo file cấu hình config.json...${plain}"
cat > "${CONF_DIR}/config.json" << EOF
{
  "Log": {
    "Level": "info",
    "Output": ""
  },
  "Cores": [
    {
      "Type": "xray",
      "Log": {
        "Level": "warning"
      },
      "AssetPath": "${CONF_DIR}/"
    },
    {
      "Type": "sing",
      "Log": {
        "Level": "error",
        "Timestamp": true
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
chmod 600 "${CONF_DIR}/config.json"

# ==========================================
# 5. Cài dịch vụ
# ==========================================
echo -e "${yellow}Đang cấu hình dịch vụ (${INIT_SYSTEM})...${plain}"

if [ "${INIT_SYSTEM}" = "systemd" ]; then
    cat > /etc/systemd/system/V2bX.service << SVCEOF
[Unit]
Description=V2bX Service
Documentation=https://github.com/Tubetna/hypex-x
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${CONF_DIR}
ExecStart=${BIN} server -c ${CONF_DIR}/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1000000
LimitNPROC=1000000
# Tương thích EulerOS / openEuler: không bật sandbox, kernel cũ có thể không hỗ trợ
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable V2bX &>/dev/null
    systemctl restart V2bX
    SVC_CHECK="systemctl is-active --quiet V2bX"
    LOG_CMD="journalctl -u V2bX -n 30 --no-pager"
else
    # OpenRC (Alpine…)
    cat > /etc/init.d/V2bX << 'RCEOF'
#!/sbin/openrc-run
name="V2bX"
description="V2bX Service"
command="/usr/bin/V2bX-bin/V2bX"
command_args="server -c /etc/V2bX/config.json"
command_background=true
directory="/etc/V2bX"
pidfile="/run/V2bX.pid"
output_log="/var/log/V2bX.log"
error_log="/var/log/V2bX.log"
rc_ulimit="-n 1000000"

depend() {
    need net
    after firewall
}
RCEOF
    chmod +x /etc/init.d/V2bX
    rc-update add V2bX default &>/dev/null
    rc-service V2bX restart
    SVC_CHECK="rc-service V2bX status >/dev/null 2>&1"
    LOG_CMD="tail -n 30 /var/log/V2bX.log"
fi

# ==========================================
# 6. Kiểm tra
# ==========================================
echo -e "\n${yellow}Đang kiểm tra tiến trình hoạt động (đợi 5 giây)...${plain}"
sleep 5

echo -e "${green}==========================================${plain}"
if eval "${SVC_CHECK}"; then
    echo -e "Trạng thái: ${green}Đang chạy (Active)${plain}"
    if eval "${LOG_CMD}" 2>/dev/null | grep -qi "Các Node đã khởi động xong"; then
        echo -e "Kết nối Panel: ${green}Thành công! Đã tải cấu hình từ Panel.${plain}"
    else
        echo -e "Kết nối Panel: ${yellow}Đang chờ... (gõ 'v2bx' rồi chọn 8 để xem log)${plain}"
    fi
else
    echo -e "Trạng thái: ${red}Thất bại (Failed/Inactive)${plain}"
    echo -e "Log lỗi gần nhất:"
    eval "${LOG_CMD}" 2>/dev/null | tail -15
fi
echo -e "${green}==========================================${plain}"

# Cảnh báo tường lửa đang bật — node sẽ không nhận được kết nối
if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
    echo -e "\n${yellow}⚠ firewalld đang bật. Nhớ mở cổng của Node:${plain}"
    echo -e "   ${cyan}firewall-cmd --permanent --add-port=<cổng>/tcp --add-port=<cổng>/udp && firewall-cmd --reload${plain}"
    echo -e "   (hoặc gõ 'v2bx' → chọn 12 để mở nhanh)"
elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qi "^Status: active"; then
    echo -e "\n${yellow}⚠ UFW đang bật. Nhớ mở cổng của Node — hoặc gõ 'v2bx' → chọn 12.${plain}"
fi

# ==========================================
# 7. Cài lệnh quản lý 'v2bx'
# ==========================================
echo -e "\n${yellow}Đang cài lệnh quản lý 'v2bx'...${plain}"
if curl -fL --retry 3 --connect-timeout 15 -o /usr/local/bin/v2bx "${SCRIPT_URL}/v2bx.sh"; then
    chmod +x /usr/local/bin/v2bx
    echo -e "${green}✓ Đã cài xong! Gõ lệnh 'v2bx' bất cứ lúc nào để quản lý.${plain}"
else
    echo -e "${yellow}⚠ Không tải được script quản lý, bỏ qua (không ảnh hưởng Node).${plain}"
fi
