# HypeX Node

Node server cho panel XBoard/V2board, chạy được trên **15 kiến trúc Linux** và **Windows**.

Fork từ [V2bX](https://github.com/InazumaV/V2bX) — phần lõi giữ nguyên, thay mới toàn bộ bộ cài đặt và bổ sung bản cài cho Windows.

---

## Cài đặt nhanh — Linux

```bash
export HXapiHost="panel.com" && export HXapiKey="API_KEY" && bash <(curl -Ls https://raw.githubusercontent.com/Tubetna/hypex-x/main/install.sh)
```

Script sẽ hỏi Node ID và giao thức. Thêm `NODE_ID` là **chạy thẳng, không hỏi gì**:

```bash
export HXapiHost="panel.com" && export HXapiKey="API_KEY" && export NODE_ID=5 && bash <(curl -Ls https://raw.githubusercontent.com/Tubetna/hypex-x/main/install.sh)
```

Cài xong gõ `v2bx` để mở menu quản lý.

### Biến điều khiển

| Biến | Mặc định | Ghi chú |
|---|---|---|
| `HXapiHost` | *(hỏi)* | Link panel. Không cần gõ `https://`, script tự thêm |
| `HXapiKey` | *(hỏi)* | Lấy trong Admin → Cấu hình → Thông số máy chủ |
| `NODE_ID` | *(hỏi)* | **Đặt biến này là script không hỏi gì nữa** |
| `NODE_TYPE` | `VMess` | Xem bảng giao thức bên dưới |
| `AUTO_SSL` | `y` khi có `NODE_ID` | `n` để bỏ chứng chỉ tự ký |
| `NUM_NODES` | *(hỏi)* | Nhiều node trên một máy thì đặt số rồi nhập từng node |
| `V2BX_BASE_URL` | GitHub Releases | Trỏ sang mirror riêng nếu cần |

Cũng nhận `API_HOST` / `API_KEY` thay cho `HXapiHost` / `HXapiKey`.

---

## Cài đặt — Windows

PowerShell quyền **Administrator**:

```powershell
iwr -useb https://raw.githubusercontent.com/Tubetna/hypex-x/main/install.ps1 | iex
```

Hoặc tải về rồi chạy với tham số:

```powershell
.\install.ps1 -ApiHost https://panel.com -ApiKey KEY -NodeId 5 -NodeType VMess
.\install.ps1 -Status      # xem trạng thái
.\install.ps1 -Logs        # xem log realtime
.\install.ps1 -Update      # cập nhật bản mới
.\install.ps1 -Uninstall   # gỡ cài đặt
```

Node chạy bằng **Scheduled Task** dưới quyền SYSTEM, tự khởi động cùng máy, tự bật lại khi lỗi. V2bX không phải Windows Service thật (không gọi `StartServiceCtrlDispatcher`) nên `sc.exe create` sẽ báo *"service did not respond"* — đó là lý do dùng Scheduled Task.

---

## Giao thức hỗ trợ

Panel liệt kê 11 loại nhưng node chỉ có nhân dựng inbound cho **8**:

| Giao thức | `NODE_TYPE` | Nhân xử lý |
|---|---|---|
| VMess | `VMess` | xray |
| VLESS | `VLESS` | xray |
| Trojan | `Trojan` | xray |
| Shadowsocks | `Shadowsocks` | sing |
| Hysteria2 | `Hysteria2` | hysteria2 |
| Hysteria v1 | `Hysteria` | sing |
| TUIC | `TUIC` | sing |
| AnyTLS | `AnyTLS` | sing |
| ~~SOCKS · Naive · HTTP · Mieru~~ | — | **không hỗ trợ** |

`NODE_TYPE` không phân biệt hoa thường, nhận cả tên tắt `v2ray` / `ss` / `hy2`. Chọn phải bốn loại không hỗ trợ thì script **báo lỗi ngay lúc cài**, không để node cài xong rồi chết lúc khởi động.

> **Hysteria vs Hysteria2:** panel chỉ có một mục "Hysteria" (`hysteria2` là bí danh của `hysteria`), phiên bản chọn trong protocol_settings của node. Nhưng node dùng **hai nhân khác nhau** — node phiên bản 2 phải chọn `Hysteria2`, phiên bản 1 chọn `Hysteria`. Chọn nhầm thì node lên nhưng client không kết nối được.

---

## Kiến trúc hỗ trợ

| | |
|---|---|
| **x86** | `amd64` · `386` |
| **ARM** | `arm64` · `arm32-v7` · `arm32-v6` · `arm32-v5` |
| **MIPS** | `mips32` · `mips32le` · `mips64` · `mips64le` |
| **Khác** | `ppc64` · `ppc64le` · `s390x` |
| **Windows** | `amd64` · `386` · `arm64` |

Script tự nhận diện, kể cả hai trường hợp `uname -m` đánh lừa:

- **Kernel 64-bit nhưng userland 32-bit** (Raspberry Pi OS và nhiều image ARM): `uname -m` trả `aarch64` nhưng phải cài bản arm32 → phân biệt bằng `getconf LONG_BIT`
- **MIPS big-endian hay little-endian**: `uname -m` không phân biệt được → đọc byte `EI_DATA` trong header ELF của `/bin/sh`

Binary **liên kết tĩnh** nên không kén glibc, chạy được cả trên Alpine (musl).

`riscv64` chưa có bản dựng sẵn — tự build bằng `./build.sh` rồi cài tay.

---

## Hệ điều hành

| Nhóm | Trình quản lý gói |
|---|---|
| Debian · Ubuntu · Mint · Raspbian · Armbian · Kali · Deepin | `apt` |
| RHEL · CentOS · Rocky · Alma · Fedora · Kylin · OpenCloudOS · Anolis · Amazon Linux | `dnf` (tự lùi `yum` nếu máy chưa có `dnf`) |
| **EulerOS · openEuler** (Huawei) · UOS | `dnf` / `yum` + chế độ tương thích riêng |
| openSUSE · SLES | `zypper` |
| Arch · Manjaro | `pacman` |
| Alpine | `apk` + init script **OpenRC** |

**EulerOS/openEuler** được xử lý riêng: gán nhãn SELinux bằng `semanage fcontext` + `restorecon` (bền vững qua relabel) thay vì `chcon` (mất sau relabel), tự lùi về `yum` khi thiếu `dnf`, và cảnh báo khi `firewalld` đang chặn cổng.

> **Alpine phải `apk add bash` trước** — script dùng mảng và `[[ ]]` nên cần bash thật, Alpine mặc định chỉ có `ash`.

---

## Menu quản lý

Gõ `v2bx` (Linux):

| | | | |
|---|---|---|---|
| **1** Cài đặt | **6** Khởi động lại | **11** Cài BBR | **16** Tạo SSL tự ký |
| **2** Cập nhật | **7** Kiểm tra trạng thái | **12** Mở cổng tường lửa | **17** Cập nhật geo |
| **3** Gỡ cài đặt | **8** Xem log realtime | **13** Chặn Speedtest | **18** Kiểm tra giới hạn thiết bị |
| **4** Khởi động | **9** Bật tự khởi động | **14** Xem config.json | |
| **5** Dừng | **10** Tắt tự khởi động | **15** Tạo khoá X25519 | |

**Mục 2 (Cập nhật)** tải đúng gói theo kiến trúc CPU của máy, **chạy thử binary mới trước khi dừng dịch vụ**, và tự lùi về bản cũ nếu bản mới không khởi động được.

**Mục 18** kiểm tra chuỗi giới hạn thiết bị từ phía node: panel có trả `alivelist` không, bao nhiêu user đang bị giới hạn, node đã báo IP online lên chưa.

> Giới hạn thiết bị **không cấu hình ở node**. Khoá `DeviceLimit` trong `config.json` được đọc nhưng không có chỗ nào dùng — số thiết bị đặt trong **panel**, theo Gói cước hoặc theo từng User.

---

## Đường dẫn

| | Linux | Windows |
|---|---|---|
| Binary | `/usr/bin/V2bX-bin/V2bX` | `C:\V2bX\V2bX.exe` |
| Cấu hình | `/etc/V2bX/config.json` | `C:\V2bX\config.json` |
| Dữ liệu geo | `/etc/V2bX/geo{ip,site}.{dat,db}` | `C:\V2bX\geo*.{dat,db}` |
| Chứng chỉ | `/etc/V2bX/cert.crt` · `private.key` | `C:\V2bX\cert.crt` · `private.key` |
| Dịch vụ | `V2bX.service` (systemd) hoặc `/etc/init.d/V2bX` (OpenRC) | Scheduled Task `V2bX` |
| Log | `journalctl -u V2bX -f` | `C:\V2bX\logs\V2bX.log` |

Geo data nằm cùng `config.json` chứ không cùng binary, vì `AssetPath` của nhân xray mặc định là `/etc/V2bX/` và nhân sing đọc `geoip.db`/`geosite.db` từ thư mục làm việc. Đặt sai chỗ thì mọi rule `geoip:` / `geosite:` từ panel đều lỗi.

---

## Build từ mã nguồn

Cần Go 1.25 trở lên.

```bash
./build.sh              # Linux/macOS — build hết 24 platform ra ./dist
powershell ./build.ps1  # Windows
```

Build một platform:

```bash
GOEXPERIMENT=jsonv2 GOOS=linux GOARCH=amd64 go build -trimpath \
  -tags "sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor" \
  -ldflags "-X 'github.com/InazumaV/V2bX/cmd.version=dev' -s -w -buildid=" \
  -o V2bX
```

Bỏ bớt tag trong `-tags` để build gọn hơn nếu chỉ cần một nhân.

### Phát hành bản mới

Binary **không nằm trong git** — repo chỉ giữ mã nguồn và script (23MB). Bản dựng đưa lên GitHub Releases:

```bash
./build.sh
gh release create v1.0.1 dist/V2bX-linux-*.zip dist/V2bX-windows-*.zip
```

Script tải qua `releases/latest/download/` nên **không phải sửa gì** sau khi tạo release mới.

---

## Lưu ý khi cài

- **Chứng chỉ tự ký theo IP**: bật `allowInsecure` cho node đó trên panel, không thì client báo lỗi chứng chỉ.
- **Tường lửa**: script cảnh báo khi `firewalld` hoặc `ufw` đang bật. Mở cổng bằng menu **12**, hoặc `firewall-cmd --permanent --add-port=<cổng>/tcp --add-port=<cổng>/udp && firewall-cmd --reload`.
- **Cài lại đè lên bản đang chạy**: script tự dừng dịch vụ trước khi ghi đè. Linux không cho ghi lên file đang thực thi (`ETXTBSY`).
- **Windows Defender** có thể chặn `V2bX.exe` — thêm loại trừ cho thư mục cài đặt.

---

## Ghi chú kỹ thuật

[`NOTES.md`](NOTES.md) — muốn thêm giao thức thì sửa file nào, những bẫy đã dính, và việc còn treo.

## Giấy phép

[MPL-2.0](LICENSE), kế thừa từ dự án gốc.

## Thanks

* [V2bX](https://github.com/InazumaV/V2bX) — dự án gốc
* [Project X](https://github.com/XTLS/) · [V2Fly](https://github.com/v2fly) · [XrayR](https://github.com/XrayR/XrayR)
* [sing-box](https://github.com/SagerNet/sing-box) · [Hysteria](https://github.com/apernet/hysteria)
