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

// Máy đã đếm bị CGNAT đổi sang IP MỚI cùng /24 → không được chặn dù đủ limit.
func TestCgnatSameSubnetNotRejected(t *testing.T) {
	l := newTestLimiter(&panel.AliveMap{
		Alive: map[int]int{7: 2},
		IPs:   map[int][]string{7: {"222.188.99.85", "171.218.86.25"}},
	})
	// IP mới toanh 222.188.99.200 — panel CHƯA thấy, nhưng cùng /24 với .85
	if _, reject := l.CheckLimit("node|u7", "222.188.99.200", true, true); reject {
		t.Fatal("IP mới cùng /24 với máy đã đếm bị chặn (CGNAT đổi IP)")
	}
	// IP ở dải thứ ba hoàn toàn thì vẫn chặn
	if _, reject := l.CheckLimit("node|u7", "8.8.8.8", true, true); !reject {
		t.Fatal("IP dải lạ khi đã đủ thiết bị mà không bị chặn")
	}
}

func newTestLimiter1(alive *panel.AliveMap) *Limiter {
	Init()
	users := []panel.UserInfo{{Id: 9, Uuid: "u9", DeviceLimit: 1}}
	return AddLimiter("node", &conf.LimitConfig{}, users, alive)
}

// Ca thật 04/10 (ndbn@, 37375): máy được đếm bằng IPv6 VNPT, cùng máy đó mở
// kết nối qua IPv4 Vinaphone → trước bị chặn, giờ phải cho qua.
func TestDualStackSamePhoneAllowed(t *testing.T) {
	l := newTestLimiter1(&panel.AliveMap{
		Alive:  map[int]int{9: 1},
		IPs:    map[int][]string{9: {"2001:ee0:26d:519b:1c09:11ff:fe53:df39"}},
		Family: map[int][2]int{9: {0, 1}},
	})
	if _, reject := l.CheckLimit("node|u9", "113.185.87.50", true, true); reject {
		t.Fatal("nửa IPv4 của máy đã đếm bằng IPv6 bị chặn")
	}
}

// Gói 1 máy: máy thứ hai thật (khác dải, CÙNG họ đã đủ) vẫn phải chặn.
func TestSecondDeviceSameFamilyStillRejected(t *testing.T) {
	l := newTestLimiter1(&panel.AliveMap{
		Alive:  map[int]int{9: 1},
		IPs:    map[int][]string{9: {"27.67.209.6", "2402:800:9d70:7608::1"}},
		Family: map[int][2]int{9: {1, 1}},
	})
	if _, reject := l.CheckLimit("node|u9", "27.67.101.185", true, true); !reject {
		t.Fatal("IPv4 thứ hai (dải khác) khi họ IPv4 đã đủ mà không bị chặn")
	}
	if _, reject := l.CheckLimit("node|u9", "2001:ee0:8209:bf79::5", true, true); !reject {
		t.Fatal("IPv6 thứ hai (dải khác) khi họ IPv6 đã đủ mà không bị chặn")
	}
}

// Panel cũ không gửi alive_family → node tự đếm theo họ từ alive_ips.
func TestFamilyFallbackFromIPs(t *testing.T) {
	l := newTestLimiter1(&panel.AliveMap{
		Alive: map[int]int{9: 1},
		IPs:   map[int][]string{9: {"2001:ee0:26d:519b::1"}},
	})
	if _, reject := l.CheckLimit("node|u9", "113.185.79.217", true, true); reject {
		t.Fatal("fallback: IPv4 đầu tiên khi chỉ có IPv6 bị chặn")
	}
	l2 := newTestLimiter1(&panel.AliveMap{
		Alive: map[int]int{9: 1},
		IPs:   map[int][]string{9: {"171.255.120.161"}},
	})
	if _, reject := l2.CheckLimit("node|u9", "27.68.87.205", true, true); !reject {
		t.Fatal("fallback: IPv4 thứ hai khác dải mà không bị chặn")
	}
}

func TestFamilyOf(t *testing.T) {
	if familyOf("1.2.3.4") != 0 || familyOf("::ffff:1.2.3.4") != 0 || familyOf("2001:db8::1") != 1 {
		t.Fatal("familyOf sai")
	}
}

func TestSubnetKey(t *testing.T) {
	cases := map[string]string{
		"222.188.99.85":  "222.188.99.0/24",
		"222.188.99.200": "222.188.99.0/24",
		"1.2.3.4":        "1.2.3.0/24",
	}
	for ip, want := range cases {
		if got := subnetKey(ip); got != want {
			t.Errorf("subnetKey(%s)=%s, muốn %s", ip, got, want)
		}
	}
	// hai IPv6 cùng /64
	if subnetKey("2001:db8:1:2:3:4:5:6") != subnetKey("2001:db8:1:2:ffff:ffff:ffff:ffff") {
		t.Error("hai IPv6 cùng /64 phải cho cùng khoá")
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
