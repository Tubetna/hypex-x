package limiter

import (
	"testing"

	"github.com/InazumaV/V2bX/api/panel"
	"github.com/InazumaV/V2bX/conf"
)

func newTestLimiter(alive *panel.AliveMap) *Limiter {
	Init()
	users := []panel.UserInfo{{Id: 7, Uuid: "u7", DeviceLimit: 2}}
	return AddLimiter("node", &conf.LimitConfig{}, users, alive)
}

// Máy đã được panel đếm, vừa đổi node → không được chặn.
func TestKnownIPNotRejectedWhenAtLimit(t *testing.T) {
	l := newTestLimiter(&panel.AliveMap{
		Alive: map[int]int{7: 2},
		IPs:   map[int][]string{7: {"1.1.1.10", "1.1.1.20"}},
	})
	if _, reject := l.CheckLimit("node|u7", "1.1.1.10", true, true); reject {
		t.Fatal("IP đã biết bị chặn dù chỉ là đổi node")
	}
	// IP lạ thứ ba thì vẫn phải chặn
	if _, reject := l.CheckLimit("node|u7", "9.9.9.9", true, true); !reject {
		t.Fatal("IP lạ khi đã đủ thiết bị mà không bị chặn")
	}
}

// Panel cũ không trả alive_ips → hành xử như trước: đủ limit là chặn IP lạ.
func TestOldPanelStillEnforces(t *testing.T) {
	l := newTestLimiter(&panel.AliveMap{Alive: map[int]int{7: 2}})
	if _, reject := l.CheckLimit("node|u7", "1.1.1.10", true, true); !reject {
		t.Fatal("panel cũ: đủ limit mà không chặn")
	}
}

func TestUnderLimitAllowed(t *testing.T) {
	l := newTestLimiter(&panel.AliveMap{Alive: map[int]int{7: 1}})
	if _, reject := l.CheckLimit("node|u7", "1.1.1.10", true, true); reject {
		t.Fatal("chưa đủ limit mà bị chặn")
	}
}

// IP chỉ ping máy chủ đo độ trễ thì không được báo lên panel làm thiết bị.
func TestProbeOnlyIPNotReported(t *testing.T) {
	l := newTestLimiter(&panel.AliveMap{})
	l.CheckLimit("node|u7", "1.1.1.10", true, true)
	l.MarkReal("node|u7", "1.1.1.10", "www.gstatic.com")
	l.CheckLimit("node|u7", "1.1.1.20", true, true)
	l.MarkReal("node|u7", "1.1.1.20", "www.youtube.com")

	online, _ := l.GetOnlineDevice()
	if len(*online) != 1 || (*online)[0].IP != "1.1.1.20" {
		t.Fatalf("mong báo đúng 1 IP thật, được %+v", *online)
	}
	// IP ping vẫn được nhớ để lượt sau không bị coi là lạ
	if _, ok := l.OldUserOnline.Load("1.1.1.10"); !ok {
		t.Fatal("IP ping không được nhớ ở OldUserOnline")
	}
	// lượt sau reset sạch
	online, _ = l.GetOnlineDevice()
	if len(*online) != 0 {
		t.Fatalf("sau reset còn %+v", *online)
	}
}

func TestIsProbeHost(t *testing.T) {
	for _, h := range []string{"www.gstatic.com", "WWW.GSTATIC.COM.", "cp.cloudflare.com", "captive.apple.com"} {
		if !IsProbeHost(h) {
			t.Errorf("%s phải là probe", h)
		}
	}
	for _, h := range []string{"fonts.gstatic.com", "www.google.com", "8.8.8.8", "graph.facebook.com"} {
		if IsProbeHost(h) {
			t.Errorf("%s không phải probe", h)
		}
	}
}
