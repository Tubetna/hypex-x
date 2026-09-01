#!/bin/bash

# ==========================================
# V2bX Cross-Platform Build Script
# Build tất cả platform và đóng gói thành ZIP
# ==========================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
plain='\033[0m'

# ==========================================
# Cấu hình
# ==========================================
APP_NAME="V2bX"
MODULE="github.com/InazumaV/V2bX"
BUILD_TAGS="sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor"
OUTPUT_DIR="./dist"
VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo "dev")}"

LDFLAGS="-X '${MODULE}/cmd.version=${VERSION}' -s -w -buildid="
GO_BUILD="GOEXPERIMENT=jsonv2 go build -trimpath -tags \"${BUILD_TAGS}\" -ldflags \"${LDFLAGS}\""

# ==========================================
# Danh sách platform cần build
# Format: "GOOS GOARCH GOARM GOMIPS SUFFIX"
# ==========================================
PLATFORMS=(
    # Linux x86
    "linux   amd64  -  -        linux-amd64"
    "linux   386    -  -        linux-386"

    # Linux ARM
    "linux   arm64  -  -        linux-arm64"
    "linux   arm    7  -        linux-arm32-v7"
    "linux   arm    6  -        linux-arm32-v6"
    "linux   arm    5  -        linux-arm32-v5"

    # Linux MIPS
    "linux   mips    -  softfloat  linux-mips32"
    "linux   mipsle  -  softfloat  linux-mips32le"
    "linux   mips64  -  -          linux-mips64"
    "linux   mips64le - -          linux-mips64le"

    # Linux khác
    "linux   riscv64 -  -        linux-riscv64"
    "linux   s390x   -  -        linux-s390x"
    "linux   ppc64   -  -        linux-ppc64"
    "linux   ppc64le -  -        linux-ppc64le"

    # Windows
    "windows amd64  -  -        windows-amd64"
    "windows 386    -  -        windows-386"
    "windows arm64  -  -        windows-arm64"

    # macOS
    "darwin  amd64  -  -        darwin-amd64"
    "darwin  arm64  -  -        darwin-arm64"

    # FreeBSD
    "freebsd amd64  -  -        freebsd-amd64"
    "freebsd 386    -  -        freebsd-386"
    "freebsd arm64  -  -        freebsd-arm64"
    "freebsd arm    7  -        freebsd-arm32-v7"

    # Android
    "android arm64  -  -        android-arm64"
)

# ==========================================
# Kiểm tra môi trường
# ==========================================
check_env() {
    echo -e "${blue}===========================================${plain}"
    echo -e "${green}   V2bX Cross-Platform Build Script${plain}"
    echo -e "${blue}===========================================${plain}"
    echo -e "${yellow}  Version : ${VERSION}${plain}"
    echo -e "${yellow}  Output  : ${OUTPUT_DIR}${plain}"
    echo -e "${blue}===========================================${plain}"
    echo ""

    if ! command -v go &>/dev/null; then
        echo -e "${red}❌ Lỗi: Go chưa được cài đặt!${plain}"
        exit 1
    fi

    GO_VERSION=$(go version | awk '{print $3}')
    echo -e "${green}✓ Go: ${GO_VERSION}${plain}"

    if ! command -v zip &>/dev/null; then
        echo -e "${yellow}⚠ 'zip' chưa cài, đang cài...${plain}"
        apt-get install -y zip 2>/dev/null || \
        dnf install -y zip 2>/dev/null || \
        brew install zip 2>/dev/null || true
    fi

    echo -e "${green}✓ Môi trường OK${plain}"
    echo ""
}

# ==========================================
# Copy file tài nguyên vào thư mục build
# ==========================================
copy_assets() {
    local build_dir="$1"

    # Config example
    [ -d "./example" ] && cp ./example/*.json "${build_dir}/" 2>/dev/null

    # Geoip/geosite nếu có
    for f in geoip.dat geosite.dat geoip.db geosite.db; do
        [ -f "./example/${f}" ] && cp "./example/${f}" "${build_dir}/"
    done

    # README và LICENSE
    [ -f "./README.md" ] && cp ./README.md "${build_dir}/"
    [ -f "./LICENSE" ]   && cp ./LICENSE "${build_dir}/"
}

# ==========================================
# Build một platform
# ==========================================
build_one() {
    local GOOS="$1"
    local GOARCH="$2"
    local GOARM="$3"
    local GOMIPS="$4"
    local SUFFIX="$5"

    local BINARY_NAME="${APP_NAME}"
    [ "${GOOS}" = "windows" ] && BINARY_NAME="${APP_NAME}.exe"

    local BUILD_DIR="${OUTPUT_DIR}/${APP_NAME}-${SUFFIX}"
    local ZIP_FILE="${OUTPUT_DIR}/${APP_NAME}-${SUFFIX}.zip"

    # Skip nếu đã có zip
    if [ -f "${ZIP_FILE}" ] && [ "${FORCE_REBUILD}" != "1" ]; then
        echo -e "${cyan}  ⏭ Bỏ qua (đã tồn tại): ${APP_NAME}-${SUFFIX}.zip${plain}"
        return 0
    fi

    mkdir -p "${BUILD_DIR}"

    # Đặt biến môi trường
    export GOOS="${GOOS}"
    export GOARCH="${GOARCH}"
    export CGO_ENABLED=0
    export GOEXPERIMENT=jsonv2

    [ "${GOARM}" != "-" ]  && export GOARM="${GOARM}"  || unset GOARM
    [ "${GOMIPS}" != "-" ] && export GOMIPS="${GOMIPS}" || unset GOMIPS

    # Build
    local BUILD_CMD="go build -v -trimpath \
        -tags \"${BUILD_TAGS}\" \
        -ldflags \"${LDFLAGS}\" \
        -o \"${BUILD_DIR}/${BINARY_NAME}\" \
        ."

    if eval ${BUILD_CMD} 2>/dev/null; then
        # Build MIPS softfloat thêm
        if [ "${GOARCH}" = "mips" ] || [ "${GOARCH}" = "mipsle" ]; then
            GOMIPS=softfloat go build -v -trimpath \
                -tags "${BUILD_TAGS}" \
                -ldflags "${LDFLAGS}" \
                -o "${BUILD_DIR}/${APP_NAME}_softfloat" . 2>/dev/null
        fi

        copy_assets "${BUILD_DIR}"

        # Đóng gói ZIP (timestamp cố định để reproducible)
        (
            cd "${OUTPUT_DIR}"
            touch -mt "$(date +%Y01010000)" "${APP_NAME}-${SUFFIX}/"*
            zip -9qr "${APP_NAME}-${SUFFIX}.zip" "${APP_NAME}-${SUFFIX}/"
        )

        # Tính checksum
        for METHOD in md5 sha1 sha256 sha512; do
            openssl dgst -${METHOD} "${ZIP_FILE}" 2>/dev/null \
                | sed 's/([^)]*)//g' >> "${ZIP_FILE}.dgst"
        done

        # Cleanup thư mục build tạm
        rm -rf "${BUILD_DIR}"

        echo -e "${green}  ✓ ${APP_NAME}-${SUFFIX}.zip${plain}"
        return 0
    else
        echo -e "${red}  ✗ THẤT BẠI: ${SUFFIX}${plain}"
        rm -rf "${BUILD_DIR}"
        return 1
    fi
}

# ==========================================
# Main
# ==========================================
check_env

# Download dependencies
echo -e "${yellow}▶ Đang tải dependencies...${plain}"
go mod download
echo -e "${green}✓ Dependencies OK${plain}\n"

# Tạo thư mục output
mkdir -p "${OUTPUT_DIR}"

# Đếm
TOTAL=${#PLATFORMS[@]}
SUCCESS=0
FAILED=0
FAILED_LIST=()

echo -e "${blue}▶ Bắt đầu build ${TOTAL} platform...${plain}\n"

for platform in "${PLATFORMS[@]}"; do
    read -r GOOS GOARCH GOARM GOMIPS SUFFIX <<< "${platform}"

    printf "${yellow}  ▸ Building %-28s${plain}" "${SUFFIX}..."

    if build_one "${GOOS}" "${GOARCH}" "${GOARM}" "${GOMIPS}" "${SUFFIX}"; then
        ((SUCCESS++))
    else
        ((FAILED++))
        FAILED_LIST+=("${SUFFIX}")
    fi
done

# ==========================================
# Tóm tắt
# ==========================================
echo ""
echo -e "${blue}===========================================${plain}"
echo -e "${green}  Kết quả build:${plain}"
echo -e "${green}  ✓ Thành công : ${SUCCESS}/${TOTAL}${plain}"
[ ${FAILED} -gt 0 ] && echo -e "${red}  ✗ Thất bại  : ${FAILED}/${TOTAL}${plain}"
echo -e "${yellow}  📁 Output    : ${OUTPUT_DIR}/${plain}"
echo -e "${blue}===========================================${plain}"

if [ ${FAILED} -gt 0 ]; then
    echo -e "\n${red}Platform thất bại:${plain}"
    for f in "${FAILED_LIST[@]}"; do
        echo -e "${red}  - ${f}${plain}"
    done
fi

echo ""
echo -e "${green}✓ Hoàn tất! Các file ZIP nằm trong: ${OUTPUT_DIR}/${plain}"
ls -lh "${OUTPUT_DIR}"/*.zip 2>/dev/null | awk '{print "  "$NF, $5}'
