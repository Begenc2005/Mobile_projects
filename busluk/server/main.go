// Buşluk — сервер маркетплейса объявлений.
// Один бинарник + PostgreSQL. Все настройки — переменные окружения (см. busluk.env.example).
package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	_ "github.com/lib/pq"
)

type Config struct {
	Addr, DBURL, DataDir, PublicURL, AdminToken, Secret string
	RequireLogin                                        bool
	DemoPhone, DemoCode                                 string
	SMS                                                 *SMPP
	Pay                                                 PayCfg
	Prices                                              Prices
}

var (
	cfg Config
	db  *sql.DB
)

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func envInt(k string, d int64) int64 {
	if v, err := strconv.ParseInt(os.Getenv(k), 10, 64); err == nil {
		return v
	}
	return d
}

func main() {
	cfg = Config{
		Addr:         env("ADDR", ":8080"),
		DBURL:        env("DB_URL", "postgres://busluk:busluk@127.0.0.1/busluk?sslmode=disable"),
		DataDir:      env("DATA_DIR", "./data"),
		PublicURL:    strings.TrimRight(env("PUBLIC_URL", "http://127.0.0.1:8080"), "/"),
		AdminToken:   env("ADMIN_TOKEN", ""),
		Secret:       env("SECRET", "change-me"),
		RequireLogin: env("REQUIRE_LOGIN", "1") == "1",
		DemoPhone:    normPhone(env("DEMO_PHONE", "")),
		DemoCode:     env("DEMO_CODE", ""),
		Prices: Prices{
			Bump:  envInt("PRICE_BUMP", 10),
			Vip7:  envInt("PRICE_VIP7", 50),
			Vip30: envInt("PRICE_VIP30", 150),
		},
		Pay: PayCfg{
			URL:  strings.TrimRight(env("PAY_URL", ""), "/"),
			User: env("PAY_USER", ""), Pass: env("PAY_PASS", ""),
			Currency: env("PAY_CURRENCY", "934"),
			Mult:     envInt("PAY_MULT", 100),
			Mock:     env("PAY_MOCK", "") == "1",
		},
	}
	if h := env("SMPP_HOST", ""); h != "" {
		ton, _ := strconv.Atoi(env("SMPP_SRC_TON", "5"))
		npi, _ := strconv.Atoi(env("SMPP_SRC_NPI", "0"))
		cfg.SMS = &SMPP{
			Addr: net.JoinHostPort(h, env("SMPP_PORT", "2775")),
			User: env("SMPP_USER", ""), Pass: env("SMPP_PASS", ""), SystemType: env("SMPP_SYSTEM_TYPE", ""),
			Src: env("SMPP_SRC", "Busluk"), SrcTON: byte(ton), SrcNPI: byte(npi),
		}
		cfg.SMS.Start()
	} else {
		log.Print("ВНИМАНИЕ: SMPP_HOST не задан — SMS-коды пишутся в лог")
	}

	// мягче порог похожести слов — поиск находит опечатки («toyta», «kwartra»)
	dsn := cfg.DBURL
	if !strings.Contains(dsn, "word_similarity_threshold") {
		if strings.Contains(dsn, "?") {
			dsn += "&"
		} else {
			dsn += "?"
		}
		dsn += "pg_trgm.word_similarity_threshold=0.45"
	}
	var err error
	if db, err = sql.Open("postgres", dsn); err != nil {
		log.Fatal(err)
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(10)
	if err = migrate(); err != nil {
		log.Fatal("migrate: ", err)
	}
	os.MkdirAll(cfg.DataDir+"/img", 0o755)
	initMeta(cfg.Prices)
	go jobs()

	srv := &http.Server{
		Addr: cfg.Addr, Handler: routes(),
		ReadTimeout: 30 * time.Second, WriteTimeout: 60 * time.Second, IdleTimeout: 120 * time.Second,
	}
	go func() {
		log.Printf("Buşluk слушает %s", cfg.Addr)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

func routes() http.Handler {
	m := http.NewServeMux()
	m.HandleFunc("GET /v1/meta", hMeta)
	m.HandleFunc("POST /v1/auth/send", hAuthSend)
	m.HandleFunc("POST /v1/auth/verify", hAuthVerify)
	m.HandleFunc("POST /v1/auth/logout", auth(hLogout))
	m.HandleFunc("GET /v1/me", auth(hMe))
	m.HandleFunc("PUT /v1/me", auth(hMeSave))

	read, readOne := optAuth(hList), optAuth(hAd)
	if cfg.RequireLogin {
		read, readOne = auth(hList), auth(hAd)
	}
	m.HandleFunc("GET /v1/ads", read)
	m.HandleFunc("GET /v1/ads/{id}", readOne)
	m.HandleFunc("GET /v1/suggest", hSuggest)
	m.HandleFunc("POST /v1/ads", auth(hAdCreate))
	m.HandleFunc("PUT /v1/ads/{id}", auth(hAdUpdate))
	m.HandleFunc("DELETE /v1/ads/{id}", auth(hAdDelete))
	m.HandleFunc("POST /v1/ads/{id}/state", auth(hAdState))
	m.HandleFunc("POST /v1/ads/{id}/report", auth(hReport))
	m.HandleFunc("GET /v1/my/ads", auth(hMyAds))
	m.HandleFunc("POST /v1/photo", auth(hPhoto))

	m.HandleFunc("POST /v1/pay", auth(hPay))
	m.HandleFunc("GET /pay/ret", hPayReturn)
	m.HandleFunc("GET /pay/mock", hPayMock)

	m.HandleFunc("GET /admin", hAdminPage)
	m.HandleFunc("GET /v1/admin/ads", admin(hAdminAds))
	m.HandleFunc("POST /v1/admin/ads/{id}", admin(hAdminAd))
	m.HandleFunc("POST /v1/admin/users/{id}", admin(hAdminUser))
	m.HandleFunc("GET /v1/admin/stats", admin(hAdminStats))

	fs := http.StripPrefix("/i/", http.FileServer(http.Dir(cfg.DataDir+"/img")))
	m.HandleFunc("GET /i/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		fs.ServeHTTP(w, r)
	})
	m.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok")) })

	return logMW(m)
}

func logMW(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t := time.Now()
		h.ServeHTTP(w, r)
		if d := time.Since(t); d > 500*time.Millisecond {
			log.Printf("медленно %s %s %v", r.Method, r.URL.Path, d)
		}
	})
}

// ---------- ответы ----------

var gzPool = sync.Pool{New: func() any { w, _ := gzip.NewWriterLevel(nil, 6); return w }}

// writeJSON сжимает ответ gzip, если он больше 600 байт: трафик списков падает в 4–6 раз.
func writeJSON(w http.ResponseWriter, r *http.Request, code int, v any) {
	b, _ := json.Marshal(v)
	writeRaw(w, r, code, b)
}

func writeRaw(w http.ResponseWriter, r *http.Request, code int, b []byte) {
	h := w.Header()
	h.Set("Content-Type", "application/json; charset=utf-8")
	h.Set("Vary", "Accept-Encoding")
	if len(b) > 600 && strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") {
		var buf bytes.Buffer
		gz := gzPool.Get().(*gzip.Writer)
		gz.Reset(&buf)
		gz.Write(b)
		gz.Close()
		gzPool.Put(gz)
		h.Set("Content-Encoding", "gzip")
		b = buf.Bytes()
	}
	h.Set("Content-Length", strconv.Itoa(len(b)))
	w.WriteHeader(code)
	w.Write(b)
}

// fail: код ошибки — короткая строка, клиент сам переводит её на RU/TK.
func fail(w http.ResponseWriter, r *http.Request, code int, e string) {
	writeJSON(w, r, code, map[string]string{"e": e})
}

func readBody(r *http.Request, v any) bool {
	return json.NewDecoder(http.MaxBytesReader(nil, r.Body, 64<<10)).Decode(v) == nil
}

func pathID(r *http.Request) int64 {
	id, _ := strconv.ParseInt(r.PathValue("id"), 10, 64)
	return id
}

func randHex(n int) string {
	b := make([]byte, n)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func hashStr(s ...string) []byte {
	h := sha256.New()
	for _, x := range s {
		h.Write([]byte(x))
		h.Write([]byte{0})
	}
	return h.Sum(nil)
}

func clientIP(r *http.Request) string {
	if x := r.Header.Get("X-Real-IP"); x != "" {
		return x
	}
	h, _, _ := net.SplitHostPort(r.RemoteAddr)
	return h
}

// ---------- лимиты ----------

type limiter struct {
	mu sync.Mutex
	m  map[string][]time.Time
}

var lim = &limiter{m: map[string][]time.Time{}}

// allow: не более n событий за окно per для ключа.
func (l *limiter) allow(key string, n int, per time.Duration) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	ts := l.m[key][:0]
	for _, t := range l.m[key] {
		if now.Sub(t) < per {
			ts = append(ts, t)
		}
	}
	if len(ts) >= n {
		l.m[key] = ts
		return false
	}
	l.m[key] = append(ts, now)
	return true
}

func (l *limiter) gc() {
	l.mu.Lock()
	defer l.mu.Unlock()
	for k, ts := range l.m {
		if len(ts) == 0 || time.Since(ts[len(ts)-1]) > 2*time.Hour {
			delete(l.m, k)
		}
	}
}

// ---------- фоновые задачи ----------

func jobs() {
	for i := 0; ; i++ {
		// объявления живут 30 дней с последнего поднятия (VIP — пока действует VIP)
		db.Exec(`UPDATE ads SET status=3 WHERE status=0 AND bumped_at < now()-interval '30 days'
			AND (vip_until IS NULL OR vip_until < now())`)
		db.Exec(`DELETE FROM otps WHERE exp < now()-interval '1 day'`)
		db.Exec(`DELETE FROM sessions WHERE seen_at < now()-interval '180 days'`)
		checkPendingPayments()
		lim.gc()
		time.Sleep(5 * time.Minute)
	}
}
