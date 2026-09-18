#!/bin/bash
# Ngắt các kết nối TCP vào cổng node đã im (không nhận byte nào) quá IDLE giây.
# Lý do: phiên UDP-over-VLESS bị route block thì Xray không đóng kết nối vào, app khách
# giữ socket mãi -> hàng nghìn ESTABLISHED chết -> RAM vượt GOMEMLIMIT -> GC ăn 100% CPU
# (CHINA 1, 17/09/2026). Dùng `ss -K` (kernel CONFIG_INET_DIAG_DESTROY) nên Xray nhận lỗi đọc
# và tự dọn goroutine/bộ nhớ, không cần restart.
IDLE=${IDLE:-900}
PORTS=$(ss -tlnpH 2>/dev/null | grep '"V2bX"' | awk '{split($4,a,":"); print a[length(a)]}' | sort -u)
[ -z "$PORTS" ] && exit 0
killed=0; total=0
for p in $PORTS; do
  while read -r peer idle; do
    total=$((total+1))
    [ -z "$peer" ] && continue
    if [ "$idle" -gt $((IDLE*1000)) ]; then
      ss -K dst "$peer" >/dev/null 2>&1 && killed=$((killed+1))
    fi
  done < <(ss -tniH state established "( sport = :$p )" | paste - - | awk '{peer=$4; idle=""; for(i=1;i<=NF;i++) if($i ~ /^lastrcv:/){split($i,x,":"); idle=x[2]} if(idle!="") print peer, idle}')
done
[ "$killed" -gt 0 ] && logger -t v2bx-reaper "ngắt $killed/$total kết nối im > ${IDLE}s"
exit 0
