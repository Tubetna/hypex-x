# Ghi chú kỹ thuật

Những thứ mất công nhất mới tìm ra, ghi lại để lần sau khỏi đào lại.
Số dòng theo trạng thái ngày **01/09/2026**, sửa code thì kiểm lại.

---

## 1. Muốn thêm giao thức thì sửa ở đâu

Panel có **11** loại, node chỉ dựng inbound được **8**. Bốn loại còn lại — SOCKS,
HTTP, Naive, Mieru — muốn thêm phải viết Go, **không phải sửa script cài**.
Script đang từ chối bốn loại đó là đúng, và báo lỗi ngay lúc cài thay vì để node
chết lúc khởi động.

### Bốn chỗ phải sửa

| File | Việc |
|---|---|
| `api/panel/panel.go` (~dòng 59-73) | Thêm chuỗi vào switch chấp nhận `node_type`, không có là trả `unsupported Node type` |
| `api/panel/node.go` | Parse `protocol_settings` panel gửi xuống, thêm struct vào `NodeInfo` |
| `core/sing/node.go` | Thêm `case` dựng `option.XxxInboundOptions` — mẫu ngắn nhất là `tuic` và `anytls` (~dòng 338-357) |
| `core/sing/user.go` | Thêm case ở **hai chỗ**: thêm user (~dòng 30-115) và xoá user (~dòng 180-200) |

### Từng loại khả thi tới đâu

| | Nhân sing-box `v1.13` | Panel sinh link cho khách | Đánh giá |
|---|---|---|---|
| **SOCKS** | ✅ `protocol/socks` | ✅ `SingBox.php` · `ClashMeta.php` | Làm được, ~nửa buổi |
| **HTTP** | ✅ `protocol/http` | ✅ `SingBox.php` · `ClashMeta.php` | Làm được, ~nửa buổi |
| **Naive** | ✅ `protocol/naive` | ❌ **không generator nào** | Phải viết thêm phía panel |
| **Mieru** | ❌ **không có** | ✅ chỉ `ClashMeta.php` | Cần thư viện mới + core thứ 4 |

Kiểm chứng: thư mục `protocol/` của sing-box có `socks`, `http`, `naive` nhưng
**không có `mieru`**; `grep -ci mieru go.sum` trả về **0**.

### Chỗ tưởng khó mà không khó

SOCKS/HTTP/Naive xác thực bằng **username + password**, khác vmess (uuid) hay
trojan (password). Nhưng panel đã quyết sẵn ánh xạ trong `SingBox.php`
(`buildSocks`, `buildHttp`): **`username = password = uuid`**. Cứ theo đó là khớp
với link khách nhận được. `ClashMeta.php::buildMieru` cũng vậy.

### Vì sao Mieru đắt

Không có trong sing-box lẫn xray. Phải thêm dependency `github.com/enfein/mieru`,
dựng nguyên một core thứ tư như `core/hy2/`, rồi build lại 24 platform và kiểm thử
từ đầu. Mà khách chỉ dùng được nếu app là Clash.Meta / mihomo — v2rayN,
Shadowrocket, sing-box, Loon, QuantumultX, Surge, Stash đều **không có** node mieru
trong link.

### Đáng làm hơn

Trước khi thêm giao thức mới, kiểm tra **VLESS + Reality** đã cấu hình đúng chưa.
Nó không cần tên miền, vân tay TLS tốt, panel sinh link cho **cả 7** loại client, và
node **đã chạy được rồi** — không phải viết một dòng Go nào.

Reality cấu hình sai thì tụt về TLS thường mà **không báo lỗi gì** — vẫn tưởng đang
chạy Reality.

---

## 2. Node dựng được gì (đã đối chiếu code, không phải đoán)

| Thành phần | Ở đâu |
|---|---|
| Security: `None=0` `Tls=1` `Reality=2` | `api/panel/node.go:17-21` |
| Reality — nhân xray | `core/xray/inbound.go:115-142` |
| Reality — nhân sing | `core/sing/node.go:90-108` |
| XTLS Vision (`flow`) | `core/xray/user.go:107` → `core/xray/vmess.go:44` |
| XHTTP / SplitHTTP | `core/xray/inbound.go:239` |
| Transport | tcp · ws · grpc · httpupgrade · xhttp |
| VLESS Encryption hậu lượng tử `mlkem768x25519plus` | `core/xray/inbound.go:178` |

Loại nào chạy nhân nào:

- `core/xray/inbound.go:26-41` → vmess, vless, trojan, shadowsocks
- `core/sing/node.go` → **cả 8 loại** (superset)
- `core/hy2/` → riêng hysteria2

---

## 3. Giới hạn thiết bị

Chuỗi hoạt động (từ **v1.0.2**, 11/09/2026):

```
Node đếm IP có kết nối THẬT → POST /api/v1/server/UniProxy/alive
                    ↓  panel lưu Redis, TTL 300s, IP phải sống ≥2 lượt mới tính
Node lấy về ← GET  /api/v1/server/UniProxy/alivelist
                    {"alive": {uid: số máy}, "alive_ips": {uid: [ip đã biết]}}
                    ↓
      chặn khi:  deviceLimit <= alive[uid]  VÀ  ip ∉ alive_ips[uid]
                                                (limiter/limiter.go: overDeviceLimit)
```

### Vì sao phải có `alive_ips` — lỗi "lâu lâu mất mạng vài phút rồi tự có lại"

Bản cũ chỉ so `deviceLimit <= alive`. Khách có đúng 2 máy (= limit 2) mà điện
thoại **đổi node** (app URLTest tự nhảy, hoặc khách bấm) thì node mới thấy IP
"lạ" → hỏi panel → 2 → `2 <= 2` → **cắt kết nối**, dù chính máy đó là 1 trong 2
máy đang được đếm. Phải đợi node cũ báo IP rớt (≤60 s) + node mới kéo alivelist
(≤60 s) → tối đa ~2 phút. App báo `EOF` trên **mọi** node cùng lúc vì alivelist là
toàn hệ thống, nên trông y hệt node chết. Gặp thật 11/09/2026 với 2 khách CHINA.

Giờ panel trả thêm danh sách IP; IP đã có ở node nào thì không phải máy mới.
Panel cũ không trả `alive_ips` → node hành xử như trước (test `TestOldPanelStillEnforces`).

### Bấm "đo độ trễ" không tính là thiết bị

`limiter.MarkReal()` được gọi sau `CheckLimit` với host đích. IP mà trong một lượt
báo cáo **chỉ** nối tới máy chủ đo độ trễ (`www.gstatic.com`, `cp.cloudflare.com`,
`captive.apple.com`, … — bảng `probeHosts`) thì `GetOnlineDevice()` **không báo lên
panel**. Vẫn nhớ ở `OldUserOnline` để lượt sau không bị coi là IP lạ.
Muốn thêm host thì sửa `probeHosts` — đừng thêm `www.google.com`, khách TQ dùng thật.

### Log chặn giờ nhìn thấy được

Dòng `Limited <email> by conn or ip, from <ip>` trước ở mức Info, mà core xray chạy
mức warning nên **không bao giờ ra log** — chặn im lặng, nhìn journal tưởng node
khoẻ. Đã nâng lên Warning (xray) / Error (sing). `CheckLimit` chạy **trước** dòng
`accepted` (dispatcher `routedDispatch`), nên kết nối bị chặn không có cả dòng
accepted — khoảng trống trong log của một khách chính là dấu vết.

### Còn treo: CGNAT đổi IP

Nhà mạng di động TQ cấp IP khác nhau cho từng luồng trong cùng dải /24 (đã thấy user
35642 có `222.188.99.85/.22/.84` cùng lúc). Một điện thoại thành 2–3 "máy". IP mới
tinh thì `alive_ips` không cứu được. Cách chữa hợp lý là panel khử trùng theo /24
(IPv4) và /64 (IPv6) thay vì theo IP — chưa làm, cần chủ quyết định vì nó nới limit
cho hai máy cùng dải.

### Cấu hình chết — đừng mất công đặt

`conf/limit.go` khai báo `IPLimit` (khoá JSON là `DeviceLimit`), `ConnLimit`,
`EnableRealtime`, `EnableIpRecorder`, `EnableDynamicSpeedLimit`. Grep toàn bộ code
Go: **không một dòng nào đọc chúng**. Parse xong rồi nằm im.

Đặt `"DeviceLimit": 3` trong `config.json` của node **không có tác dụng gì**. Số
thiết bị đặt trong **panel**, theo Gói cước hoặc theo từng User.

Panel cũng có khoá chết tương tự: `device_limit_mode` xuất hiện trong
`ConfigController` và `ConfigSave` nhưng không nơi nào đọc để quyết định gì.

### `DeviceOnlineMinTraffic` không lọc được ping

`node/user.go:29-41` xây `nocountUID` **khoá theo UID**, không phải theo IP. Khách
đang tải nặng trên máy chính thì UID không nằm trong danh sách bỏ qua. Việc lọc
ping theo IP giờ do `MarkReal`/`probeHosts` đảm nhiệm (ở trên); ngưỡng này chỉ còn
tác dụng khi khách hoàn toàn không có traffic.

---

## 4. Bẫy đã dính, đừng dính lại

**Đường tới AWS Việt Nam rớt gói 1500 byte, không ICMP (12/09/2026).** Node Hanoi
Telecom `103.5.209.17/.20` → AWS Local Zone VN (`166.117.0.0/16`) và Global Accelerator
(`75.2.x`, `15.197.x`) có PMTU **1482**; gói full-size rớt im, kernel không nhận
frag-needed → TCP retransmit tới chết. Triệu chứng: **Xanh SM** (`api-ub.vn.gsm-api.net`)
treo ở logo, log V2bX chỉ thấy `accepted >> direct` lặp 4–5 lần mỗi 15–40 s, `curl GET`
từ node vẫn 404 trong 0,1 s (gói nhỏ qua được) nên trông như node khoẻ. Tái hiện bằng
`curl -X POST --data-binary @3KB https://api-ub.vn.gsm-api.net/` → treo 8 s. Sửa: bộ cài
bước 6 / menu 20 (`hyx`) ép **MSS 1400 ở cả INPUT/OUTPUT/FORWARD** + `tcp_mtu_probing=1`.
Rule chỉ ở OUTPUT **không đủ** — nó ép cỡ gói server gửi về, còn cỡ gói node gửi đi theo
MSS trong SYN-ACK của server (đo thật: OUTPUT thôi vẫn còn 3,3 s). Muốn biết app khách
gọi domain nào: `tcpdump -i any udp port 53` trên node — xray resolve hộ nên thấy tên miền.

**`ETXTBSY` khi cài đè.** Linux không cho ghi lên file đang thực thi. Cài lại trên
máy đã chạy V2bX là `install`/`cp` chết giữa chừng. Phải dừng dịch vụ rồi `rm -f`
binary trước — `rm` chỉ cắt tên file, tiến trình cũ vẫn giữ inode nên không sập.

**CRLF giết script.** File `.sh` có `\r` thì Linux báo `bad interpreter` hoặc
`$'\r': command not found`. Editor trên Windows rất hay ghi CRLF. `.gitattributes`
đang ép `*.sh text eol=lf` — đừng bỏ. Kiểm bằng `git show HEAD:install.sh | tr -dc
'\r' | wc -c`, phải ra **0** (kiểm trên **blob**, không phải file trên đĩa).

**`.ps1` thì ngược lại, phải có UTF-8 BOM.** Không BOM thì PowerShell 5.1 đọc theo
codepage ANSI, chữ tiếng Việt vỡ và **script không parse nổi** — từng ra 9 lỗi cú
pháp mà nhìn code thì không thấy sai gì.

**`curl -s` không có `-f`.** HTTP 4xx/5xx vẫn exit 0 và trả chuỗi rỗng. Lấy IP
public kiểu đó thì `CN=` của chứng chỉ trống, openssl từ chối, cài dừng. Luôn dùng
`-fsS`.

**Route mới không ăn cho tới khi reload Octane.** Panel chạy Swoole/Octane, worker
giữ bảng route và code PHP trong RAM. Sửa file xong vẫn phải
`php artisan octane:reload`, không thì worker chạy code cũ.

**`gh` pipe qua `tail` che mất lỗi.** `gh release create ... | tail` trả exit code
của `tail`, nên lệnh hỏng vẫn hiện `exit 0`. Đừng pipe, hoặc in `${PIPESTATUS[0]}`.

**Tag cũ của repo cũ.** Sau khi làm lại lịch sử, tag `v1.0.0`/`v1.0.1` còn trỏ vào
commit đã bỏ. `gh release create` đòi push tag đó — push là **kéo ngược 833MB
history cũ về**. Phải `git tag -d` rồi tạo release bằng `--target main`.

**VLESS từng bị gộp vào V2ray.** Menu cũ ghi "V2ray (VMess/VLESS)" chung một mục,
mà `api/panel/panel.go:61` đổi `v2ray` → `vmess`. Kết quả: chọn VLESS thì node gửi
lên panel `node_type=vmess`, sai loại. Giờ tách hai mục riêng.

**TLS1.3 + h2 CHƯA ĐỦ để làm `dest` cho Reality.** `www.microsoft.com` có đủ cả
hai mà vẫn không dùng được — nó đứng sau CDN xử lý bắt tay theo cách Reality không
chuyển tiếp được. Triệu chứng rất dễ đánh lừa: client **thêm được, bắt tay xong,
nhưng không đi được byte nào**, app báo `io: read/write on closed pipe`.

Phân biệt bằng đúng một chữ trong log Xray (phải bật `"Level": "debug"` cho nhân
xray trong `/etc/V2bX/config.json`):

| Log | Nghĩa |
|---|---|
| `authentication failed or validation criteria not met` | Sai `pbk` hoặc `sid` — lỗi phía khoá |
| `handshake did not complete successfully` | **Qua được xác thực rồi**, chết ở bước chuyển tiếp tới `dest` |

Kiểm `dest` bằng `openssl s_client` là **vô nghĩa** — nó chỉ chứng minh openssl nói
chuyện được với site đó, không chứng minh Reality chuyển tiếp nổi một ClientHello
vân tay Chrome. Cách kiểm đúng: dựng Xray client thật nối vào chính node.

`dl.google.com` chạy tốt. Đổi `dest` là phải đổi luôn `sni` trong link của khách.

**uTLS bắt buộc với Reality.** Tắt công tắc uTLS trong panel thì `Helper::getTlsFingerprint()`
trả `null` → không ghi `fp` vào link → client họ sing-box (NekoBox, Hiddify, Karing)
báo `uTLS is required by reality client` (`sing-box/common/tls/reality_client.go:56`).
Client Xray thì thường tự mặc định `chrome`, nhưng đó là may chứ không phải thiết kế.

**Sửa node trong giao diện admin làm rụng group.** Lưu form một lần là `group_ids`
chỉ còn group đang chọn trong ô. Node từng phục vụ 1224 khách tụt xuống 317, log ghi
`Đã xoá 906 khách`. Khách không thuộc group còn lại thì **node biến mất khỏi link
đăng ký** — nhìn giống lỗi kết nối nhưng không phải.

---

**Node không có IPv6 thì phải sniff QUIC (v1.0.4, 11/09/2026).** Triệu chứng: khách
Shadowrocket/iPhone "không load được ảnh Facebook", còn Hiddify/sing-box thì bình
thường. iPhone trên mạng di động VN nhận AAAA, app Facebook đi HTTP/3 (QUIC), Shadowrocket
chuyển nguyên **IP đích IPv6 + UDP 443** xuống node. Xray gốc chỉ sniff `http`+`tls`
nên TCP còn được đổi sang tên miền, **UDP thì không** → node không có IPv6 → gói rơi im
lặng, không một dòng log (`failed`/`unreachable` đều **0**). Soi bằng
`journalctl -u V2bX | grep -c "accepted udp:\["` — số này >0 là đang dính.
Sửa hai chỗ: `core/xray/inbound.go` thêm `"quic"` vào `DestOverride`, và
`config.json` → `Options.XrayOptions = {"EnableDNS": true, "DNSType": "UseIPv4"}`
cho freedom chỉ chọn IPv4. Kiểm nhanh (không cần iPhone): xray client + `dokodemo-door`
UDP trỏ tới IPv6 của `scontent.*.fbcdn.net`, rồi `curl --http3-only` qua nó —
trước sửa **timeout 12 s**, sau sửa **200 / 0,28 s**. Hiddify/sing-box không dính vì
template dùng fake-ip nên app không bao giờ thấy AAAA.

**Cert phải mang tên ORIGIN, không phải tên Host header (11/09/2026).** Node sau CloudFront có
hai tên: `cloudaz1.hypexcloud.com` (Host header WS, bật proxy Cloudflare) và
`cloudvip1az.hypexcloud.com` (origin, DNS-only → IP máy). CloudFront bắt tay TLS với tên
**origin** nên cert phải là `cloudvip1az`. Nhập nhầm `cloudaz1` → HTTP-01 hỏng (xác thực rơi
vào Cloudflare) → bộ cài cũ lặng lẽ tạo cert tự ký → **502 ở 443 mà cổng 80 vẫn chạy**.
Từ commit `8d58a57`: `check_cert_domain` kiểm trước, in rõ "đang proxy Cloudflare / trỏ máy
khác / không phân giải", không cho rơi về tự ký nếu không tự tay chọn; acme.sh có
`SAVED_CF_Token` thì tự dùng DNS-01. Đổi máy node: **DNS `cloudvip1az` → IP mới, rồi cấp cert
trên máy mới** (token CF nằm trong `/root/.acme.sh/account.conf` máy cũ, copy sang nhớ bỏ CRLF).

**`acme.sh --install-cert` trả exit 1 không có nghĩa cert hỏng (v1.0.5, 11/09/2026).** acme chạy
`--reloadcmd` ngay lúc install-cert; máy cài mới chưa có service V2bX → `systemctl restart` lỗi → exit 1
dù cert/key đã chép xong. Bộ cài cũ coi là "cert hỏng" và dừng — máy `103.5.209.20` bị vậy khi DNS
`cloudbasicz` đã trỏ sang, khách node 30/33 mất mạng ~10 phút. Từ `9af8a7a`: reload có `|| true`, kết quả
kiểm bằng `cert_key_match` (hai file không rỗng + cùng public key). Và **đổi DNS sang máy mới chỉ sau
khi V2bX máy mới đã chạy**.

**Panel sập là node chết luôn, không tự dậy (v1.0.6, 12/09/2026).** Panel `43.133.42.80` (2 GB) bị OOM giết
MariaDB → API trả 500 → V2bX "Khởi chạy các Node thất bại" rồi **thoát mã 0** (`return` trong `cmd/server.go`)
→ systemd `Restart=on-failure` không khởi động lại → node 25/26 chết cho tới khi bật tay. Sửa: thoát `os.Exit(1)`
+ unit `Restart=always RestartSec=10s` (máy đang chạy: drop-in `/etc/systemd/system/V2bX.service.d/restart.conf`).
Gốc bên panel: Horizon master bị giết để lại worker mồ côi, php-fpm trần 30 con × 55 MB, đã siết xuống
(fpm 12, Horizon 3/2/2, swap 2 GB) — 2 GB RAM vẫn là quá ít cho 36k user + 25 node.

**Sniff SNI đè tên miền khách đã gửi → Facebook "lúc load ảnh lúc không" (v1.0.8, 14/09/2026).**
App Facebook/Instagram nối tới `scontent.fhan12-1.fna.fbcdn.net` (cache FB tại VN) nhưng gửi **SNI
`scontent.xx.fbcdn.net`** (kiểu gộp kết nối của FB; `video.fhan12-1` → `video.xx` cũng vậy). Xray sniff
`tls` rồi **đè đích bằng SNI** → phân giải `*.xx.fbcdn.net` qua 1.1.1.1 → **edge Hong Kong `57.144.98.x`**
(TTL 3 s) → edge trả cert `*.fbcdn.net`, **không khớp** `scontent.fhan12-1.fna.fbcdn.net` (wildcard chỉ khớp
một nhãn) → app huỷ TLS ngay khi nhận cert rồi thử lại 4–5 lần/giây: log node ra **100–300 dòng
`accepted tcp:scontent…` mỗi phút từ một user** ("bão"), mỗi kết nối chỉ ~4 KB downlink, khách thấy
ảnh/video xoay. Kết nối mà app gửi SNI = fhan12-1 thì khoẻ, nên chỉ ~15% khách dính (tuỳ bản app). Máy node
cũ dùng resolver ISP nên `*.xx` ra cache VN, đè đích vô hại — sang máy mới dùng 1.1.1.1 (11/09) mới lộ.
Nhìn ra bằng log Xray mức **info** (ghi ra file qua `ErrorPath`, journald sẽ rate-limit): mỗi phiên
`received request for tcp:scontent.fhan12-1…` + `sniffed domain: scontent.xx…` + `dialing to 57.144.98.128`
+ `connection ends > … websocket: close 1000 (normal)` sau **0,16 s**. Sửa: `shouldOverride` trong
`core/xray/app/dispatcher/default.go` — **client đã gửi tên miền thì không đè**, chỉ đè khi client gửi IP
(vẫn giữ được fix IPv6 literal 11/09). Sau vá: scontent từ 30–300 xuống 4–16 kết nối/phút, hết bão.
Bài học đo: `accepted` nhiều ≠ node khoẻ; `curl` từ node tới FB luôn 200 vì curl gửi SNI đúng tên.
Đừng `--resolve` ép SNI fna vào IP edge rồi kết luận "TLS treo" — đó là curl từ chối cert (exit 60).

**Không có `DnsConfigPath` là Xray hỏi DNS cho từng kết nối (14/09/2026).** Máy `.17` thiếu khoá này (`.20`
có) → resolver `localhost`, không cache → **40 truy vấn/s** tới 1.1.1.1 (A + AAAA), `.20` chỉ 2/s. Bộ cài
phải luôn đặt `"DnsConfigPath": "/etc/V2bX/dns.json"`; kiểm nhanh: `tcpdump -ni ens3 udp port 53 | wc -l`.

## 5. Vị trí file — đặt sai là hỏng ngầm

Geo data phải nằm cùng `config.json`, **không phải cùng binary**:

- `conf/xray.go:34` — `AssetPath` mặc định `/etc/V2bX/`
- `core/xray/xray.go:71` — `os.Setenv("XRAY_LOCATION_ASSET", c.AssetPath)`
- nhân sing đọc `geoip.db` / `geosite.db` từ **thư mục làm việc**, cũng là `/etc/V2bX`

Đặt sai chỗ thì mọi rule `geoip:` / `geosite:` từ panel đều lỗi, mà node vẫn khởi
động bình thường nên rất khó nhận ra.

Riêng hysteria2 tự cứu được: `core/hy2/geoloader.go` tự tải geo từ jsdelivr khi
thiếu. Xray và sing thì **không**.

Trên Windows `AssetPath` mặc định `/etc/V2bX/` là vô nghĩa — `install.ps1` phải ghi
đè trỏ về thư mục cài.

---

## 6. Vài thứ khác đáng nhớ

**Config nhận cả hai kiểu.** `conf/node.go:74-99` đọc được cả kiểu lồng
(`ApiConfig` / `Options`) lẫn kiểu phẳng — không lo chọn sai.

**Panel đổi tên loại.** `Server.php` TYPE_ALIASES map `hysteria2` → `hysteria` và
`v2ray` → `vmess`. Nên panel chỉ có **một** mục "Hysteria" cho cả v1 và v2, phiên
bản chọn trong protocol_settings. Nhưng node dùng **hai nhân khác nhau** — chọn
nhầm thì node lên mà client không vào được.

**Gọi API panel phải viết thường**, và `v2ray` phải đổi thành `vmess`
(`api/panel/panel.go:58-61`). Gọi bằng `v2ray` là panel trả lỗi.

**`LIKE '__xb%'` trong SQL bắt nhầm.** Dấu `_` là ký tự đại diện, phải escape
`LIKE '\_\_xb%'`. Từng báo còn 4 tài khoản test trong khi cả 4 là khách thật.

**Binary liên kết tĩnh** nên không kén glibc — chạy được cả Alpine (musl). Nhưng
**Alpine phải `apk add bash`** trước vì script dùng mảng và `[[ ]]`.

---

## 7. Còn treo

- [ ] **Chạy thử bộ cài trên VPS Linux thật.** Đã kiểm URL, bytes, loại binary, cú
      pháp — nhưng bước `systemctl` và kết nối panel thì phải có máy thật mới biết.
- [ ] Chưa thử **OpenRC trên Alpine** và **Scheduled Task trên Windows**.
- [ ] `riscv64` có trong `build.sh` nhưng **lần build đó thất bại**, `dist/` không
      có file. Muốn hỗ trợ thì sửa lỗi build rồi thêm vào release.
- [ ] Cân nhắc thêm **SOCKS + HTTP** (rẻ) — xem mục 1.
- [ ] Kiểm tra cấu hình **Reality** trên panel: SNI mượn site nào, `dest` hợp lý
      chưa, đã bật Vision chưa.

## Kết nối TCP "chết" tích luỹ trên node Reality trực tiếp (CHINA 1/2, 17/09/2026)

Triệu chứng: V2bX 100% CPU trên máy 1 CPU/800 MB, RSS vượt GOMEMLIMIT, `ss -s` thấy **7.000 ESTABLISHED** trên cổng
node trong khi chỉ ~22 khách online; 80% im > 2 h (có cái 55 h), mẫu `bytes_sent:5890 / bytes_received:~8000`.
Gốc: phiên **UDP 443 (QUIC Facebook) đi qua VLESS** bị `route.json` → `block`; Xray không đóng kết nối vào
(cùng họ với lỗi `EndpointOverrideWriter` không có Close — v1.0.7 mới gỡ entry LinkManager, chưa đóng inbound),
app khách (Shadowrocket, China Mobile) giữ socket mãi → ~2.300 kết nối chết/ngày. Node đi qua CDN (.17/.20)
không dính vì CDN tự cắt kết nối im.

Band-aid (từ 18/09 nằm trong bộ cài: bước **4e**, mặc định bật, tắt bằng `HXreaper=0`; máy đã cài: `hyx` → **23**)
đang chạy trên CHINA 1 + 2: `conn-reaper.sh` (→ `/usr/local/sbin/v2bx-conn-reaper.sh`) + timer systemd
5 phút, `ss -K` mọi kết nối vào cổng node im > 900 s → Xray nhận lỗi đọc, tự dọn goroutine, không cần restart.
Kết quả: CN1 7.089 → 915 kết nối, CPU 100% → 6%; CN2 4.089 → 195, CPU 100% → 1,4%.
**Việc còn treo:** vá gốc trong `core/xray/app/dispatcher` — khi outbound (blackhole/UDP) kết thúc phải đóng
`link` phía inbound dù writer bị bọc EndpointOverrideWriter; hoặc cân nhắc bỏ `block` UDP 443 (đã có sniff quic +
UseIPv4 từ v1.0.4) để phiên có traffic thật và tự hết theo `connIdle`.
