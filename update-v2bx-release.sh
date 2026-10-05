#!/bin/bash
# Nâng V2bX trên 1 máy node lên bản mới nhất của GitHub Releases, hỏng thì tự lùi (chạy bằng root):
#   sshp.py <ip> <user> <pass> < update-v2bx-release.sh   ·   jump_run.py ... (máy sau hx-ddos)
# Tải lệnh hyx mới nhất rồi gọi `hyx update` — mọi kiểm tra (đủ cổng, node đã lên, không panic) + tự lùi nằm ở đó.
# Ép cài lại cùng phiên bản: đặt FORCE=1.
set -u
SCRIPT_URL="${V2BX_SCRIPT_URL:-https://raw.githubusercontent.com/Tubetna/hypex-x/main}"
if curl -fsSL --connect-timeout 15 -o /usr/local/bin/hyx.new "${SCRIPT_URL}/v2bx.sh" && bash -n /usr/local/bin/hyx.new; then
    install -m 755 /usr/local/bin/hyx.new /usr/local/bin/hyx
    ln -sf /usr/local/bin/hyx /usr/local/bin/v2bx; ln -sf /usr/local/bin/hyx /usr/local/bin/hypex-x
fi
rm -f /usr/local/bin/hyx.new
echo "== $(hostname)"
if [ "${FORCE:-0}" = 1 ]; then HYX_NOANIM=1 /usr/local/bin/hyx update --force; else HYX_NOANIM=1 /usr/local/bin/hyx update; fi
