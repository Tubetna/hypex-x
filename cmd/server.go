package cmd

import (
	"os"
	"os/signal"
	"runtime"
	"syscall"

	"github.com/InazumaV/V2bX/conf"
	vCore "github.com/InazumaV/V2bX/core"
	"github.com/InazumaV/V2bX/limiter"
	"github.com/InazumaV/V2bX/node"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

var (
	config string
	watch  bool
)

var serverCommand = cobra.Command{
	Use:   "server",
	Short: "Run V2bX server",
	Run:   serverHandle,
	Args:  cobra.NoArgs,
}

func init() {
	serverCommand.PersistentFlags().
		StringVarP(&config, "config", "c",
			"/etc/V2bX/config.json", "config file path")
	serverCommand.PersistentFlags().
		BoolVarP(&watch, "watch", "w",
			true, "watch file path change")
	command.AddCommand(&serverCommand)
}

func serverHandle(_ *cobra.Command, _ []string) {
	showVersion()
	c := conf.New()
	err := c.LoadFromPath(config)
	if err != nil {
		log.WithField("err", err).Error("Tải file cấu hình thất bại")
		return
	}
	switch c.LogConfig.Level {
	case "debug":
		log.SetLevel(log.DebugLevel)
	case "info":
		log.SetLevel(log.InfoLevel)
	case "warn":
		log.SetLevel(log.WarnLevel)
	case "error":
		log.SetLevel(log.ErrorLevel)
	}
	if c.LogConfig.Output != "" {
		f, err := os.OpenFile(c.LogConfig.Output, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			log.WithField("err", err).Error("Mở file log thất bại, sẽ in trực tiếp ra màn hình")
		}
		log.SetOutput(f)
	}
	limiter.Init()
	log.Info("Đang khởi động V2bX...")
	vc, err := vCore.NewCore(c.CoresConfig)
	if err != nil {
		log.WithField("err", err).Error("Khởi tạo Core thất bại")
		return
	}
	err = vc.Start()
	if err != nil {
		log.WithField("err", err).Error("Khởi động Core thất bại")
		return
	}
	defer vc.Close()
	log.Info("Core ", vc.Type(), " đã khởi động thành công")
	nodes := node.New()
	err = nodes.Start(c.NodeConfig, vc)
	if err != nil {
		log.WithField("err", err).Error("Khởi chạy các Node thất bại")
		return
	}
	log.Info("Các Node đã khởi động xong")
	xdns := os.Getenv("XRAY_DNS_PATH")
	sdns := os.Getenv("SING_DNS_PATH")
	if watch {
		err = c.Watch(config, xdns, sdns, func() {
			nodes.Close()
			err = vc.Close()
			if err != nil {
				log.WithField("err", err).Error("Dừng Node thất bại để khởi động lại")
				return
			}
			vc, err = vCore.NewCore(c.CoresConfig)
			if err != nil {
				log.WithField("err", err).Error("Khởi tạo Core mới thất bại")
				return
			}
			err = vc.Start()
			if err != nil {
				log.WithField("err", err).Error("Khởi động Core thất bại")
				return
			}
			log.Info("Core ", vc.Type(), " đã được khởi động lại")
			err = nodes.Start(c.NodeConfig, vc)
			if err != nil {
				log.WithField("err", err).Error("Chạy lại các Node thất bại")
				return
			}
			log.Info("Các Node đã được khởi động lại")
			runtime.GC()
		})
		if err != nil {
			log.WithField("err", err).Error("Bật chế độ theo dõi cấu hình (Watch) thất bại")
			return
		}
	}
	// clear memory
	runtime.GC()
	// wait exit signal
	{
		osSignals := make(chan os.Signal, 1)
		signal.Notify(osSignals, syscall.SIGINT, syscall.SIGTERM)
		<-osSignals
	}
}
