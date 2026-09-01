<#
    ==========================================
    Script cài đặt V2bX cho Windows
    Hỗ trợ: Windows 10/11, Windows Server 2016+
    Kiến trúc: amd64, 386, arm64
    ==========================================

    Cách dùng:
      Cài mới     : .\install.ps1
      Cài im lặng : .\install.ps1 -ApiHost https://panel.com -ApiKey KEY -NodeId 5 -NodeType V2ray
      Cập nhật    : .\install.ps1 -Update
      Gỡ cài đặt  : .\install.ps1 -Uninstall
      Trạng thái  : .\install.ps1 -Status
      Xem log     : .\install.ps1 -Logs

    Chạy nhanh từ Internet (PowerShell quyền Administrator):
      iwr -useb https://raw.githubusercontent.com/Tubetna/hypex-x/main/install.ps1 | iex
#>

[CmdletBinding()]
param(
    [string] $ApiHost,
    [string] $ApiKey,
    [int]    $NodeId,
    [ValidateSet('VMess', 'VLESS', 'Trojan', 'Shadowsocks', 'Hysteria2', 'Hysteria', 'TUIC', 'AnyTLS', 'V2ray')]
    [string] $NodeType,
    [string] $InstallDir = 'C:\V2bX',
    [switch] $AutoSsl,
    [switch] $Update,
    [switch] $Uninstall,
    [switch] $Status,
    [switch] $Logs
)

$ErrorActionPreference = 'Stop'

$TaskName = 'V2bX'
$BaseUrl  = $env:V2BX_BASE_URL
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = 'https://github.com/Tubetna/hypex-x/releases/latest/download'
}

$BinPath  = Join-Path $InstallDir 'V2bX.exe'
$ConfPath = Join-Path $InstallDir 'config.json'
$LogDir   = Join-Path $InstallDir 'logs'
$LogPath  = Join-Path $LogDir 'V2bX.log'

# ── Tiện ích hiển thị ────────────────────────────────────────────
function Write-Ok   ($m) { Write-Host "  $m" -ForegroundColor Green }
function Write-Warn ($m) { Write-Host "  $m" -ForegroundColor Yellow }
function Write-Err  ($m) { Write-Host "  $m" -ForegroundColor Red }
function Write-Step ($m) { Write-Host "$m" -ForegroundColor Cyan }
function Die ($m) { Write-Err "Lỗi: $m"; exit 1 }

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Die 'Cần mở PowerShell bằng quyền Administrator (chuột phải > Run as administrator).'
    }
}

# ── Phát hiện kiến trúc ──────────────────────────────────────────
function Get-ArchSuffix {
    $a = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $a = $env:PROCESSOR_ARCHITEW6432 }
    switch ($a) {
        'AMD64' { return 'windows-amd64' }
        'ARM64' { return 'windows-arm64' }
        'x86'   { return 'windows-386' }
        default { Die "Không nhận ra kiến trúc CPU '$a'." }
    }
}

# ── Tải + giải nén ───────────────────────────────────────────────
function Get-Package {
    param([string] $Suffix, [string] $Dest)

    $url = "$BaseUrl/V2bX-$Suffix.zip"
    $zip = Join-Path $Dest 'v2bx.zip'
    Write-Step "Đang tải V2bX cho $Suffix ..."
    Write-Host "  $url" -ForegroundColor DarkGray

    # TLS 1.2 — Windows Server 2016 và PowerShell 5.1 không bật sẵn
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $prev = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # nhanh hơn nhiều khi tải file lớn
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 600
    } catch {
        Die "Không tải được gói cài đặt. $($_.Exception.Message)"
    } finally {
        $ProgressPreference = $prev
    }

    if (-not (Test-Path $zip) -or (Get-Item $zip).Length -eq 0) { Die 'File tải về rỗng.' }

    Write-Step 'Đang giải nén ...'
    $x = Join-Path $Dest 'x'
    Expand-Archive -Path $zip -DestinationPath $x -Force

    # Gói có thể phẳng hoặc nằm trong một thư mục con
    $exe = Get-ChildItem -Path $x -Filter 'V2bX.exe' -Recurse -File | Select-Object -First 1
    if (-not $exe) { Die 'Không tìm thấy V2bX.exe trong gói tải về.' }
    return $exe.Directory.FullName
}

# ── Cài binary + geo ─────────────────────────────────────────────
function Install-Files {
    param([string] $SrcDir)

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    New-Item -ItemType Directory -Force -Path $LogDir     | Out-Null

    $backup = $null
    if (Test-Path $BinPath) {
        $backup = "$BinPath.bak"
        Copy-Item $BinPath $backup -Force
    }

    Copy-Item (Join-Path $SrcDir 'V2bX.exe') $BinPath -Force

    # Xray đọc geo từ AssetPath, sing-box đọc geoip.db/geosite.db từ thư mục làm việc.
    # Trên Windows AssetPath mặc định (/etc/V2bX/) vô nghĩa nên config bên dưới trỏ lại.
    $geoCount = 0
    foreach ($g in @('geoip.dat', 'geosite.dat', 'geoip.db', 'geosite.db')) {
        $s = Join-Path $SrcDir $g
        if (Test-Path $s) { Copy-Item $s (Join-Path $InstallDir $g) -Force; $geoCount++ }
    }
    Write-Ok "Đã cài $geoCount/4 file dữ liệu geo."

    # File mẫu — chỉ chép khi chưa có, không đè của người dùng
    foreach ($f in @('route.json', 'dns.json', 'custom_inbound.json', 'custom_outbound.json')) {
        $s = Join-Path $SrcDir $f
        $d = Join-Path $InstallDir $f
        if ((Test-Path $s) -and -not (Test-Path $d)) { Copy-Item $s $d -Force }
    }

    # Kiểm tra binary chạy được (bắt trường hợp tải nhầm kiến trúc)
    try {
        & $BinPath version *> $null
        if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
    } catch {
        if ($backup) {
            Move-Item $backup $BinPath -Force
            Die 'Binary mới không chạy được trên máy này — đã lùi về bản cũ.'
        }
        Die 'Binary không chạy được trên máy này (sai kiến trúc?).'
    }
    if ($backup) { Remove-Item $backup -Force -ErrorAction SilentlyContinue }
    Write-Ok 'Binary hoạt động bình thường.'
}

# ── Sinh config.json ─────────────────────────────────────────────
function New-Config {
    param(
        [string] $PanelHost, [string] $Key,
        [array]  $Nodes,     [bool]   $UseSsl
    )

    if (Test-Path $ConfPath) {
        $stamp = Get-Date -Format 'yyyyMMddHHmmss'
        Copy-Item $ConfPath "$ConfPath.bak.$stamp" -Force
        Write-Warn "Đã sao lưu config.json cũ thành config.json.bak.$stamp"
    }

    # Đường dẫn Windows phải escape dấu \ khi nhúng vào JSON
    $assetPath = ($InstallDir.TrimEnd('\') + '\').Replace('\', '\\')
    $certFile  = (Join-Path $InstallDir 'cert.crt').Replace('\', '\\')
    $keyFile   = (Join-Path $InstallDir 'private.key').Replace('\', '\\')

    $nodeBlocks = @()
    foreach ($n in $Nodes) {
        # Loại nào chạy trên nhân nào — theo bảng dispatch trong mã nguồn V2bX:
        #   core/xray/inbound.go : vmess, vless, trojan, shadowsocks
        #   core/sing/node.go    : cả 8 loại (superset)
        #   core/hy2             : riêng hysteria2
        $core = switch ($n.Type) {
            'VMess'       { 'xray' }
            'V2ray'       { 'xray' }
            'VLESS'       { 'xray' }
            'Trojan'      { 'xray' }
            'Shadowsocks' { 'sing' }
            'Hysteria2'   { 'hysteria2' }
            'Hysteria'    { 'sing' }
            'TUIC'        { 'sing' }
            'AnyTLS'      { 'sing' }
            default       { 'sing' }
        }
        $cert = ''
        if ($UseSsl) {
            $cert = @"
,
        "CertConfig": {
          "CertMode": "file",
          "CertFile": "$certFile",
          "KeyFile": "$keyFile"
        }
"@
        }
        $nodeBlocks += @"
    {
      "ApiConfig": {
        "ApiHost": "$PanelHost",
        "ApiKey": "$Key",
        "NodeID": $($n.Id),
        "NodeType": "$($n.Type)",
        "Timeout": 30
      },
      "Options": {
        "Core": "$core",
        "ListenIP": "0.0.0.0",
        "SendIP": "0.0.0.0",
        "DeviceOnlineMinTraffic": 100$cert
      }
    }
"@
    }

    $json = @"
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
      "AssetPath": "$assetPath"
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
$($nodeBlocks -join ",`n")
  ]
}
"@

    # Ghi UTF-8 KHÔNG BOM — Go đọc BOM ở đầu file sẽ báo lỗi JSON
    [IO.File]::WriteAllText($ConfPath, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Ok "Đã ghi cấu hình: $ConfPath"
}

# ── Dịch vụ (Scheduled Task) ─────────────────────────────────────
# V2bX không phải ứng dụng Windows Service (không gọi StartServiceCtrlDispatcher)
# nên sc.exe sẽ báo "service did not respond". Dùng Scheduled Task chạy lúc khởi
# động máy dưới quyền SYSTEM, có tự khởi động lại khi lỗi.
function Install-Task {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $cmd = "`"$BinPath`" server -c `"$ConfPath`" >> `"$LogPath`" 2>&1"
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' `
        -Argument "/c $cmd" -WorkingDirectory $InstallDir

    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
        -LogonType ServiceAccount -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings `
        -Description 'V2bX Node Service' | Out-Null

    Write-Ok "Đã tạo tác vụ khởi động cùng máy: $TaskName"
}

function Start-V2bX {
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 5
}

function Stop-V2bX {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Get-Process -Name 'V2bX' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}

function Test-Running {
    $p = Get-Process -Name 'V2bX' -ErrorAction SilentlyContinue
    return $null -ne $p
}

function Show-Status {
    Write-Host ''
    Write-Step '══ Trạng thái V2bX ══'
    if (-not (Test-Path $BinPath)) { Write-Warn 'Chưa cài đặt.'; return }

    Write-Host "  Thư mục   : $InstallDir"
    $ver = (& $BinPath version 2>$null | Select-Object -Last 1)
    Write-Host "  Phiên bản : $ver"

    if (Test-Running) {
        $p = Get-Process -Name 'V2bX'
        $mem = [math]::Round($p.WorkingSet64 / 1MB, 1)
        Write-Ok "Đang chạy (PID $($p.Id), RAM ${mem}MB)"
    } else {
        Write-Err 'Không chạy'
    }

    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        Write-Host "  Tác vụ    : $($t.State)"
    } else {
        Write-Warn 'Chưa đăng ký tác vụ khởi động cùng máy.'
    }

    if (Test-Path $LogPath) {
        Write-Host ''
        Write-Step '── 15 dòng log gần nhất ──'
        Get-Content $LogPath -Tail 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
}

# ── Các chế độ phụ ───────────────────────────────────────────────
if ($Status) { Assert-Admin; Show-Status; exit 0 }

if ($Logs) {
    Assert-Admin
    if (-not (Test-Path $LogPath)) { Die "Chưa có file log tại $LogPath" }
    Write-Step "Đang theo dõi $LogPath (Ctrl+C để thoát)"
    Get-Content $LogPath -Tail 50 -Wait
    exit 0
}

if ($Uninstall) {
    Assert-Admin
    Write-Step 'Đang gỡ cài đặt V2bX ...'
    Stop-V2bX
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName 'V2bX Node*' -ErrorAction SilentlyContinue
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    Write-Ok 'Đã gỡ cài đặt xong.'
    exit 0
}

if ($Update) {
    Assert-Admin
    if (-not (Test-Path $BinPath)) { Die "Chưa cài V2bX tại $InstallDir." }

    $suffix = Get-ArchSuffix
    $tmp = Join-Path $env:TEMP ("v2bx-up-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $src = Get-Package -Suffix $suffix -Dest $tmp
        Stop-V2bX
        Install-Files -SrcDir $src
        Start-V2bX
        if (Test-Running) { Write-Ok 'Cập nhật thành công, V2bX đang chạy.' }
        else { Write-Err 'Cập nhật xong nhưng V2bX chưa chạy — xem log bằng: .\install.ps1 -Logs' }
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# ==========================================
# Cài đặt
# ==========================================
Assert-Admin

$suffix = Get-ArchSuffix

Write-Host ''
Write-Host '===========================================' -ForegroundColor Blue
Write-Host ' Cài đặt V2bX cho Windows' -ForegroundColor Green
Write-Host '===========================================' -ForegroundColor Blue
Write-Host "  Windows    : $((Get-CimInstance Win32_OperatingSystem).Caption)" -ForegroundColor Yellow
Write-Host "  Kiến trúc  : $suffix" -ForegroundColor Yellow
Write-Host "  Thư mục    : $InstallDir" -ForegroundColor Yellow
Write-Host '===========================================' -ForegroundColor Blue
Write-Host ''

# ── Thu thập thông tin ───────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($ApiHost)) {
    $ApiHost = Read-Host 'Nhập link Panel (VD: https://panel.com)'
}
if ([string]::IsNullOrWhiteSpace($ApiHost)) { Die 'Chưa nhập link Panel.' }
$ApiHost = $ApiHost.TrimEnd('/')
if ($ApiHost -notmatch '^https?://') { $ApiHost = "https://$ApiHost" }

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = Read-Host 'Nhập API Key của Panel'
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) { Die 'Chưa nhập API Key.' }

$useSsl = $AutoSsl.IsPresent
if (-not $PSBoundParameters.ContainsKey('AutoSsl') -and -not $NodeId) {
    $a = Read-Host 'Tự động tạo chứng chỉ SSL tự ký cho IP máy chủ? (y/n)'
    $useSsl = ($a -match '^[yY]')
}

$nodes = @()
if ($NodeId -gt 0) {
    if ([string]::IsNullOrWhiteSpace($NodeType)) { $NodeType = 'VMess' }
    $nodes += [pscustomobject]@{ Id = $NodeId; Type = $NodeType }
} else {
    $num = Read-Host 'Bạn muốn chạy bao nhiêu Node trên máy này? (VD: 2)'
    $n = 0
    if (-not [int]::TryParse($num, [ref]$n) -or $n -lt 1) {
        Write-Warn 'Số lượng không hợp lệ, mặc định 1 Node.'
        $n = 1
    }
    for ($i = 1; $i -le $n; $i++) {
        Write-Host ''
        Write-Host "--- Cấu hình cho Node thứ $i ---" -ForegroundColor Yellow

        $idStr = Read-Host "Nhập Node ID cho Node thứ $i"
        $id = 0
        while (-not [int]::TryParse($idStr, [ref]$id) -or $id -lt 1) {
            Write-Err 'Node ID phải là số.'
            $idStr = Read-Host "Nhập Node ID cho Node thứ $i"
        }

        Write-Host 'Chọn loại Giao thức (Node Type):'
        Write-Host '  1. VMess          (nhân xray)'
        Write-Host '  2. VLESS          (nhân xray)'
        Write-Host '  3. Trojan         (nhân xray)'
        Write-Host '  4. Shadowsocks    (nhân sing)'
        Write-Host '  5. Hysteria2      (nhân hysteria2)'
        Write-Host '  6. Hysteria v1    (nhân sing)'
        Write-Host '  7. TUIC           (nhân sing)'
        Write-Host '  8. AnyTLS         (nhân sing)'
        $c = Read-Host 'Nhập số (1-8)'
        $t = switch ($c) {
            '1' { 'VMess' }
            '2' { 'VLESS' }
            '3' { 'Trojan' }
            '4' { 'Shadowsocks' }
            '5' { 'Hysteria2' }
            '6' { 'Hysteria' }
            '7' { 'TUIC' }
            '8' { 'AnyTLS' }
            default { Write-Warn 'Lựa chọn không hợp lệ, dùng VMess.'; 'VMess' }
        }
        $nodes += [pscustomobject]@{ Id = $id; Type = $t }
    }
}

# ── Tải và cài ───────────────────────────────────────────────────
$tmp = Join-Path $env:TEMP ("v2bx-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $src = Get-Package -Suffix $suffix -Dest $tmp
    Stop-V2bX
    Install-Files -SrcDir $src
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Chứng chỉ SSL tự ký ──────────────────────────────────────────
if ($useSsl) {
    Write-Step 'Đang tạo chứng chỉ SSL tự ký ...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ip = (Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 15).Content.Trim()
    } catch { $ip = '127.0.0.1' }

    $cert = New-SelfSignedCertificate -Subject "CN=$ip" -DnsName $ip `
        -KeyAlgorithm RSA -KeyLength 2048 -NotAfter (Get-Date).AddYears(10) `
        -CertStoreLocation 'Cert:\LocalMachine\My'

    # Xuất ra PEM để V2bX (thư viện Go) đọc được — .pfx thì không
    $crt = Join-Path $InstallDir 'cert.crt'
    $key = Join-Path $InstallDir 'private.key'

    $b64 = [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
    "-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----" |
        Set-Content -Path $crt -Encoding ASCII

    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    if ($rsa) {
        try {
            $pk = [Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey(), 'InsertLineBreaks')
            "-----BEGIN PRIVATE KEY-----`n$pk`n-----END PRIVATE KEY-----" |
                Set-Content -Path $key -Encoding ASCII
            Write-Ok "Đã tạo chứng chỉ cho IP $ip"
            Write-Warn "Cert tự ký — trên Panel phải bật 'allowInsecure' cho node này."
        } catch {
            # ExportPkcs8PrivateKey cần .NET 4.7.2+ / PowerShell 7
            Write-Warn 'Không xuất được private key ở định dạng PEM (Windows/.NET quá cũ).'
            Write-Warn 'Hãy tự đặt cert.crt + private.key vào thư mục cài, hoặc cài không dùng SSL.'
            $useSsl = $false
        }
    } else {
        Write-Warn 'Không lấy được private key — bỏ qua cấu hình SSL.'
        $useSsl = $false
    }
}

# ── Ghi cấu hình + đăng ký tác vụ ────────────────────────────────
New-Config -PanelHost $ApiHost -Key $ApiKey -Nodes $nodes -UseSsl $useSsl
Install-Task

# ── Tường lửa ────────────────────────────────────────────────────
Write-Host ''
$fw = Read-Host 'Mở cổng trên Windows Firewall cho Node? Nhập cổng/dải (VD: 443 hoặc 10000-20000), Enter để bỏ qua'
if (-not [string]::IsNullOrWhiteSpace($fw)) {
    if ($fw -match '^\d+(-\d+)?$') {
        Remove-NetFirewallRule -DisplayName 'V2bX Node*' -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName 'V2bX Node TCP' -Direction Inbound `
            -Protocol TCP -LocalPort $fw -Action Allow | Out-Null
        New-NetFirewallRule -DisplayName 'V2bX Node UDP' -Direction Inbound `
            -Protocol UDP -LocalPort $fw -Action Allow | Out-Null
        Write-Ok "Đã mở cổng $fw (TCP + UDP)."
    } else {
        Write-Warn 'Cổng không hợp lệ, bỏ qua.'
    }
}

# ── Khởi động ────────────────────────────────────────────────────
Write-Step 'Đang khởi động V2bX ...'
Start-V2bX

Write-Host ''
Write-Host '==========================================' -ForegroundColor Green
if (Test-Running) {
    Write-Ok 'Trạng thái: Đang chạy'
    Start-Sleep -Seconds 3
    if ((Test-Path $LogPath) -and (Select-String -Path $LogPath -Pattern 'Các Node đã khởi động xong' -Quiet)) {
        Write-Ok 'Kết nối Panel: Thành công! Đã tải cấu hình từ Panel.'
    } else {
        Write-Warn 'Kết nối Panel: Đang chờ... xem log bằng: .\install.ps1 -Logs'
    }
} else {
    Write-Err 'Trạng thái: Không chạy'
    if (Test-Path $LogPath) {
        Write-Host '  Log gần nhất:' -ForegroundColor Red
        Get-Content $LogPath -Tail 15 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
}
Write-Host '==========================================' -ForegroundColor Green

Write-Host ''
Write-Host '  Lệnh quản lý:' -ForegroundColor White
Write-Host "    .\install.ps1 -Status      # xem trạng thái"
Write-Host "    .\install.ps1 -Logs        # xem log realtime"
Write-Host "    .\install.ps1 -Update      # cập nhật bản mới"
Write-Host "    .\install.ps1 -Uninstall   # gỡ cài đặt"
Write-Host ''
Write-Warn 'Nếu Windows Defender chặn V2bX.exe, thêm loại trừ cho thư mục cài đặt.'
