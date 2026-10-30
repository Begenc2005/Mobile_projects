// Dost — local messenger server for Turkmenistan.
// Single binary: REST API + WebSocket realtime + media storage. PostgreSQL for data.
package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/lib/pq"
)

type Config struct {
	Addr        string
	DatabaseURL string
	MediaDir    string
	Secret      string
	DevMode     bool
	SMSURL      string
	SMSToken    string
	SMSSender   string
	MaxUploadMB int64
}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func main() {
	cfg := Config{
		Addr:        env("DOST_ADDR", ":8080"),
		DatabaseURL: env("DATABASE_URL", "postgres://dost:dost@localhost:5432/dost?sslmode=disable"),
		MediaDir:    env("MEDIA_DIR", "./data/media"),
		Secret:      env("DOST_SECRET", "change-me-in-production"),
		DevMode:     env("DEV_MODE", "0") == "1",
		SMSURL:      env("SMS_GATEWAY_URL", ""),
		SMSToken:    env("SMS_GATEWAY_TOKEN", ""),
		SMSSender:   env("SMS_SENDER", "Dost"),
		MaxUploadMB: 25,
	}
	if cfg.Secret == "change-me-in-production" && !cfg.DevMode {
		log.Fatal("DOST_SECRET must be set in production")
	}

	db, err := sql.Open("postgres", cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	db.SetMaxOpenConns(50)
	db.SetMaxIdleConns(10)
	db.SetConnMaxIdleTime(5 * time.Minute)
	for i := 0; ; i++ {
		if err = db.Ping(); err == nil {
			break
		}
		if i > 30 {
			log.Fatal("database not reachable: ", err)
		}
		log.Println("waiting for database...", err)
		time.Sleep(2 * time.Second)
	}
	if err := migrate(db); err != nil {
		log.Fatal("migrate: ", err)
	}
	if err := os.MkdirAll(cfg.MediaDir, 0o755); err != nil {
		log.Fatal(err)
	}

	s := &Server{cfg: cfg, db: db, hub: newHub(), sms: newSMS(cfg), limiter: newLimiter()}
	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           s.logMW(s.routes()),
		ReadHeaderTimeout: 15 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		log.Printf("Dost server listening on %s (dev=%v)", cfg.Addr, cfg.DevMode)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
	log.Println("stopped")
}
