#!/bin/bash
# relay.sh — chuyển tiếp một số dịch vụ từ node này sang node khác (thường là node VN)
#
# Vì sao: node đặt ở HK/SG bị TikTok trả feed rỗng (IP datacenter), OpenAI/Claude/Gemini
# từ chối HK, YouTube khoá vùng nhạc/phim VN, dichvucong/ngân hàng chặn IP nước ngoài.
# Cách: thêm outbound `relay-vn` (VLESS tới node VN bằng tài khoản relay) + luật route
# theo domain/IP, gắn `_tag: hx-relay` để chạy lại không nhân đôi. QUIC (UDP 443) tới các
# dịch vụ đó bị block để app lùi về TCP (QUIC-trong-TCP tệ cho video).
#
# Dùng: bash relay.sh            (hỏi từng mục)
#       RELAY_IP=103.5.209.20 RELAY_UUID=... RELAY_NODE=33 bash relay.sh   (không hỏi)
#       RELAY_REMOVE=1 bash relay.sh   (gỡ)
# Biến tuỳ chọn: RELAY_PORT (mặc định lấy từ panel/80), RELAY_HOST, RELAY_PATH (khi không có
#   RELAY_NODE), RELAY_SVC="tiktok,youtube,play,vn,ai" (mặc định tự dò: ai chỉ khi OpenAI bị chặn),
#   RELAY_TAG (mặc định relay-vn), CONF_DIR (/etc/V2bX).
set -u
CONF_DIR="${CONF_DIR:-/etc/V2bX}"
TAG="${RELAY_TAG:-relay-vn}"
red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; dim='\033[2m'; plain='\033[0m'
ok(){ echo -e "  ${green}✓${plain} $*"; }; warn(){ echo -e "  ${yellow}!${plain} $*"; }
die(){ echo -e "  ${red}✗${plain} $*"; exit 1; }
[ "$(id -u)" = 0 ] || die "Chạy bằng root."
command -v python3 >/dev/null || die "Cần python3 (apt/yum install python3)."
[ -f "$CONF_DIR/config.json" ] || die "Không thấy $CONF_DIR/config.json — cài V2bX trước."
[ -f "$CONF_DIR/route.json" ] || echo '{"domainStrategy":"AsIs","rules":[]}' > "$CONF_DIR/route.json"
[ -f "$CONF_DIR/custom_outbound.json" ] || echo '[{"tag":"direct","protocol":"freedom","settings":{"domainStrategy":"UseIPv4"}},{"tag":"block","protocol":"blackhole"}]' > "$CONF_DIR/custom_outbound.json"

if [ "${RELAY_REMOVE:-0}" = 1 ]; then
    TAG="$TAG" CONF_DIR="$CONF_DIR" python3 - << 'PYEOF'
import json, os
d=os.environ["CONF_DIR"]; tag=os.environ["TAG"]
r=json.load(open(d+"/route.json")); n=len(r["rules"])
r["rules"]=[x for x in r["rules"] if not str(x.get("_tag","")).startswith("hx-relay")]
json.dump(r,open(d+"/route.json","w"),indent=1)
o=json.load(open(d+"/custom_outbound.json")); m=len(o)
o=[x for x in o if x.get("tag")!=tag]
json.dump(o,open(d+"/custom_outbound.json","w"),indent=1)
print("  đã gỡ %d luật, %d outbound" % (n-len(r["rules"]), m-len(o)))
PYEOF
    systemctl restart V2bX 2>/dev/null && ok "Đã gỡ chuyển tiếp, V2bX khởi động lại." || warn "Đã gỡ trong file; tự restart V2bX."
    exit 0
fi

# ── Hỏi thông tin (bỏ qua mục đã có biến) ────────────────────────────────
ask(){ local v="$1" p="$2" d="${3:-}" x; [ -n "${!v:-}" ] && return; if [ -n "$d" ]; then read -r -p "  $p [$d]: " x; printf -v "$v" '%s' "${x:-$d}"; else read -r -p "  $p: " x; printf -v "$v" '%s' "$x"; fi; }
echo -e "  ${dim}Node VN nhận chuyển tiếp: khách ở node này sẽ ra Internet bằng IP của node đó cho các dịch vụ chọn.${plain}"
ask RELAY_IP   "IP node VN"
[ -n "${RELAY_IP:-}" ] || die "Thiếu IP."
ask RELAY_UUID "UUID tài khoản relay (tài khoản trên panel có nhóm của node VN)"
[ -n "${RELAY_UUID:-}" ] || die "Thiếu UUID."
ask RELAY_NODE "ID node VN trên panel (Enter nếu nhập tay Host/path)" ""

API_HOST=$(python3 -c 'import json;c=json.load(open("'"$CONF_DIR"'/config.json"));print(c["Nodes"][0]["ApiConfig"]["ApiHost"])' 2>/dev/null)
API_KEY=$(python3 -c 'import json;c=json.load(open("'"$CONF_DIR"'/config.json"));print(c["Nodes"][0]["ApiConfig"]["ApiKey"])' 2>/dev/null)
NET=ws; TLS=0; SNI=""; PBK=""; SID=""
if [ -n "${RELAY_NODE:-}" ]; then
    J=$(curl -fsSL --max-time 15 "${API_HOST}/api/v1/server/UniProxy/config?node_id=${RELAY_NODE}&node_type=vless&token=${API_KEY}") \
        || die "Không lấy được cấu hình node ${RELAY_NODE} từ panel (sai ID? node không phải VLESS?)."
    eval "$(echo "$J" | python3 -c '
import json,sys,shlex
c=json.load(sys.stdin); ns=c.get("networkSettings") or c.get("network_settings") or {}
hdr=ns.get("headers") or {}
print("RELAY_PORT_P=%s" % shlex.quote(str(c.get("server_port",""))))
print("NET=%s" % shlex.quote(c.get("network","tcp") or "tcp"))
print("TLS=%s" % shlex.quote(str(c.get("tls",0))))
print("RELAY_HOST_P=%s" % shlex.quote(hdr.get("Host") or ns.get("host") or (c.get("tls_settings") or {}).get("server_name") or ""))
print("RELAY_PATH_P=%s" % shlex.quote(ns.get("path","") or ""))
ts=c.get("tls_settings") or {}
print("SNI=%s" % shlex.quote(ts.get("server_name","") or ""))
print("PBK=%s" % shlex.quote(ts.get("public_key","") or ""))
print("SID=%s" % shlex.quote(ts.get("short_id","") or ""))
')"
    RELAY_PORT="${RELAY_PORT:-$RELAY_PORT_P}"; RELAY_HOST="${RELAY_HOST:-$RELAY_HOST_P}"; RELAY_PATH="${RELAY_PATH:-$RELAY_PATH_P}"
    ok "Panel: node ${RELAY_NODE} · ${NET} · cổng ${RELAY_PORT} · tls ${TLS} · Host ${RELAY_HOST:-—} · path ${RELAY_PATH:-—}"
else
    ask RELAY_PORT "Cổng" "80"
    ask RELAY_HOST "Host header (WS)" ""
    ask RELAY_PATH "Path (WS)" "/"
fi
if [ "$TLS" = 2 ]; then
    [ -z "$PBK" ] && ask PBK "Reality public key"
    [ -z "$SID" ] && ask SID "Reality short id" ""
    [ -z "$SNI" ] && ask SNI "Reality server name" "www.apple.com"
fi

# Dịch vụ: tự dò AI (OpenAI chặn HK) nếu không chỉ định
if [ -z "${RELAY_SVC:-}" ]; then
    RELAY_SVC="tiktok,youtube,play,vn"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://api.openai.com/v1/models 2>/dev/null)
    if [ "$code" = 403 ]; then RELAY_SVC="$RELAY_SVC,ai"; warn "OpenAI trả 403 từ máy này → relay cả ChatGPT/Claude/Gemini"; else ok "OpenAI vào được trực tiếp (HTTP ${code:-?}) → không relay AI"; fi
fi
echo -e "  Dịch vụ chuyển tiếp: ${yellow}${RELAY_SVC}${plain}"

# Kiểm cổng node VN tới được không
if timeout 5 bash -c "</dev/tcp/${RELAY_IP}/${RELAY_PORT}" 2>/dev/null; then ok "Tới được ${RELAY_IP}:${RELAY_PORT}"; else warn "Không nối được ${RELAY_IP}:${RELAY_PORT} — kiểm firewall/nhà mạng (Hanoi Telecom chỉ mở 22/80/443)"; fi

cp -a "$CONF_DIR/route.json" "$CONF_DIR/route.json.bak_relay_$(date +%Y%m%d_%H%M%S)"
cp -a "$CONF_DIR/custom_outbound.json" "$CONF_DIR/custom_outbound.json.bak_relay_$(date +%Y%m%d_%H%M%S)"

export CONF_DIR TAG RELAY_IP RELAY_PORT RELAY_UUID NET TLS RELAY_HOST RELAY_PATH SNI PBK SID RELAY_SVC
python3 - << 'PYEOF'
import json, os
E=os.environ; d=E["CONF_DIR"]; tag=E["TAG"]
SVC=[s.strip() for s in E["RELAY_SVC"].split(",") if s.strip()]
L = {
 "tiktok": {"domain": ["domain:tiktok.com", "domain:tiktokv.com", "domain:tiktokcdn.com", "domain:tiktokcdn-us.com", "domain:tiktokcdn-eu.com", "domain:tiktokv.us", "domain:tiktokv.eu", "domain:tiktokglobalshop.com", "domain:tiktokmusic.app", "domain:tiktokw.us", "domain:byteoversea.com", "domain:byteoversea.net", "domain:byteglb.com", "domain:bytedapm.com", "domain:bytegecko.com", "domain:ibytedtos.com", "domain:ibyteimg.com", "domain:ipstatp.com", "domain:isnssdk.com", "domain:sgsnssdk.com", "domain:muscdn.com", "domain:musical.ly", "domain:ttwstatic.com", "domain:tiktokstaticb.com", "domain:ttlivecdn.com", "domain:ttoverseaus.net", "domain:byteintl.com", "domain:bytefcdn-oversea.com", "domain:bytecdn.cn", "domain:pstatp.com"],
            "ip": ["101.45.0.0/16", "71.18.0.0/16", "103.136.220.0/23", "103.136.223.0/24", "130.44.212.0/24", "130.44.214.0/23", "139.177.225.0/24", "139.177.227.0/24", "139.177.233.0/24", "139.177.235.0/24", "139.177.238.0/24", "139.177.240.0/21", "139.177.248.0/24", "147.160.176.0/23", "147.160.180.0/24", "147.160.182.0/24", "147.160.184.0/24", "147.160.190.0/24", "180.240.234.0/23", "192.64.15.0/24", "199.103.24.0/23", "202.52.240.0/21"]},
 "youtube": {"domain": ["domain:youtube.com", "domain:googlevideo.com", "domain:ytimg.com", "domain:youtu.be", "domain:youtube-nocookie.com", "domain:ggpht.com", "domain:youtubei.googleapis.com", "domain:youtube.googleapis.com", "domain:ytimg.l.google.com", "domain:play.googleapis.com", "domain:play-fe.googleapis.com", "domain:android.clients.google.com", "domain:play.google.com", "domain:gvt1.com", "domain:play-lh.googleusercontent.com", "domain:play-apps-features.googleusercontent.com"]},
 "play": {"domain": ["domain:play.googleapis.com", "domain:play-fe.googleapis.com", "domain:android.clients.google.com",
                     "domain:play.google.com", "domain:gvt1.com", "domain:play-lh.googleusercontent.com",
                     "domain:play-apps-features.googleusercontent.com"]},
 "ai": {"domain": ["domain:openai.com", "domain:chatgpt.com", "domain:oaistatic.com", "domain:oaiusercontent.com", "domain:sora.com", "domain:anthropic.com", "domain:claude.ai", "full:gemini.google.com", "domain:generativelanguage.googleapis.com", "full:aistudio.google.com"],
        "ip": ["104.18.32.47", "172.64.155.209", "104.18.39.85", "172.64.148.171", "104.18.41.241", "172.64.146.15", "162.159.140.245", "172.66.0.243", "104.18.41.158", "172.64.146.98", "104.18.33.45", "172.64.154.211", "104.18.39.16", "172.64.148.240"]},
 "vn": {"domain": ["domain:vn", "domain:momo.vn", "domain:zalopay.com", "domain:vnpayqr.com", "domain:napas.com.vn", "domain:viettel.com", "domain:viettelpay.com", "domain:vtcpay.com", "domain:payoo.com", "domain:shopeepay.com", "domain:vpbank.com", "domain:vietcombank.com", "domain:bidv.com", "domain:techcombank.com", "domain:mbbank.com", "domain:acb.com", "domain:tpb.com", "domain:vib.com"]},
}
# youtube + play phải cùng lối ra: link tải APK của Play ký theo IP và nằm trên googlevideo.com
if "youtube" in SVC and "play" not in SVC: SVC.append("play")
unknown=[s for s in SVC if s not in L]
if unknown: raise SystemExit("dịch vụ không biết: %s (có: %s)" % (unknown, ",".join(L)))
dom=[]; ips=[]
for s in SVC:
    dom += [x for x in L[s].get("domain",[]) if x not in dom]
    ips += [x for x in L[s].get("ip",[]) if x not in ips]

# outbound
o=json.load(open(d+"/custom_outbound.json"))
o=[x for x in o if x.get("tag")!=tag]
user={"id":E["RELAY_UUID"],"encryption":"none"}
ss={"network":E["NET"],"sockopt":{"tcpFastOpen":False,"tcpNoDelay":True,"tcpKeepAliveInterval":30}}
if E["NET"]=="ws":
    ss["wsSettings"]={"path":E["RELAY_PATH"] or "/","headers":{"Host":E["RELAY_HOST"]} if E["RELAY_HOST"] else {}}
elif E["NET"] in ("xhttp","splithttp"):
    ss["network"]="xhttp"; ss["xhttpSettings"]={"path":E["RELAY_PATH"] or "/","host":E["RELAY_HOST"],"mode":"packet-up"}
if E["TLS"]=="1":
    ss["security"]="tls"; ss["tlsSettings"]={"serverName":E["RELAY_HOST"] or E["SNI"],"fingerprint":"chrome"}
elif E["TLS"]=="2":
    user["flow"]="xtls-rprx-vision"
    ss["security"]="reality"; ss["realitySettings"]={"serverName":E["SNI"],"fingerprint":"chrome","publicKey":E["PBK"],"shortId":E["SID"]}
o.append({"tag":tag,"protocol":"vless","settings":{"vnext":[{"address":E["RELAY_IP"],"port":int(E["RELAY_PORT"]),"users":[user]}]},
          "streamSettings":ss,"mux":{"enabled":False}})
json.dump(o,open(d+"/custom_outbound.json","w"),indent=1)

# route: gỡ luật cũ cùng tag, chèn sau khối UDP ở đầu (block QUIC phải đứng trước relay)
r=json.load(open(d+"/route.json")); rules=[x for x in r["rules"] if not str(x.get("_tag","")).startswith("hx-relay")]
new=[]
if dom: new.append({"_tag":"hx-relay","type":"field","network":"udp","port":"443","domain":dom,"outboundTag":"block"})
if ips: new.append({"_tag":"hx-relay","type":"field","network":"udp","port":"443","ip":ips,"outboundTag":"block"})
if dom: new.append({"_tag":"hx-relay","type":"field","domain":dom,"outboundTag":tag})
if ips: new.append({"_tag":"hx-relay","type":"field","ip":ips,"outboundTag":tag})
pos=0
for i,x in enumerate(rules):
    if x.get("network")=="udp" and x.get("outboundTag") in ("block","direct"): pos=i+1
r["rules"]=rules[:pos]+new+rules[pos:]
json.dump(r,open(d+"/route.json","w"),indent=1)
print("  luật relay: %d domain, %d dải IP → %s (chèn ở vị trí %d/%d)" % (len(dom),len(ips),tag,pos,len(r["rules"])))
PYEOF
[ $? -eq 0 ] || die "Ghi cấu hình thất bại (xem lỗi trên), file cũ còn ở *.bak_relay_*"

# config.json phải nạp route/outbound
python3 - "$CONF_DIR" << 'PYEOF'
import json,sys
d=sys.argv[1]; c=json.load(open(d+"/config.json")); ch=False
for core in c.get("Cores",[]):
    if core.get("Type")=="xray":
        for k,f in (("RouteConfigPath","route.json"),("OutboundConfigPath","custom_outbound.json")):
            if not core.get(k): core[k]=d+"/"+f; ch=True
if ch: json.dump(c,open(d+"/config.json","w"),indent=2); print("  đã thêm RouteConfigPath/OutboundConfigPath vào config.json")
PYEOF

if systemctl restart V2bX 2>/dev/null; then
    sleep 3
    if systemctl is-active V2bX >/dev/null; then
        ok "V2bX chạy lại với outbound ${TAG} → ${RELAY_IP}:${RELAY_PORT}"
        echo -e "  ${dim}Kiểm: journalctl -u V2bX -f | grep -- '-> ${TAG}'   · gỡ: RELAY_REMOVE=1 bash relay.sh${plain}"
    else
        die "V2bX không lên — journalctl -u V2bX -n 30; khôi phục: cp ${CONF_DIR}/route.json.bak_relay_* ${CONF_DIR}/route.json"
    fi
else
    warn "Không restart được qua systemd — tự khởi động lại V2bX."
fi
