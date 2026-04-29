# V2bX Cross-Platform Build Script (PowerShell)
param(
    [string]$OutputDir = ".\dist",
    [switch]$Force
)

$ErrorActionPreference = "Continue"

$APP_NAME   = "V2bX"
$MODULE     = "github.com/InazumaV/V2bX"
$BUILD_TAGS = "sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor"

$gitTag = (git describe --tags --always --dirty 2>$null)
$VERSION = if ($env:VERSION) { $env:VERSION } elseif ($gitTag) { $gitTag } else { "dev" }

# LDFLAGS - dung single quote de truyen vao go build
$LDFLAGS = "-X github.com/InazumaV/V2bX/cmd.version=$VERSION -s -w -buildid="

# Danh sach platform
$PLATFORMS = @(
    [pscustomobject]@{ GOOS="linux";   GOARCH="amd64";    GOARM=""; GOMIPS="";          SUFFIX="linux-amd64"      },
    [pscustomobject]@{ GOOS="linux";   GOARCH="386";      GOARM=""; GOMIPS="";          SUFFIX="linux-386"        },
    [pscustomobject]@{ GOOS="linux";   GOARCH="arm64";    GOARM=""; GOMIPS="";          SUFFIX="linux-arm64"      },
    [pscustomobject]@{ GOOS="linux";   GOARCH="arm";      GOARM="7"; GOMIPS="";         SUFFIX="linux-arm32-v7"   },
    [pscustomobject]@{ GOOS="linux";   GOARCH="arm";      GOARM="6"; GOMIPS="";         SUFFIX="linux-arm32-v6"   },
    [pscustomobject]@{ GOOS="linux";   GOARCH="arm";      GOARM="5"; GOMIPS="";         SUFFIX="linux-arm32-v5"   },
    [pscustomobject]@{ GOOS="linux";   GOARCH="mips";     GOARM=""; GOMIPS="softfloat"; SUFFIX="linux-mips32"     },
    [pscustomobject]@{ GOOS="linux";   GOARCH="mipsle";   GOARM=""; GOMIPS="softfloat"; SUFFIX="linux-mips32le"   },
    [pscustomobject]@{ GOOS="linux";   GOARCH="mips64";   GOARM=""; GOMIPS="";          SUFFIX="linux-mips64"     },
    [pscustomobject]@{ GOOS="linux";   GOARCH="mips64le"; GOARM=""; GOMIPS="";          SUFFIX="linux-mips64le"   },
    [pscustomobject]@{ GOOS="linux";   GOARCH="riscv64";  GOARM=""; GOMIPS="";          SUFFIX="linux-riscv64"    },
    [pscustomobject]@{ GOOS="linux";   GOARCH="s390x";    GOARM=""; GOMIPS="";          SUFFIX="linux-s390x"      },
    [pscustomobject]@{ GOOS="linux";   GOARCH="ppc64";    GOARM=""; GOMIPS="";          SUFFIX="linux-ppc64"      },
    [pscustomobject]@{ GOOS="linux";   GOARCH="ppc64le";  GOARM=""; GOMIPS="";          SUFFIX="linux-ppc64le"    },
    [pscustomobject]@{ GOOS="windows"; GOARCH="amd64";    GOARM=""; GOMIPS="";          SUFFIX="windows-amd64"    },
    [pscustomobject]@{ GOOS="windows"; GOARCH="386";      GOARM=""; GOMIPS="";          SUFFIX="windows-386"      },
    [pscustomobject]@{ GOOS="windows"; GOARCH="arm64";    GOARM=""; GOMIPS="";          SUFFIX="windows-arm64"    },
    [pscustomobject]@{ GOOS="darwin";  GOARCH="amd64";    GOARM=""; GOMIPS="";          SUFFIX="darwin-amd64"     },
    [pscustomobject]@{ GOOS="darwin";  GOARCH="arm64";    GOARM=""; GOMIPS="";          SUFFIX="darwin-arm64"     },
    [pscustomobject]@{ GOOS="freebsd"; GOARCH="amd64";    GOARM=""; GOMIPS="";          SUFFIX="freebsd-amd64"    },
    [pscustomobject]@{ GOOS="freebsd"; GOARCH="386";      GOARM=""; GOMIPS="";          SUFFIX="freebsd-386"      },
    [pscustomobject]@{ GOOS="freebsd"; GOARCH="arm64";    GOARM=""; GOMIPS="";          SUFFIX="freebsd-arm64"    },
    [pscustomobject]@{ GOOS="freebsd"; GOARCH="arm";      GOARM="7"; GOMIPS="";         SUFFIX="freebsd-arm32-v7" },
    [pscustomobject]@{ GOOS="android"; GOARCH="arm64";    GOARM=""; GOMIPS="";          SUFFIX="android-arm64"    }
)

function Log($msg, $clr) { Write-Host $msg -ForegroundColor $clr }

function Copy-Assets($dir) {
    if (Test-Path ".\example") {
        Copy-Item ".\example\*.json" $dir -ErrorAction SilentlyContinue
        "geoip.dat","geosite.dat","geoip.db","geosite.db" | ForEach-Object {
            $src = ".\example\$_"
            if (Test-Path $src) { Copy-Item $src $dir }
        }
    }
    if (Test-Path ".\README.md") { Copy-Item ".\README.md" $dir }
    if (Test-Path ".\LICENSE")   { Copy-Item ".\LICENSE"   $dir }
}

# Header
Log "==========================================" "Cyan"
Log "   V2bX Cross-Platform Build" "Green"
Log "==========================================" "Cyan"
Log "  Version : $VERSION" "Yellow"
Log "  Output  : $OutputDir" "Yellow"
Log "  Total   : $($PLATFORMS.Count) platforms" "Yellow"
Log "==========================================" "Cyan"
Write-Host ""

$goVer = & go version 2>&1
Log "Go: $goVer" "Green"
Write-Host ""

# Download deps
Log "Downloading dependencies..." "Yellow"
$env:GOEXPERIMENT = "jsonv2"
& go mod download
Log "Dependencies OK" "Green"
Write-Host ""

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$ok   = 0
$fail = 0
$failList = @()
$total = $PLATFORMS.Count
$i = 0

foreach ($p in $PLATFORMS) {
    $i++
    $GOOS   = $p.GOOS
    $GOARCH = $p.GOARCH
    $GOARM  = $p.GOARM
    $GOMIPS = $p.GOMIPS
    $SUFFIX = $p.SUFFIX

    $bin     = if ($GOOS -eq "windows") { "$APP_NAME.exe" } else { $APP_NAME }
    $bdir    = Join-Path $OutputDir "$APP_NAME-$SUFFIX"
    $zipPath = Join-Path $OutputDir "$APP_NAME-$SUFFIX.zip"

    $label = "[$i/$total] $SUFFIX"
    Write-Host ("  {0,-40}" -f $label) -NoNewline

    if (-not $Force -and (Test-Path $zipPath)) {
        Log " SKIP (cached)" "Cyan"
        $ok++
        continue
    }

    New-Item -ItemType Directory -Force -Path $bdir | Out-Null

    $env:GOOS        = $GOOS
    $env:GOARCH      = $GOARCH
    $env:CGO_ENABLED = "0"
    $env:GOEXPERIMENT = "jsonv2"

    if ($GOARM)  { $env:GOARM  = $GOARM  } else { Remove-Item Env:GOARM  -ErrorAction SilentlyContinue }
    if ($GOMIPS) { $env:GOMIPS = $GOMIPS } else { Remove-Item Env:GOMIPS -ErrorAction SilentlyContinue }

    $outPath = Join-Path $bdir $bin
    $result = & go build -trimpath -tags $BUILD_TAGS -ldflags $LDFLAGS -o $outPath . 2>&1

    if ($LASTEXITCODE -eq 0) {
        Copy-Assets $bdir
        Compress-Archive -Path "$bdir\*" -DestinationPath $zipPath -Force
        Remove-Item $bdir -Recurse -Force
        Log " OK" "Green"
        $ok++
    } else {
        Log " FAILED" "Red"
        if ($env:VERBOSE -eq "1") { Write-Host $result -ForegroundColor DarkRed }
        Remove-Item $bdir -Recurse -Force -ErrorAction SilentlyContinue
        $fail++
        $failList += $SUFFIX
    }
}

$env:GOOS = ""; $env:GOARCH = ""; $env:GOARM = ""; $env:GOMIPS = ""

Write-Host ""
Log "==========================================" "Cyan"
Log "  OK   : $ok / $total" "Green"
if ($fail -gt 0) { Log "  FAIL : $fail / $total" "Red" }
Log "  Dir  : $OutputDir" "Yellow"
Log "==========================================" "Cyan"

if ($failList.Count -gt 0) {
    Write-Host ""
    Log "Failed platforms:" "Red"
    $failList | ForEach-Object { Log "  - $_" "Red" }
}

Write-Host ""
Log "ZIP files:" "Green"
$zips = Get-ChildItem -Path $OutputDir -Filter "*.zip" -ErrorAction SilentlyContinue
foreach ($z in $zips) {
    $mb = [math]::Round($z.Length / 1MB, 1)
    Write-Host ("  {0,-45} {1} MB" -f $z.Name, $mb)
}
