package limiter

import (
	"errors"
	"net"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/InazumaV/V2bX/api/panel"
	"github.com/InazumaV/V2bX/common/format"
	"github.com/InazumaV/V2bX/conf"
	"github.com/juju/ratelimit"
)

var limitLock sync.RWMutex
var limiter map[string]*Limiter

func Init() {
	limiter = map[string]*Limiter{}
}

type Limiter struct {
	DomainRules   []*regexp.Regexp
	ProtocolRules []string
	SpeedLimit    int
	UserOnlineIP  *sync.Map      // Key: TagUUID, value: {Key: Ip, value: Uid}
	OldUserOnline *sync.Map      // Key: Ip, value: Uid
	UUIDtoUID     map[string]int // Key: UUID, value: Uid
	UserLimitInfo *sync.Map      // Key: TagUUID value: UserLimitInfo
	SpeedLimiter  *sync.Map      // key: TagUUID, value: *ratelimit.Bucket
	AliveList     map[int]int    // Key: Uid, value: alive_ip
	// AliveNets: DẢI mạng panel đang ghi nhận cho mỗi user (mọi node gộp lại),
	// đã gom theo /24 (IPv4) · /64 (IPv6). IP mới thuộc một dải đã biết là máy
	// cũ vừa bị CGNAT đổi IP, không phải thiết bị mới → không chặn.
	AliveNets map[int]map[string]struct{} // Key: Uid, value: set dải
	// RealIP: IP đã có kết nối tới đích KHÔNG phải máy chủ đo độ trễ trong lượt
	// báo cáo hiện tại. Chỉ IP nằm trong đây mới được báo lên panel làm thiết bị.
	RealIP *sync.Map // Key: TagUUID + "|" + Ip, value: struct{}
}

type UserLimitInfo struct {
	UID               int
	SpeedLimit        int
	DeviceLimit       int
	DynamicSpeedLimit int
	ExpireTime        int64
	OverLimit         bool
}

func AddLimiter(tag string, l *conf.LimitConfig, users []panel.UserInfo, alive *panel.AliveMap) *Limiter {
	info := &Limiter{
		SpeedLimit:    l.SpeedLimit,
		UserOnlineIP:  new(sync.Map),
		UserLimitInfo: new(sync.Map),
		SpeedLimiter:  new(sync.Map),
		OldUserOnline: new(sync.Map),
		RealIP:        new(sync.Map),
	}
	info.SetAlive(alive)
	uuidmap := make(map[string]int)
	for i := range users {
		uuidmap[users[i].Uuid] = users[i].Id
		userLimit := &UserLimitInfo{}
		userLimit.UID = users[i].Id
		if users[i].SpeedLimit != 0 {
			userLimit.SpeedLimit = users[i].SpeedLimit
		}
		if users[i].DeviceLimit != 0 {
			userLimit.DeviceLimit = users[i].DeviceLimit
		}
		userLimit.OverLimit = false
		info.UserLimitInfo.Store(format.UserTag(tag, users[i].Uuid), userLimit)
	}
	info.UUIDtoUID = uuidmap
	limitLock.Lock()
	limiter[tag] = info
	limitLock.Unlock()
	return info
}

// SetAlive nạp kết quả /alivelist mới nhất: số thiết bị đang đếm và các IP đã biết.
func (l *Limiter) SetAlive(alive *panel.AliveMap) {
	if alive == nil {
		return
	}
	nets := make(map[int]map[string]struct{}, len(alive.IPs))
	for uid, list := range alive.IPs {
		set := make(map[string]struct{}, len(list))
		for _, ip := range list {
			set[subnetKey(strings.TrimPrefix(ip, "::ffff:"))] = struct{}{}
		}
		nets[uid] = set
	}
	if alive.Alive == nil {
		alive.Alive = make(map[int]int)
	}
	l.AliveList = alive.Alive
	l.AliveNets = nets
}

// overDeviceLimit: IP này có bị coi là thiết bị vượt giới hạn không.
//
// Chỉ chặn khi (1) user có giới hạn, (2) panel đã đếm đủ số máy, VÀ (3) IP này
// panel chưa từng thấy ở node nào. Bỏ điều kiện (3) thì máy đã đếm rồi vừa
// đổi node hoặc bị nhà mạng đổi IP cũng bị chặn — đó là lý do khách "lâu lâu
// mất mạng vài phút rồi tự có lại".
func (l *Limiter) overDeviceLimit(uid, deviceLimit int, ip string) bool {
	if deviceLimit <= 0 {
		return false
	}
	if l.AliveList[uid] < deviceLimit {
		return false
	}
	if set, ok := l.AliveNets[uid]; ok {
		if _, known := set[subnetKey(strings.TrimPrefix(ip, "::ffff:"))]; known {
			return false // IP mới nhưng cùng dải máy đã đếm → CGNAT đổi IP, tha
		}
	}
	return true
}

// subnetKey gom IP về dải để so khớp: /24 cho IPv4, /64 cho IPv6. Nhà mạng di
// động đổi IP công cộng liên tục trong một dải; coi cả dải là một thiết bị thì
// một máy không bị đếm thành nhiều. IP không hợp lệ trả về nguyên văn.
func subnetKey(ip string) string {
	p := net.ParseIP(ip)
	if p == nil {
		return ip
	}
	if v4 := p.To4(); v4 != nil {
		return net.IP(v4.Mask(net.CIDRMask(24, 32))).String() + "/24"
	}
	return p.Mask(net.CIDRMask(64, 128)).String() + "/64"
}

func GetLimiter(tag string) (info *Limiter, err error) {
	limitLock.RLock()
	info, ok := limiter[tag]
	limitLock.RUnlock()
	if !ok {
		return nil, errors.New("not found")
	}
	return info, nil
}

func DeleteLimiter(tag string) {
	limitLock.Lock()
	delete(limiter, tag)
	limitLock.Unlock()
}

func (l *Limiter) UpdateUser(tag string, added []panel.UserInfo, deleted []panel.UserInfo) {
	for i := range deleted {
		l.UserLimitInfo.Delete(format.UserTag(tag, deleted[i].Uuid))
		l.UserOnlineIP.Delete(format.UserTag(tag, deleted[i].Uuid))
		l.SpeedLimiter.Delete(format.UserTag(tag, deleted[i].Uuid))
		delete(l.UUIDtoUID, deleted[i].Uuid)
		delete(l.AliveList, deleted[i].Id)
		delete(l.AliveNets, deleted[i].Id)
	}
	for i := range added {
		userLimit := &UserLimitInfo{
			UID: added[i].Id,
		}
		if added[i].SpeedLimit != 0 {
			userLimit.SpeedLimit = added[i].SpeedLimit
			userLimit.ExpireTime = 0
		}
		if added[i].DeviceLimit != 0 {
			userLimit.DeviceLimit = added[i].DeviceLimit
		}
		userLimit.OverLimit = false
		l.UserLimitInfo.Store(format.UserTag(tag, added[i].Uuid), userLimit)
		l.UUIDtoUID[added[i].Uuid] = added[i].Id
	}
}

func (l *Limiter) UpdateDynamicSpeedLimit(tag, uuid string, limit int, expire time.Time) error {
	if v, ok := l.UserLimitInfo.Load(format.UserTag(tag, uuid)); ok {
		info := v.(*UserLimitInfo)
		info.DynamicSpeedLimit = limit
		info.ExpireTime = expire.Unix()
	} else {
		return errors.New("not found")
	}
	return nil
}

func (l *Limiter) CheckLimit(taguuid string, ip string, isTcp bool, noSSUDP bool) (Bucket *ratelimit.Bucket, Reject bool) {
	// check if ipv4 mapped ipv6
	ip = strings.TrimPrefix(ip, "::ffff:")

	// check and gen speed limit Bucket
	nodeLimit := l.SpeedLimit
	userLimit := 0
	deviceLimit := 0
	var uid int
	if v, ok := l.UserLimitInfo.Load(taguuid); ok {
		u := v.(*UserLimitInfo)
		deviceLimit = u.DeviceLimit
		uid = u.UID
		if u.ExpireTime < time.Now().Unix() && u.ExpireTime != 0 {
			if u.SpeedLimit != 0 {
				userLimit = u.SpeedLimit
				u.DynamicSpeedLimit = 0
				u.ExpireTime = 0
			} else {
				l.UserLimitInfo.Delete(taguuid)
			}
		} else {
			userLimit = determineSpeedLimit(u.SpeedLimit, u.DynamicSpeedLimit)
		}
	} else {
		return nil, true
	}
	if noSSUDP {
		// Store online user for device limit
		newipMap := new(sync.Map)
		newipMap.Store(ip, uid)
		// If any device is online
		if v, loaded := l.UserOnlineIP.LoadOrStore(taguuid, newipMap); loaded {
			oldipMap := v.(*sync.Map)
			// If this is a new ip
			if _, loaded := oldipMap.LoadOrStore(ip, uid); !loaded {
				if v, loaded := l.OldUserOnline.Load(ip); loaded {
					if v.(int) == uid {
						l.OldUserOnline.Delete(ip)
					}
				} else if l.overDeviceLimit(uid, deviceLimit, ip) {
					oldipMap.Delete(ip)
					return nil, true
				}
			}
		} else if v, ok := l.OldUserOnline.Load(ip); ok {
			if v.(int) == uid {
				l.OldUserOnline.Delete(ip)
			}
		} else if l.overDeviceLimit(uid, deviceLimit, ip) {
			l.UserOnlineIP.Delete(taguuid)
			return nil, true
		}
	}

	limit := int64(determineSpeedLimit(nodeLimit, userLimit)) * 1000000 / 8 // If you need the Speed limit
	if limit > 0 {
		Bucket = ratelimit.NewBucketWithQuantum(time.Second, limit, limit) // Byte/s
		if v, ok := l.SpeedLimiter.LoadOrStore(taguuid, Bucket); ok {
			return v.(*ratelimit.Bucket), false
		} else {
			l.SpeedLimiter.Store(taguuid, Bucket)
			return Bucket, false
		}
	} else {
		return nil, false
	}
}

// GetOnlineDevice trả về các IP sẽ báo lên panel làm "thiết bị" rồi reset lượt.
//
// IP trong lượt này chỉ nối tới máy chủ đo độ trễ (generate_204, captive
// portal…) thì KHÔNG báo — bấm "kiểm tra độ trễ" không được tính là một máy.
// Nó vẫn được nhớ ở OldUserOnline để lượt sau không bị coi là IP lạ.
func (l *Limiter) GetOnlineDevice() (*[]panel.OnlineUser, error) {
	var onlineUser []panel.OnlineUser
	l.OldUserOnline = new(sync.Map)
	real := l.RealIP
	l.RealIP = new(sync.Map)
	l.UserOnlineIP.Range(func(key, value interface{}) bool {
		taguuid := key.(string)
		ipMap := value.(*sync.Map)
		ipMap.Range(func(key, value interface{}) bool {
			uid := value.(int)
			ip := key.(string)
			l.OldUserOnline.Store(ip, uid)
			if _, ok := real.Load(taguuid + "|" + ip); ok {
				onlineUser = append(onlineUser, panel.OnlineUser{UID: uid, IP: ip})
			}
			return true
		})
		l.UserOnlineIP.Delete(taguuid) // Reset online device
		return true
	})

	return &onlineUser, nil
}

// probeHosts: máy chủ mà app VPN dùng để đo độ trễ / kiểm tra mạng. Kết nối
// chỉ tới các đích này không chứng tỏ có người đang dùng.
var probeHosts = map[string]struct{}{
	"www.gstatic.com":               {},
	"connectivitycheck.gstatic.com": {},
	"connectivitycheck.android.com": {},
	"clients1.google.com":           {},
	"clients3.google.com":           {},
	"cp.cloudflare.com":             {},
	"captive.apple.com":             {},
	"www.apple.com":                 {}, // Reality SNI, iOS ping "www.apple.com/library/test/success.html"
	"www.msftconnecttest.com":       {},
	"www.msftncsi.com":              {},
	"detectportal.firefox.com":      {},
	"connect.rom.miui.com":          {},
	"wifi.vivo.com.cn":              {},
	"conn1.oppomobile.com":          {},
	"conn2.oppomobile.com":          {},
	"1.1.1.1":                       {},
	"1.0.0.1":                       {},
}

// IsProbeHost: đích này có phải máy chủ đo độ trễ không.
func IsProbeHost(host string) bool {
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	_, ok := probeHosts[host]
	return ok
}

// MarkReal ghi nhận IP nguồn vừa mở kết nối tới một đích thật (không phải
// máy chủ đo độ trễ). Gọi sau khi CheckLimit đã cho qua.
func (l *Limiter) MarkReal(taguuid, ip, destHost string) {
	if IsProbeHost(destHost) {
		return
	}
	l.RealIP.Store(taguuid+"|"+strings.TrimPrefix(ip, "::ffff:"), struct{}{})
}

type UserIpList struct {
	Uid    int      `json:"Uid"`
	IpList []string `json:"Ips"`
}
