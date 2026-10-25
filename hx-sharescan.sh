#!/bin/bash
# hx-sharescan — gom 24 h log V2bX theo (uuid, IP khách): số kết nối được nhận + số lần bị chặn thiết bị (Limited).
# In ra mỗi dòng: "<uuid> <ip> <kết nối> <limited>". Panel gộp nhiều máy để tìm tài khoản dùng chung (node China).
#   hx-sharescan [giờ, mặc định 24] [--push]   (--push: gửi về panel, đọc ApiHost/ApiKey trong /etc/V2bX/config.json)
#   hx-sharescan --install    cài vào /usr/local/sbin + timer mỗi giờ (lệch ngẫu nhiên ≤ 15 phút) chạy "24 --push"
#   hx-sharescan --uninstall
if [ "${1:-}" = "--install" ]; then
    self=$(readlink -f "$0")
    [ "$self" = /usr/local/sbin/hx-sharescan ] || install -m 755 "$self" /usr/local/sbin/hx-sharescan
    cat > /etc/systemd/system/hx-sharescan.service <<'UNIT'
[Unit]
Description=HX sharescan: gui so lieu dung chung tai khoan (24 h log V2bX) ve panel
[Service]
Type=oneshot
Nice=10
ExecStart=/usr/local/sbin/hx-sharescan 24 --push
UNIT
    cat > /etc/systemd/system/hx-sharescan.timer <<'UNIT'
[Unit]
Description=HX sharescan moi gio
[Timer]
OnCalendar=hourly
RandomizedDelaySec=900
Persistent=true
[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload && systemctl enable --now hx-sharescan.timer >/dev/null 2>&1 && echo "hx-sharescan: timer moi gio da bat"
    exit 0
fi
if [ "${1:-}" = "--uninstall" ]; then
    systemctl disable --now hx-sharescan.timer >/dev/null 2>&1
    rm -f /etc/systemd/system/hx-sharescan.{service,timer}; systemctl daemon-reload; echo "hx-sharescan: da go"; exit 0
fi
H="${1:-24}"
out=$(journalctl -u V2bX --since "-${H}h" -o cat --grep "accepted|Limited" 2>/dev/null | awk '
# mawk (Debian Huawei) không hiểu {n} → bắt "|<uuid>" bằng [0-9a-f-]+ rồi kiểm độ dài 36
match($0, /\|[0-9a-f-]+/) {
    u = substr($0, RSTART + 1, RLENGTH - 1); if (length(u) != 36) next
    if (!match($0, /from (tcp:|udp:)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) next
    ip = substr($0, RSTART, RLENGTH); sub(/^from (tcp:|udp:)?/, "", ip)
    if ($0 ~ /Limited/) l[u " " ip]++; else c[u " " ip]++
    k[u " " ip] = 1
}
END { for (x in k) print x, c[x] + 0, l[x] + 0 }')
if [ "${2:-}" = "--push" ]; then
    host=$(grep -oE '"ApiHost" *: *"[^"]+"' /etc/V2bX/config.json | head -1 | sed -E 's/.*"(https?:\/\/)?([^"]+)"$/\2/')
    key=$(grep -oE '"ApiKey" *: *"[^"]+"' /etc/V2bX/config.json | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
    printf '%s\n' "$out" | gzip -c | curl -fsS --max-time 60 -X POST -H "X-Key: $key" -H "Content-Type: application/gzip" \
        --data-binary @- "https://${host}/hxshare/push.php?h=$(hostname)" && echo
else
    printf '%s\n' "$out"
fi
