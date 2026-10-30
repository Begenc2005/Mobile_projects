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
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Server struct {
	cfg     Config
	db      *sql.DB
	hub     *Hub
	sms     SMSSender
	limiter *Limiter
}

type ctxKey int

const uidKey ctxKey = 1

func (s *Server) routes() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, r, 200, map[string]any{"ok": true, "online": s.hub.count()})
	})
	// auth
	mux.HandleFunc("POST /api/auth/code", s.handleRequestCode)
	mux.HandleFunc("POST /api/auth/verify", s.handleVerify)
	mux.HandleFunc("POST /api/auth/logout", s.auth(s.handleLogout))
	// profile & users
	mux.HandleFunc("GET /api/me", s.auth(s.handleMe))
	mux.HandleFunc("PUT /api/me", s.auth(s.handleUpdateMe))
	mux.HandleFunc("GET /api/users/{id}", s.auth(s.handleGetUser))
	mux.HandleFunc("GET /api/users/search", s.auth(s.handleSearchUser))
	mux.HandleFunc("POST /api/users/lookup", s.auth(s.handleLookup))
	// chats & messages
	mux.HandleFunc("GET /api/chats", s.auth(s.handleChats))
	mux.HandleFunc("GET /api/chats/{id}", s.auth(s.handleChat))
	mux.HandleFunc("POST /api/chats/direct", s.auth(s.handleDirect))
	mux.HandleFunc("POST /api/chats/group", s.auth(s.handleGroup))
	mux.HandleFunc("POST /api/chats/{id}/members", s.auth(s.handleAddMembers))
	mux.HandleFunc("POST /api/chats/{id}/leave", s.auth(s.handleLeave))
	mux.HandleFunc("PUT /api/chats/{id}/mute", s.auth(s.handleMute))
	mux.HandleFunc("GET /api/chats/{id}/messages", s.auth(s.handleMessages))
	mux.HandleFunc("GET /api/sync", s.auth(s.handleSync))
	// media
	mux.HandleFunc("POST /api/media", s.auth(s.handleUpload))
	mux.HandleFunc("GET /media/{id}", s.auth(s.handleMedia))
	// realtime
	mux.HandleFunc("GET /ws", s.auth(s.handleWS))
	return mux
}

// ---------- helpers ----------

type apiError struct {
	Error string `json:"error"`
}

func writeJSON(w http.ResponseWriter, r *http.Request, code int, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		http.Error(w, "encode error", 500)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	// gzip larger responses: chat lists and history compress 5-10x
	if len(b) > 600 && strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") {
		var buf bytes.Buffer
		gz, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
		_, _ = gz.Write(b)
		_ = gz.Close()
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Set("Vary", "Accept-Encoding")
		w.WriteHeader(code)
		_, _ = w.Write(buf.Bytes())
		return
	}
	w.WriteHeader(code)
	_, _ = w.Write(b)
}

func fail(w http.ResponseWriter, r *http.Request, code int, msg string) {
	writeJSON(w, r, code, apiError{Error: msg})
}

func readJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
	return dec.Decode(v)
}

func pathID(r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	return id, err == nil && id > 0
}

func uidOf(r *http.Request) int64 { return r.Context().Value(uidKey).(int64) }

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func sha(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

func clientIP(r *http.Request) string {
	if xf := r.Header.Get("X-Real-IP"); xf != "" {
		return xf
	}
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	return host
}

func (s *Server) logMW(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		h.ServeHTTP(w, r)
		if r.URL.Path != "/ws" && r.URL.Path != "/health" {
			log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start).Round(time.Millisecond))
		}
	})
}

// auth accepts "Authorization: Bearer <token>" or "?t=<token>" (for media URLs / websocket).
func (s *Server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if tok == "" {
			tok = r.URL.Query().Get("t")
		}
		if tok == "" {
			fail(w, r, 401, "unauthorized")
			return
		}
		var uid int64
		err := s.db.QueryRowContext(r.Context(),
			`UPDATE sessions SET last_used=now() WHERE token_hash=$1 RETURNING user_id`, sha(tok)).Scan(&uid)
		if err != nil {
			fail(w, r, 401, "unauthorized")
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), uidKey, uid)))
	}
}

// ---------- rate limiter (per key, sliding window) ----------

type Limiter struct {
	mu   sync.Mutex
	hits map[string][]time.Time
}

func newLimiter() *Limiter {
	l := &Limiter{hits: map[string][]time.Time{}}
	go func() {
		for range time.Tick(10 * time.Minute) {
			l.mu.Lock()
			for k, v := range l.hits {
				if len(v) == 0 || time.Since(v[len(v)-1]) > time.Hour {
					delete(l.hits, k)
				}
			}
			l.mu.Unlock()
		}
	}()
	return l
}

func (l *Limiter) allow(key string, max int, per time.Duration) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	v := l.hits[key][:0]
	for _, t := range l.hits[key] {
		if now.Sub(t) < per {
			v = append(v, t)
		}
	}
	if len(v) >= max {
		l.hits[key] = v
		return false
	}
	l.hits[key] = append(v, now)
	return true
}

var errNotFound = errors.New("not found")

func isNoRows(err error) bool { return errors.Is(err, sql.ErrNoRows) }

func errf(format string, a ...any) error { return fmt.Errorf(format, a...) }
