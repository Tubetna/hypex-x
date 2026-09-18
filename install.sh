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
bold='\033[1m'
dim='\033[2m'
plain='\033[0m'

# Gradient 256-color xanh ngọc → tím → hồng (terminal 16 màu thì hạ về cyan)
GRAD=(51 45 39 33 27 63 99 135 171 207)
if [ "$(tput colors 2>/dev/null || echo 8)" -lt 256 ]; then GRAD=(36 36 36 34 34 35 35 35 35 35); fi
g() { printf '\033[38;5;%sm' "${GRAD[$(( $1 % ${#GRAD[@]} ))]}"; }
gtext() { local str="$1" i; for (( i=0; i<${#str}; i++ )); do printf '%s%s' "$(g $i)" "${str:$i:1}"; done; printf '%s' "$plain"; }
anim_ok() { [ -t 1 ] && [ -z "$HYX_NOANIM" ]; }

# In theo bước đánh số, mỗi việc một dòng — người cài nhìn là biết đang ở đâu, hỏng chỗ nào
STEP_N=0; STEP_TOTAL=7
step() { STEP_N=$((STEP_N+1)); echo -e "\n$(g $((STEP_N+1)))${bold}[${STEP_N}/${STEP_TOTAL}] $1${plain}"; }
ok()   { echo -e "  ${green}✓${plain} $1"; }
warn() { echo -e "  ${yellow}!${plain} $1"; }
bad()  { echo -e "  ${red}✗${plain} $1"; }
hr()   { echo -e "${dim}  ──────────────────────────────────────────────────${plain}"; }

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

# Tim chung chi acme.sh da co san va con han tren may.
# Box Nhat (160.16.60.76) tung co cert that nam san o /root/.acme.sh nhung bo cai
# van tao cert tu ky de len, roi node 443 chet vi client tu choi cert tu ky.
find_existing_cert() {
    local f d
    for f in /root/.acme.sh/*_ecc/fullchain.cer /root/.acme.sh/*/fullchain.cer; do
        [ -s "$f" ] || continue
        # con han it nhat 7 ngay thi moi tinh
        openssl x509 -in "$f" -noout -checkend 604800 &>/dev/null || continue
        d=$(basename "$(dirname "$f")"); d="${d%_ecc}"
        echo "$d"; return 0
    done
    return 1
}

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
        0)  ok "${2} trỏ thẳng về máy này (${MY_PUBLIC_IP})" ;;
        10) bad "${2} đang bật PROXY Cloudflare (đám mây cam) → ${DOMAIN_POINTS_TO}"
            warn "Cổng 80 sẽ thất bại. Node sau CloudFront thì tên cần cấp là tên ORIGIN trỏ thẳng IP máy (DNS-only), KHÔNG phải Host header WS." ;;
        20) bad "${2} trỏ về ${DOMAIN_POINTS_TO}, máy này là ${MY_PUBLIC_IP:-?}"
            warn "Cert vẫn cấp được qua DNS Cloudflare, nhưng khách/CDN sẽ nối tới IP kia. Thường là chưa đổi DNS sang máy mới." ;;
        30) bad "Không phân giải được ${2} — bản ghi DNS chưa có hoặc gõ sai" ;;
    esac
}

issue_le_cert() {
    local domain="$1" cf_token="$2"
    [ -z "$domain" ] && { echo -e "${red}Chưa nhập tên miền.${plain}"; return 1; }

    ensure_pkg curl || { echo -e "${red}Không cài được curl.${plain}"; return 1; }
    ensure_pkg socat &>/dev/null

    local acme=/root/.acme.sh/acme.sh
    if [ ! -f "$acme" ]; then
        echo -e "  ${dim}Cài acme.sh...${plain}"
        curl -fsS https://get.acme.sh | sh -s email="admin@${domain}" &>/dev/null \
            || { echo -e "${red}Cài acme.sh thất bại.${plain}"; return 1; }
    fi
    "$acme" --set-default-ca --server letsencrypt &>/dev/null

    mkdir -p "${CONF_DIR}"
    local issued=false

    if [ -n "$cf_token" ] || has_saved_cf_token; then
        # DNS-01: chạy được cả khi tên miền đang bật proxy Cloudflare,
        # và không cần cổng 80 rảnh. Không dán token thì acme.sh dùng token đã lưu.
        [ -z "$cf_token" ] && ok "Dùng lại token Cloudflare đã lưu trong acme.sh"
        echo -e "  ${dim}Xin cert cho ${domain} qua DNS Cloudflare...${plain}"
        CF_Token="$cf_token" "$acme" --issue --dns dns_cf -d "$domain" \
            --keylength ec-256 && issued=true
    else
        # HTTP-01: cần cổng 80 rảnh nên tạm dừng V2bX nếu nó đang giữ cổng
        local stopped=false
        if ss -lnt 2>/dev/null | grep -q ':80 '; then
            echo -e "  ${dim}Tạm dừng V2bX để lấy cổng 80...${plain}"
            eval "$(svc_cmd stop)" &>/dev/null && stopped=true
            sleep 2
        fi
        # Cong 80 co the do tien trinh khac giu (xray roi, nginx, XrayR...),
        # dung V2bX khong giai phong duoc. Bao ro ten tien trinh cho khoi mo.
        if ss -lnt 2>/dev/null | grep -q ':80 '; then
            local holder
            holder=$(ss -lntp 2>/dev/null | awk '$4 ~ /:80$/ {print $NF; exit}')
            bad "Cổng 80 đang bị chiếm: ${holder:-không rõ tiến trình}"
            warn "Dừng tiến trình đó rồi chạy lại, hoặc dùng Cloudflare API Token (xác thực DNS, không cần cổng 80)."
            [ "$stopped" = true ] && eval "$(svc_cmd start)" &>/dev/null
            return 1
        fi
        echo -e "  ${dim}Xin cert cho ${domain} qua cổng 80...${plain}"
        "$acme" --issue --standalone -d "$domain" --keylength ec-256 && issued=true
        [ "$stopped" = true ] && eval "$(svc_cmd start)" &>/dev/null
    fi

    # acme.sh trả mã lỗi khi cert còn hạn ("Skipping. Next renewal time is...").
    # Đó không phải lỗi — cert đã có sẵn, cứ đem đi cài là được.
    if [ "$issued" != true ] && [ -s "/root/.acme.sh/${domain}_ecc/fullchain.cer" ]; then
        ok "Tên miền đã có cert còn hạn, dùng lại"
        issued=true
    fi

    if [ "$issued" != true ]; then
        bad "Xin cert thất bại cho ${domain}"
        warn "Qua DNS Cloudflare: token phải có quyền Zone:DNS:Edit · Qua cổng 80: tên miền phải trỏ đúng IP máy, cổng 80 mở"
        return 1
    fi

    # reloadcmd: mỗi lần acme.sh tự gia hạn thì V2bX nạp lại cert mới
    # Reload phải "|| true": cài mới thì service chưa có, restart lỗi làm acme trả 1.
    "$acme" --install-cert -d "$domain" --ecc \
        --fullchain-file "${CONF_DIR}/cert.crt" \
        --key-file "${CONF_DIR}/private.key" \
        --reloadcmd "$(svc_cmd restart) 2>/dev/null || true" &>/dev/null
    if ! cert_key_match "${CONF_DIR}/cert.crt" "${CONF_DIR}/private.key"; then
        bad "Cài cert vào ${CONF_DIR} thất bại (cert/key trống hoặc không khớp)"
        return 1
    fi

    chmod 600 "${CONF_DIR}/private.key"
    CERT_DOMAIN="$domain"
    ok "Let's Encrypt cho ${domain} · hết hạn $(openssl x509 -in "${CONF_DIR}/cert.crt" -noout -enddate 2>/dev/null | cut -d= -f2) · tự gia hạn"
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
    echo -e "  ${dim}Cài gói '${pkg}'...${plain}"
    eval "${PKG_UPDATE}" &>/dev/null
    eval "${PKG_INSTALL} ${pkg}" &>/dev/null
    command -v "$cmd" &>/dev/null
}

detect_os
detect_arch
detect_init

echo ""
echo -e "  ${bold}$(gtext 'HYX')${dim} · cài node V2bX${plain}"
echo -e "  $(g 0)────────────────────────────────────────────────────${plain}"
echo -e "  ${dim}${OS_NAME:-Linux} ${OS_VERSION} · ${ARCH_SUFFIX} · ${PKG_MANAGER} · ${INIT_SYSTEM}${plain}"
[ "${IS_EULER}" = "true" ] && ok "EulerOS/openEuler — đã bật chế độ tương thích"

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

step "Thông tin Panel"
if [ -z "$API_HOST" ]; then
    read -p "  Link Panel (VD: https://panel.com): " API_HOST
fi
[ -z "$API_HOST" ] && die "Chưa nhập link Panel."
# Bỏ dấu / thừa ở cuối, tự thêm https:// nếu người dùng chỉ gõ tên miền
API_HOST="${API_HOST%/}"
[[ "$API_HOST" =~ ^https?:// ]] || API_HOST="https://${API_HOST}"

if [ -z "$API_KEY" ]; then
    read -p "  API Key của Panel: " API_KEY
fi
[ -z "$API_KEY" ] && die "Chưa nhập API Key."
ok "Panel ${API_HOST}"

step "Chứng chỉ SSL"
# Cho phép cài không cần hỏi: đặt sẵn HXdomain (và HXcfToken nếu xác thực qua DNS)
SSL_DOMAIN="${SSL_DOMAIN:-${HXdomain:-}}"
CF_TOKEN="${CF_TOKEN:-${HXcfToken:-}}"

if [ -n "$SSL_DOMAIN" ]; then
    SSL_MODE=1
    SSL_PRESET=true
    # Cài không hỏi: vẫn phải kiểm tên miền, sai là dừng ngay chứ không rơi về tự ký
    ensure_pkg curl &>/dev/null
    check_cert_domain "$SSL_DOMAIN"; _rc=$?
    explain_cert_domain "$_rc" "$SSL_DOMAIN"
    if [ "$_rc" -eq 30 ] || { [ "$_rc" -ne 0 ] && [ -z "$CF_TOKEN" ] && ! has_saved_cf_token; }; then
        die "HXdomain=${SSL_DOMAIN} không dùng được cho máy này (xem trên). Sửa DNS hoặc thêm HXcfToken."
    fi
elif [ -n "$AUTO_SSL" ]; then
    # Giữ tương thích ngược với biến AUTO_SSL cũ (y = cert tự ký theo IP)
    [[ "$AUTO_SSL" =~ ^[yY] ]] && SSL_MODE=2 || SSL_MODE=3
else
    FOUND_CERT=$(find_existing_cert 2>/dev/null || true)
    echo -e "  ${green}1${plain}  Let's Encrypt theo tên miền   ${dim}(khuyên dùng cho cổng 443)${plain}"
    echo -e "  ${yellow}2${plain}  Tự ký theo IP                 ${dim}(xray 26.x trở lên từ chối)${plain}"
    echo -e "  ${blue}3${plain}  Không tạo chứng chỉ"
    [ -n "$FOUND_CERT" ] && ok "Máy đã có cert còn hạn cho ${FOUND_CERT} — chọn 1 rồi Enter là dùng lại"
    read -p "  Chọn [1-3, mặc định 1]: " SSL_MODE
    SSL_MODE="${SSL_MODE:-1}"
fi

HAS_SSL=false
USE_LE=false
case "$SSL_MODE" in
    1)
        USE_LE=true
        if [ -z "$SSL_DOMAIN" ]; then
            if [ -n "$FOUND_CERT" ]; then
                read -p "  Tên miền [Enter = dùng lại ${FOUND_CERT}]: " SSL_DOMAIN
                SSL_DOMAIN="${SSL_DOMAIN:-$FOUND_CERT}"
            else
                read -p "  Tên miền trỏ về máy này (VD: node1.domain.com): " SSL_DOMAIN
            fi
        fi
        [ -z "$SSL_DOMAIN" ] && die "Chưa nhập tên miền cho chứng chỉ."
        if [ -z "$CF_TOKEN" ] && ! has_saved_cf_token; then
            echo -e "  ${dim}Tên miền trên Cloudflare (nhất là đang bật proxy): dán API Token quyền Zone:DNS:Edit.${plain}"
            echo -e "  ${dim}Bỏ trống = xác thực qua cổng 80 (tên miền phải trỏ thẳng IP máy này).${plain}"
            read -p "  Cloudflare API Token [Enter = cổng 80]: " CF_TOKEN
        fi
        # Kiểm tên miền ngay tại đây, lúc còn sửa được, thay vì để acme thất bại rồi
        # âm thầm rơi về cert tự ký.
        ensure_pkg curl &>/dev/null
        for _try in 1 2 3; do
            echo -e "  ${dim}Kiểm tra ${SSL_DOMAIN}...${plain}"
            check_cert_domain "$SSL_DOMAIN"; _rc=$?
            explain_cert_domain "$_rc" "$SSL_DOMAIN"
            [ "$_rc" -eq 0 ] && break
            if [ "$_rc" -ne 30 ] && { [ -n "$CF_TOKEN" ] || has_saved_cf_token; }; then
                read -p "  Vẫn cấp cert cho tên này qua DNS Cloudflare? [y/N]: " _ok
                [[ "$_ok" =~ ^[yY] ]] && break
            elif [ "$_rc" -eq 10 ]; then
                warn "Tên này chỉ cấp được qua DNS Cloudflare — cần API Token."
            fi
            [ "$_try" -eq 3 ] && die "Tên miền không hợp lệ cho máy này, dừng để anh kiểm lại DNS."
            read -p "  Nhập lại tên miền [Enter = giữ ${SSL_DOMAIN}]: " _d
            [ -n "$_d" ] && SSL_DOMAIN="$_d"
            if [ -z "$CF_TOKEN" ] && ! has_saved_cf_token; then
                read -p "  Cloudflare API Token [Enter = không]: " CF_TOKEN
            fi
        done
        ok "Sẽ cấp Let's Encrypt cho ${SSL_DOMAIN}"
        ;;
    2)
        HAS_SSL=true
        warn "Sẽ tạo cert tự ký theo IP"
        ;;
    *)
        ok "Không tạo chứng chỉ"
        ;;
esac

step "Cấu hình Node"
if [ -z "$NUM_NODES" ]; then
    read -p "  Số Node chạy trên máy này [1]: " NUM_NODES
    NUM_NODES="${NUM_NODES:-1}"
fi
if ! [[ "$NUM_NODES" =~ ^[1-9][0-9]*$ ]]; then
    warn "Số lượng không hợp lệ, dùng 1 Node."
    NUM_NODES=1
fi

declare -a NODE_CONFIGS

for (( i=1; i<=NUM_NODES; i++ )); do
    [ "$NUM_NODES" -gt 1 ] && echo -e "  ${dim}— Node thứ $i —${plain}"

    # Cài một dòng: NODE_ID + NODE_TYPE lấy thẳng từ biến môi trường, không hỏi
    if [ -n "${NODE_ID}" ]; then
        CURRENT_NODE_ID="${NODE_ID}"
        [[ "$CURRENT_NODE_ID" =~ ^[0-9]+$ ]] || die "NODE_ID phải là số, đang nhận '${NODE_ID}'."
    else
        CURRENT_NODE_ID=""
        while ! [[ "$CURRENT_NODE_ID" =~ ^[0-9]+$ ]]; do
            read -p "  Node ID: " CURRENT_NODE_ID
            [[ "$CURRENT_NODE_ID" =~ ^[0-9]+$ ]] || bad "Node ID phải là số."
        done

        echo -e "  Giao thức:  ${green}1${plain} VMess   ${green}2${plain} VLESS   ${green}3${plain} Trojan   ${green}4${plain} Shadowsocks"
        echo -e "              ${green}5${plain} Hysteria2   ${green}6${plain} Hysteria   ${green}7${plain} TUIC   ${green}8${plain} AnyTLS"
        read -p "  Chọn [1-8, mặc định 2]: " CURRENT_TYPE_CHOICE
        CURRENT_TYPE_CHOICE="${CURRENT_TYPE_CHOICE:-2}"

        case $CURRENT_TYPE_CHOICE in
            1) NODE_TYPE="VMess" ;;
            2) NODE_TYPE="VLESS" ;;
            3) NODE_TYPE="Trojan" ;;
            4) NODE_TYPE="Shadowsocks" ;;
            5) NODE_TYPE="Hysteria2" ;;
            6) NODE_TYPE="Hysteria" ;;
            7) NODE_TYPE="TUIC" ;;
            8) NODE_TYPE="AnyTLS" ;;
            *) warn "Lựa chọn không hợp lệ, dùng VLESS."
               NODE_TYPE="VLESS" ;;
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

    ok "Node #${CURRENT_NODE_ID} · ${NODE_TYPE} · nhân ${CORE}"

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
step "Môi trường & chứng chỉ"
mkdir -p "${CONF_DIR}" "${BIN_DIR}"

ensure_pkg curl || die "Không cài được curl."
ensure_pkg unzip || die "Không cài được unzip."
ok "Thư mục ${CONF_DIR} · curl · unzip"

if [ "$USE_LE" = true ]; then
    ensure_pkg openssl || die "Không cài được openssl."
    if ! issue_le_cert "$SSL_DOMAIN" "$CF_TOKEN"; then
        # Cài không hỏi (HXdomain đặt sẵn) mà cert hỏng thì dừng hẳn — để node 443
        # chạy với cert tự ký là CloudFront 502 âm thầm, tệ hơn dừng cài.
        [ "${SSL_PRESET:-}" = true ] && die "Không cấp được cert cho ${SSL_DOMAIN}. Kiểm lại DNS/token rồi chạy lại."
        bad "Không cấp được cert thật cho ${SSL_DOMAIN}"
        echo -e "  ${green}1${plain}  Nhập lại tên miền / token rồi thử lại"
        echo -e "  ${yellow}2${plain}  Tạm dùng cert tự ký theo IP ${red}(node 443 sẽ 502 qua CloudFront)${plain}"
        echo -e "  ${blue}3${plain}  Dừng cài"
        read -p "  Chọn [1-3, mặc định 1]: " _c
        case "${_c:-1}" in
            2) HAS_SSL=true ;;
            3) die "Dừng theo yêu cầu." ;;
            *) read -p "  Tên miền [Enter = giữ ${SSL_DOMAIN}]: " _d; [ -n "$_d" ] && SSL_DOMAIN="$_d"
               read -p "  Cloudflare API Token [Enter = giữ như cũ]: " _t; [ -n "$_t" ] && CF_TOKEN="$_t"
               issue_le_cert "$SSL_DOMAIN" "$CF_TOKEN" || die "Vẫn không cấp được cert. Dừng để anh kiểm lại DNS/token." ;;
        esac
    fi
fi

if [ "$HAS_SSL" = true ]; then
    ensure_pkg openssl || die "Không cài được openssl."
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
    ok "Cert tự ký cho IP ${SERVER_IP}"
    warn "xray 26.x+ và CloudFront từ chối cert tự ký — node 443 nên cấp cert thật: ${cyan}hyx${plain} → 19"
fi

# ==========================================
# 3. Tải và cài binary + dữ liệu geo
# ==========================================
ZIP_NAME="V2bX-${ARCH_SUFFIX}.zip"
BINARY_URL="${BASE_URL}/${ZIP_NAME}"
TMP_DIR=$(mktemp -d /tmp/v2bx-install.XXXXXX) || die "Không tạo được thư mục tạm."
trap 'rm -rf "${TMP_DIR}"' EXIT

step "Tải V2bX"
echo -e "  ${dim}${BINARY_URL}${plain}"

# Dùng curl có kiểm chứng chỉ TLS (KHÔNG dùng --insecure: đây là binary chạy quyền root)
_prog="-sS"; anim_ok && _prog="--progress-bar"
if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 \
        ${_prog} -o "${TMP_DIR}/v2bx.zip" "${BINARY_URL}"; then
    die "Không tải được ${ZIP_NAME}. Kiểm tra mạng, hoặc đặt V2BX_BASE_URL trỏ sang mirror khác."
fi

[ -s "${TMP_DIR}/v2bx.zip" ] || die "File tải về rỗng."

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
        # semanage ghi vào policy nên nhãn sống sót qua relabel; chcon chỉ tạm thời
        if command -v semanage &>/dev/null; then
            semanage fcontext -a -t bin_t "${BIN_DIR}(/.*)?" 2>/dev/null
            restorecon -R "${BIN_DIR}" 2>/dev/null \
                && ok "SELinux ${SELINUX_STATUS}: đã gán nhãn binary (semanage)"
        elif command -v chcon &>/dev/null; then
            chcon -R -t bin_t "${BIN_DIR}" 2>/dev/null \
                && warn "SELinux ${SELINUX_STATUS}: gán nhãn tạm bằng chcon (mất khi relabel)"
        fi
    fi
fi

# --- Dữ liệu geo ----------------------------------------------------------
# Xray đọc geo từ AssetPath, mặc định là /etc/V2bX/ (conf/xray.go).
# sing-box dùng geoip.db/geosite.db trong thư mục làm việc, cũng là /etc/V2bX.
# Thiếu mấy file này thì mọi rule geoip:/geosite: từ Panel đều lỗi.
GEO_OK=0
for g in geoip.dat geosite.dat geoip.db geosite.db; do
    if [ -f "${SRC_DIR}/${g}" ]; then
        install -m 644 "${SRC_DIR}/${g}" "${CONF_DIR}/${g}" && GEO_OK=$((GEO_OK+1))
    fi
done
if [ "${GEO_OK}" -gt 0 ]; then
    ok "Dữ liệu geo ${GEO_OK}/4 file"
else
    warn "Gói không kèm geo — rule geoip:/geosite: từ Panel sẽ không chạy"
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
ok "$(${BIN} version 2>/dev/null | tail -1 | sed 's/ (.*//')"

# ==========================================
# 4. Ghi file cấu hình
# ==========================================
step "Ghi cấu hình & dịch vụ"
if [ -f "${CONF_DIR}/config.json" ]; then
    cp -f "${CONF_DIR}/config.json" "${CONF_DIR}/config.json.bak.$(date +%Y%m%d%H%M%S)"
    ok "Đã sao lưu config.json cũ"
fi
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
      "AssetPath": "${CONF_DIR}/",
      "DnsConfigPath": "${CONF_DIR}/dns.json",
      "XrayConnectionConfig": {
        "handshake": 4,
        "connIdle": 30,
        "uplinkOnly": 2,
        "downlinkOnly": 4,
        "bufferSize": 16
      }
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
ok "config.json (${NUM_NODES} node)"

# ==========================================
# 4b. Ép MSS 1400 + dò MTU (chống app treo do đường rớt gói 1500 byte)
# ==========================================
# 12/09/2026: node Hanoi Telecom tới AWS Việt Nam (166.117.0.0/16, Global Accelerator)
# rớt gói 1500 byte mà không trả ICMP frag-needed -> TCP retransmit mãi, app đặt trên AWS
# (Xanh SM...) treo ở màn hình logo trong khi Google/Facebook vẫn chạy. PMTU đo được 1482.
# Phải ép ở CẢ INPUT: rule OUTPUT chỉ ép cỡ gói server gửi về, cỡ gói node gửi đi theo
# MSS trong SYN-ACK của server.
if [ "${INIT_SYSTEM}" = "systemd" ] && command -v iptables &>/dev/null; then
    cat > /etc/sysctl.d/90-v2bx-mtu.conf << 'EOF'
# Duong toi AWS VN rot goi 1500 byte, ICMP frag-needed khong ve -> de kernel tu ha co goi
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1200
EOF
    sysctl -q -p /etc/sysctl.d/90-v2bx-mtu.conf 2>/dev/null
    cat > /usr/local/sbin/mss-clamp.sh << 'EOF'
#!/bin/sh
# Ep MSS moi ket noi TCP qua node xuong 1400 (PMTU toi AWS VN = 1482 -> toi da 1442).
# INPUT: SYN-ACK cua server + SYN cua khach (quyet dinh co goi node GUI DI).
# OUTPUT/FORWARD: SYN node gui (quyet dinh co goi server GUI VE).
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
    if systemctl enable --now mss-clamp.service &>/dev/null \
       && iptables -t mangle -S INPUT 2>/dev/null | grep -q TCPMSS; then
        MSS_OK=true; ok "Ép MSS 1400 + tcp_mtu_probing (chống app treo do MTU)"
    else
        MSS_OK=false; warn "Không ép được MSS (thiếu module TCPMSS?) — app trên AWS VN có thể treo"
    fi
fi

# ==========================================
# 4c. Máy ít RAM: swap + trần bộ nhớ cho Go
# ==========================================
# 12/09/2026: máy 1 GB không swap, ~1.500 kết nối đồng thời -> V2bX phình 700-800 MB
# (bufferSize 64 KB x 2 chiều x số kết nối, cộng GC giữ gấp đôi) -> OOM killer giết
# 10 lần/ngày, mỗi lần mọi khách trên máy đứt 10 s -> "FB lúc load ảnh lúc không".
# Ba lớp: bufferSize 16 KB (config.json ở trên), GOMEMLIMIT để Go dọn rác gắt trước
# khi chạm trần, và swap để không bị giết thẳng tay.
MEM_TOTAL_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
GOMEMLIMIT_MB=$(( MEM_TOTAL_MB * 55 / 100 ))
[ "${GOMEMLIMIT_MB}" -lt 256 ] && GOMEMLIMIT_MB=256
if [ "${INIT_SYSTEM}" = "systemd" ]; then
    mkdir -p /etc/systemd/system/V2bX.service.d
    cat > /etc/systemd/system/V2bX.service.d/memory.conf << EOF
[Service]
# Go don rac gat gao khi heap cham ${GOMEMLIMIT_MB} MiB (55% RAM) thay vi de OOM killer giet
Environment=GOMEMLIMIT=${GOMEMLIMIT_MB}MiB
Environment=GOGC=100
EOF
fi
if [ "${MEM_TOTAL_MB}" -gt 0 ] && [ "${MEM_TOTAL_MB}" -lt 2048 ] && [ "$(awk '/SwapTotal/{print $2}' /proc/meminfo)" = "0" ]; then
    if fallocate -l 1G /swapfile 2>/dev/null && chmod 600 /swapfile && mkswap /swapfile &>/dev/null && swapon /swapfile 2>/dev/null; then
        grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo 'vm.swappiness=10' > /etc/sysctl.d/91-v2bx-swappiness.conf
        sysctl -q -w vm.swappiness=10 2>/dev/null
        ok "Máy ${MEM_TOTAL_MB} MB không swap → đã tạo swap 1 GB, GOMEMLIMIT=${GOMEMLIMIT_MB}MiB"
    else
        rm -f /swapfile
        warn "Không tạo được swap (fallocate không hỗ trợ?) — chỉ đặt GOMEMLIMIT=${GOMEMLIMIT_MB}MiB"
    fi
else
    ok "GOMEMLIMIT=${GOMEMLIMIT_MB}MiB (RAM ${MEM_TOTAL_MB} MB)"
fi

# ==========================================
# 4d. Tối ưu mạng (BBR+fq, buffer, TFO, DNS cache, journald) — tune-net.sh
# ==========================================
# Chạy SAU khi config.json đã ghi và TRƯỚC khi cài dịch vụ; script tự restart V2bX
# nếu đã có, lần cài mới thì restart ở bước 5 sẽ nạp. Xem tune-net.sh để biết từng mục.
# 13/09/2026: khách game báo "khựng hơn" sau tuning trên node 25/26, gỡ thì ổn → KHÔNG tự chạy.
# Chỉ chạy khi chủ động: HXtune=1 khi cài, hoặc hyx → 22 sau này.
if [ "${HXtune:-0}" = "1" ] && [ "${INIT_SYSTEM}" = "systemd" ] && command -v python3 &>/dev/null; then
    TUNE_URL="https://raw.githubusercontent.com/Tubetna/hypex-x/main/tune-net.sh"
    if curl -fsSL -o /usr/local/sbin/hyx-tune-net.sh "${TUNE_URL}" 2>/dev/null; then
        chmod 755 /usr/local/sbin/hyx-tune-net.sh
        if bash /usr/local/sbin/hyx-tune-net.sh >/tmp/hyx-tune.log 2>&1; then
            ok "Tối ưu mạng: BBR+fq · buffer TCP · TFO/NoDelay · DNS cache · journald 300M"
        else
            warn "Tối ưu mạng lỗi (xem /tmp/hyx-tune.log) — node vẫn chạy, chạy lại bằng hyx → 22"
        fi
    else
        warn "Không tải được tune-net.sh — chạy sau bằng hyx → 22"
    fi
else
    ok "Tối ưu mạng: bỏ qua (mặc định; bật bằng HXtune=1 hoặc hyx → 22 — node game nên để nguyên)"
fi

# ==========================================
# 4e. Dọn kết nối TCP chết (conn-reaper) — timer 5 phút
# ==========================================
# 17/09/2026: node Reality trực tiếp (CHINA 1/2) giữ 7.000 ESTABLISHED trong khi chỉ ~22 khách:
# phiên UDP 443 (QUIC) qua VLESS bị route block, Xray không đóng kết nối vào, app khách giữ
# socket mãi -> RAM vượt GOMEMLIMIT -> GC ăn 100% CPU. `ss -K` ngắt kết nối im > 15 phút
# (Xray đã tự cắt kết nối có traffic sau connIdle 300 s nên không đụng khách thật).
# Node sau CDN không dính nhưng chạy cũng vô hại. Tắt: HXreaper=0.
if [ "${HXreaper:-1}" = "1" ] && [ "${INIT_SYSTEM}" = "systemd" ] && command -v ss &>/dev/null; then
    if curl -fsSL -o /usr/local/sbin/v2bx-conn-reaper.sh "${SCRIPT_URL}/conn-reaper.sh" 2>/dev/null; then
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
        if systemctl enable --now v2bx-conn-reaper.timer &>/dev/null; then
            ok "Dọn kết nối chết: timer 5 phút, ngắt kết nối im > 15 phút (log: journalctl -t v2bx-reaper)"
        else
            warn "Không bật được v2bx-conn-reaper.timer"
        fi
        KCFG=/boot/config-$(uname -r)
        if [ -r "$KCFG" ] && ! grep -q '^CONFIG_INET_DIAG_DESTROY=y' "$KCFG"; then
            warn "Kernel thiếu CONFIG_INET_DIAG_DESTROY — ss -K không ngắt được, timer sẽ chạy không"
        fi
    else
        warn "Không tải được conn-reaper.sh — chạy sau bằng hyx → 23"
    fi
else
    ok "Dọn kết nối chết: bỏ qua (HXreaper=0 hoặc không có systemd/ss)"
fi

# ==========================================
# 5. Cài dịch vụ
# ==========================================

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
# always: V2bX cũ thoát mã 0 khi panel lỗi, on-failure sẽ không khởi động lại
Restart=always
RestartSec=10s
LimitNOFILE=1000000
LimitNPROC=1000000
# Tương thích EulerOS / openEuler: không bật sandbox, kernel cũ có thể không hỗ trợ
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable V2bX &>/dev/null
    INSTALL_T0=$(date '+%Y-%m-%d %H:%M:%S')
    systemctl restart V2bX
    SVC_CHECK="systemctl is-active --quiet V2bX"
    LOG_CMD="journalctl -u V2bX --since '${INSTALL_T0}' --no-pager -o cat"
    ok "Dịch vụ systemd V2bX (Restart=always)"
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
    LOG_CMD="tail -n 80 /var/log/V2bX.log"
    ok "Dịch vụ OpenRC V2bX"
fi

# ==========================================
# 6. Kiểm tra
# ==========================================
step "Kiểm tra"
# Đợi tối đa 20 s cho V2bX kéo cấu hình từ Panel — dừng sớm khi thấy "khởi động xong"
# hoặc thấy lỗi, khỏi bắt người cài ngồi đếm.
SVC_OK=false; PANEL_OK=false
_frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
for _i in $(seq 1 60); do
    if anim_ok; then printf '\r  %s%s%s Đợi V2bX kéo cấu hình từ Panel...' "$(g $_i)" "${_frames:$((_i%10)):1}" "$plain"; fi
    sleep 0.33
    if [ $((_i % 3)) -eq 0 ] && eval "${SVC_CHECK}"; then
        SVC_OK=true
        _log=$(eval "${LOG_CMD}" 2>/dev/null)
        echo "$_log" | grep -q "Các Node đã khởi động xong" && { PANEL_OK=true; break; }
        echo "$_log" | grep -qiE "level=error|thất bại|failed|panic" && break
    fi
done
printf '\r\033[K'

# Rút gọn log lỗi: bỏ dòng "accepted" của khách, chỉ giữ error/fail, cắt ngắn.
# Kèm gợi ý nguyên nhân cho các lỗi hay gặp — đọc log thô của Go rất khó đoán.
show_errors() {
    local errs
    # Dòng log Go dài 300+ ký tự: cắt time="…", tag="…", chỉ giữ msg + err rồi rút gọn
    errs=$(eval "${LOG_CMD}" 2>/dev/null | grep -v accepted \
        | grep -iE "level=error|level=fatal|error|thất bại|failed|panic" | tail -6 \
        | sed -E 's/^time="[^"]*" +//; s/ +tag="[^"]*"//; s/level=(error|fatal) +//; s/\\"/"/g' \
        | sed -E 's/msg="([^"]*)" +err="(.*)"$/\1 — \2/' | sort -u | cut -c1-230)
    [ -z "$errs" ] && errs=$(eval "${LOG_CMD}" 2>/dev/null | grep -v accepted | tail -6 | cut -c1-200)
    echo -e "  ${red}Lỗi:${plain}"
    echo "$errs" | sed "s/^/    /"
    echo ""
    case "$errs" in
        *"Invalid token"*|*401*|*403*|*"token"*|*"Token"*)
            warn "Panel từ chối: ${bold}API Key sai${plain} — lấy đúng server_token trong Panel → Cài đặt → Node." ;;
        *"no such host"*|*"dial tcp"*|*"connection refused"*|*"timeout"*)
            warn "Không tới được Panel: kiểm link ${API_HOST} (DNS/https/tường lửa)." ;;
        *404*|*"not found"*|*"Node not found"*)
            warn "Panel không có node này: kiểm ${bold}NODE_ID${plain} và loại giao thức." ;;
        *"address already in use"*)
            warn "Cổng của node đang bị tiến trình khác giữ (xem cảnh báo bên dưới)." ;;
        *"certificate"*|*"cert"*|*"private key"*)
            warn "Chứng chỉ lỗi: ${cyan}hyx${plain} → 19 để cấp lại." ;;
        *"unmarshal"*|*"json"*)
            warn "Cấu hình node trên Panel có JSON hỏng (object rỗng trong protocol_settings?)." ;;
    esac
}

hr
if [ "$SVC_OK" = true ]; then
    echo -e "  Trạng thái     ${green}● Đang chạy${plain} · $(${BIN} version 2>/dev/null | tail -1 | sed 's/ (.*//')"
    if [ "$PANEL_OK" = true ]; then
        echo -e "  Panel          ${API_HOST}  ${green}✓ đã tải cấu hình${plain}"
    else
        echo -e "  Panel          ${API_HOST}  ${yellow}? chưa thấy xác nhận (xem log bên dưới)${plain}"
    fi
else
    echo -e "  Trạng thái     ${red}● Không chạy${plain}"
fi
_nodes=""
for (( i=0; i<${#NODE_CONFIGS[@]}; i++ )); do
    _id=$(echo "${NODE_CONFIGS[$i]}" | grep -oE '"NodeID": [0-9]+' | grep -oE '[0-9]+')
    _ty=$(echo "${NODE_CONFIGS[$i]}" | grep -oE '"NodeType": "[^"]+"' | cut -d'"' -f4)
    _nodes="${_nodes}#${_id} ${_ty}  "
done
echo -e "  Node           ${_nodes}"
if [ "$USE_LE" = true ] && [ -s "${CONF_DIR}/cert.crt" ]; then
    _exp=$(openssl x509 -in "${CONF_DIR}/cert.crt" -noout -enddate 2>/dev/null | cut -d= -f2)
    echo -e "  Chứng chỉ      ${CERT_DOMAIN:-$SSL_DOMAIN} · hết hạn ${_exp:-?} ${dim}(tự gia hạn)${plain}"
elif [ "$HAS_SSL" = true ]; then
    echo -e "  Chứng chỉ      ${yellow}tự ký theo IP${plain}"
else
    echo -e "  Chứng chỉ      không"
fi
_ports=$( { ss -lntp 2>/dev/null | grep -i v2bx | awk '{print $4}'; ss -lnup 2>/dev/null | grep -i v2bx | awk '{print $5}'; } \
          | sed 's/.*://' | awk '$1 ~ /^[0-9]+$/ && $1<32768' | sort -un | tr '\n' ' ')
echo -e "  Cổng lắng nghe ${_ports:-${dim}chưa có (node chưa lên hoặc chưa kéo được cấu hình)${plain}}"
if [ "${MSS_OK:-}" = true ]; then
    echo -e "  MSS/MTU        ${green}✓ ép 1400${plain}"
elif [ "${MSS_OK:-}" = false ]; then
    echo -e "  MSS/MTU        ${yellow}✗ chưa ép${plain}"
fi
hr
if [ "$SVC_OK" != true ] || [ "$PANEL_OK" != true ]; then
    show_errors
fi

# Canh bao co tien trinh khac dang giu cong cua Node.
#
# Linux cho nhieu tien trinh cung bind mot cong (SO_REUSEPORT), khong bao loi gi,
# nhung ket noi vao bi chia ngau nhien giua chung. Da gap tren 4 may: XrayR hoac
# x-ui chay song song V2bX tren cong 80/443, node "cai xong bao thanh cong" ma
# thuc te chi nhan duoc mot nua traffic, nua con lai roi vao tien trinh sai va chet.
RIVALS=""
for port in 80 443; do
    while read -r proc; do
        case "$proc" in
            ""|*V2bX*) continue ;;
            *) RIVALS="${RIVALS}\n     cổng ${port}: ${proc}" ;;
        esac
    done <<< "$(ss -lntp 2>/dev/null | awk -v p=":${port}\$" '$4 ~ p {print $NF}' | sort -u)"
done
if [ -n "$RIVALS" ]; then
    bad "Tiến trình khác đang giữ cổng của Node — khách sẽ bị chia ngẫu nhiên, node chỉ nhận một phần:"
    echo -e "${yellow}${RIVALS}${plain}"
    echo -e "     Dừng hẳn nó: ${cyan}systemctl disable --now XrayR${plain} / ${cyan}x-ui${plain}"
fi

# Cảnh báo tường lửa đang bật — node sẽ không nhận được kết nối
if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
    warn "firewalld đang bật — mở cổng của Node: ${cyan}hyx${plain} → 12"
elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qi "^Status: active"; then
    warn "UFW đang bật — mở cổng của Node: ${cyan}hyx${plain} → 12"
fi

# ==========================================
# 7. Cài lệnh quản lý 'hyx' (tên cũ 'v2bx' / 'hypex-x' vẫn chạy)
# ==========================================
if curl -fsL --retry 3 --connect-timeout 15 -o /usr/local/bin/hyx "${SCRIPT_URL}/v2bx.sh"; then
    chmod +x /usr/local/bin/hyx
    ln -sf /usr/local/bin/hyx /usr/local/bin/v2bx
    ln -sf /usr/local/bin/hyx /usr/local/bin/hypex-x
    echo -e "\n  Quản lý: gõ ${bold}$(gtext hyx)${plain}   ${dim}(7 trạng thái · 8 log)${plain}\n"
else
    warn "Không tải được script quản lý (không ảnh hưởng Node). Chạy lại: curl -fsL ${SCRIPT_URL}/v2bx.sh -o /usr/local/bin/hyx"
fi
