package dispatcher

// Dọn kết nối vào đã im quá lâu NGAY TRONG TIẾN TRÌNH, thay cho v2bx-conn-reaper
// (script dùng `ss -K`, không chạy được trên kernel thiếu CONFIG_INET_DIAG_DESTROY
// như EulerOS của Huawei Cloud).
//
// Gốc bệnh (CHINA 1/2, 17/09/2026): app khách giữ socket VLESS/mux mở mãi sau khi
// luồng UDP bị block; đường DispatchLink của Xray mới không có timeout cho kết nối
// vào → sau vài ngày 7.000 socket chết, RAM vượt GOMEMLIMIT, GC quay vòng 100% CPU.
//
// Cách làm: mọi phiên DispatchLink có user đăng ký net.Conn vào của nó (mux dùng
// chung một conn cho nhiều phiên → đếm tham chiếu). Mỗi byte đi qua ở cả hai chiều
// cập nhật mốc hoạt động của conn. Goroutine quét mỗi phút, conn im quá
// V2BX_IDLE_KILL giây (mặc định 900; 0 = tắt) thì Close() → Process trả về, Xray
// tự dọn phiên, entry được gỡ trong defer của DispatchLink.

import (
	"context"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/xtls/xray-core/common"
	"github.com/xtls/xray-core/common/buf"
	"github.com/xtls/xray-core/common/errors"
	"github.com/xtls/xray-core/common/net"
)

type idleEntry struct {
	conn net.Conn
	last atomic.Int64 // unix nano của byte cuối cùng đi qua
	refs atomic.Int32 // số phiên DispatchLink đang dùng conn này
}

var (
	idleConns   sync.Map // net.Conn -> *idleEntry
	idleKillSec = idleKillSetting()
	idleOnce    sync.Once
)

func idleKillSetting() int64 {
	v := os.Getenv("V2BX_IDLE_KILL")
	if v == "" {
		return 900
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil || n < 0 {
		return 900
	}
	return n
}

// idleRegister ghi nhận một phiên mới trên conn; trả nil khi tắt hoặc không có conn
// (inbound UDP thuần không có Conn).
func idleRegister(conn net.Conn) *idleEntry {
	if conn == nil || idleKillSec == 0 {
		return nil
	}
	idleOnce.Do(func() { go idleReaper() })
	v, _ := idleConns.LoadOrStore(conn, &idleEntry{conn: conn})
	e := v.(*idleEntry)
	e.refs.Add(1)
	e.last.Store(time.Now().UnixNano())
	return e
}

func (e *idleEntry) touch() {
	if e != nil {
		e.last.Store(time.Now().UnixNano())
	}
}

func (e *idleEntry) release() {
	if e != nil && e.refs.Add(-1) <= 0 {
		idleConns.Delete(e.conn)
	}
}

func idleReaper() {
	t := time.NewTicker(time.Minute)
	defer t.Stop()
	for range t.C {
		limit := time.Duration(idleKillSec) * time.Second
		now := time.Now().UnixNano()
		killed, total := 0, 0
		idleConns.Range(func(_, v any) bool {
			e := v.(*idleEntry)
			total++
			if time.Duration(now-e.last.Load()) > limit {
				_ = e.conn.Close()
				killed++
			}
			return true
		})
		if killed > 0 {
			errors.LogWarning(context.Background(), "idle-kill: ngắt ", killed, "/", total, " kết nối vào im > ", limit)
		}
	}
}

// idleWriter cập nhật mốc hoạt động cho chiều xuống (server → client). Đặt ở lớp trong
// cùng của outbound.Writer để Close/Interrupt từ ManagedWriter lan xuống được.
type idleWriter struct {
	buf.Writer
	e *idleEntry
}

func (w *idleWriter) WriteMultiBuffer(mb buf.MultiBuffer) error {
	if mb.Len() > 0 {
		w.e.touch()
	}
	return w.Writer.WriteMultiBuffer(mb)
}

func (w *idleWriter) Close() error {
	return common.Close(w.Writer)
}

func (w *idleWriter) Interrupt() {
	common.Interrupt(w.Writer)
}
