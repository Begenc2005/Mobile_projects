package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// Turkmenistan numbers: +993 XX XXXXXX
var phoneRe = regexp.MustCompile(`^\+993\d{8}$`)

func normalizePhone(p string) string {
	var b strings.Builder
	for _, r := range p {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	d := b.String()
	switch {
	case strings.HasPrefix(d, "993") && len(d) == 11:
		return "+" + d
	case strings.HasPrefix(d, "8") && len(d) == 9: // 8 6X XXXXXX (local format)
		return "+993" + d[1:]
	case len(d) == 8: // 6X XXXXXX
		return "+993" + d
	}
	return "+" + d
}

// ---------- SMS ----------

type SMSSender interface {
	Send(phone, text string) error
}

type logSMS struct{}

func (logSMS) Send(phone, text string) error {
	log.Printf("[SMS dev] to %s: %s", phone, text)
	return nil
}

// httpSMS posts JSON {"to","text","sender"} to an SMS gateway (TMCELL / Altyn Asyr / aggregator).
// Adapt the payload in Send() to the exact API of the chosen operator.
type httpSMS struct {
	url, token, sender string
	client             *http.Client
}

func (h httpSMS) Send(phone, text string) error {
	body, _ := json.Marshal(map[string]string{"to": phone, "text": text, "sender": h.sender})
	req, _ := http.NewRequest("POST", h.url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if h.token != "" {
		req.Header.Set("Authorization", "Bearer "+h.token)
	}
	resp, err := h.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("sms gateway status %d", resp.StatusCode)
	}
	return nil
}

func newSMS(cfg Config) SMSSender {
	if cfg.SMSURL == "" {
		return logSMS{}
	}
	return httpSMS{url: cfg.SMSURL, token: cfg.SMSToken, sender: cfg.SMSSender,
		client: &http.Client{Timeout: 15 * time.Second}}
}

func genCode() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1000000))
	return fmt.Sprintf("%06d", n.Int64())
}

// ---------- handlers ----------

func (s *Server) handleRequestCode(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Phone string `json:"phone"`
	}
	if err := readJSON(r, &in); err != nil {
		fail(w, r, 400, "bad_request")
		return
	}
	phone := normalizePhone(in.Phone)
	if !phoneRe.MatchString(phone) {
		fail(w, r, 400, "bad_phone")
		return
	}
	if !s.limiter.allow("ip:"+clientIP(r), 10, time.Hour) || !s.limiter.allow("ph:"+phone, 5, time.Hour) {
		fail(w, r, 429, "too_many")
		return
	}
	var sentAt time.Time
	err := s.db.QueryRowContext(r.Context(), `SELECT sent_at FROM sms_codes WHERE phone=$1`, phone).Scan(&sentAt)
	if err == nil && time.Since(sentAt) < 60*time.Second {
		fail(w, r, 429, "wait")
		return
	}
	code := genCode()
	_, err = s.db.ExecContext(r.Context(), `
INSERT INTO sms_codes(phone, code_hash, expires_at, attempts, sent_at) VALUES($1,$2,$3,0,now())
ON CONFLICT (phone) DO UPDATE SET code_hash=$2, expires_at=$3, attempts=0, sent_at=now()`,
		phone, sha(phone+code+s.cfg.Secret), time.Now().Add(5*time.Minute))
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	text := fmt.Sprintf("Dost: tassyklaýyş koduňyz %s. Код подтверждения: %s", code, code)
	if err := s.sms.Send(phone, text); err != nil {
		log.Println("sms error:", err)
		fail(w, r, 502, "sms_failed")
		return
	}
	resp := map[string]any{"ok": true, "phone": phone}
	if s.cfg.DevMode {
		resp["dev_code"] = code // testing only: no SMS gateway yet
	}
	writeJSON(w, r, 200, resp)
}

func (s *Server) handleVerify(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Phone  string `json:"phone"`
		Code   string `json:"code"`
		Device string `json:"device"`
	}
	if err := readJSON(r, &in); err != nil {
		fail(w, r, 400, "bad_request")
		return
	}
	phone := normalizePhone(in.Phone)
	ctx := r.Context()
	var hash string
	var exp time.Time
	var attempts int
	err := s.db.QueryRowContext(ctx,
		`SELECT code_hash, expires_at, attempts FROM sms_codes WHERE phone=$1`, phone).Scan(&hash, &exp, &attempts)
	if err != nil || time.Now().After(exp) {
		fail(w, r, 400, "code_expired")
		return
	}
	if attempts >= 5 {
		fail(w, r, 429, "too_many")
		return
	}
	if sha(phone+strings.TrimSpace(in.Code)+s.cfg.Secret) != hash {
		_, _ = s.db.ExecContext(ctx, `UPDATE sms_codes SET attempts=attempts+1 WHERE phone=$1`, phone)
		fail(w, r, 400, "bad_code")
		return
	}
	_, _ = s.db.ExecContext(ctx, `DELETE FROM sms_codes WHERE phone=$1`, phone)

	var uid int64
	var isNew bool
	err = s.db.QueryRowContext(ctx, `
INSERT INTO users(phone) VALUES($1)
ON CONFLICT (phone) DO UPDATE SET last_seen=now()
RETURNING id, (xmax = 0)`, phone).Scan(&uid, &isNew)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	token := randHex(32)
	if _, err := s.db.ExecContext(ctx, `INSERT INTO sessions(token_hash, user_id, device) VALUES($1,$2,$3)`,
		sha(token), uid, truncate(in.Device, 100)); err != nil {
		fail(w, r, 500, "db")
		return
	}
	u, err := s.getUser(ctx, uid)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, map[string]any{"token": token, "user": u, "new": isNew || u.Name == ""})
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	_, _ = s.db.ExecContext(r.Context(), `DELETE FROM sessions WHERE token_hash=$1`, sha(tok))
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) > n {
		return string(r[:n])
	}
	return s
}
