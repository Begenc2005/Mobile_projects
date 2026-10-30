package main

import (
	"database/sql"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/lib/pq"
)

// ---------- profile & users ----------

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	u, err := s.getUser(r.Context(), uidOf(r))
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, u)
}

func (s *Server) handleUpdateMe(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name   *string `json:"name"`
		About  *string `json:"about"`
		Avatar *string `json:"avatar"`
		Lang   *string `json:"lang"`
	}
	if err := readJSON(r, &in); err != nil {
		fail(w, r, 400, "bad_request")
		return
	}
	uid := uidOf(r)
	ctx := r.Context()
	if in.Name != nil {
		n := strings.TrimSpace(truncate(*in.Name, 64))
		if n == "" {
			fail(w, r, 400, "bad_name")
			return
		}
		_, _ = s.db.ExecContext(ctx, `UPDATE users SET name=$1 WHERE id=$2`, n, uid)
	}
	if in.About != nil {
		_, _ = s.db.ExecContext(ctx, `UPDATE users SET about=$1 WHERE id=$2`, truncate(*in.About, 140), uid)
	}
	if in.Avatar != nil {
		_, _ = s.db.ExecContext(ctx, `UPDATE users SET avatar=$1 WHERE id=$2`, truncate(*in.Avatar, 64), uid)
	}
	if in.Lang != nil && (*in.Lang == "tk" || *in.Lang == "ru") {
		_, _ = s.db.ExecContext(ctx, `UPDATE users SET lang=$1 WHERE id=$2`, *in.Lang, uid)
	}
	u, err := s.getUser(ctx, uid)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, u)
}

func (s *Server) handleGetUser(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		fail(w, r, 400, "bad_id")
		return
	}
	u, err := s.getUser(r.Context(), id)
	if err != nil {
		fail(w, r, 404, "not_found")
		return
	}
	writeJSON(w, r, 200, u)
}

func (s *Server) handleSearchUser(w http.ResponseWriter, r *http.Request) {
	phone := normalizePhone(r.URL.Query().Get("phone"))
	if !phoneRe.MatchString(phone) {
		fail(w, r, 400, "bad_phone")
		return
	}
	u, err := s.scanUser(s.db.QueryRowContext(r.Context(), `SELECT `+userCols+` FROM users WHERE phone=$1 AND name<>''`, phone))
	if err != nil {
		fail(w, r, 404, "not_found")
		return
	}
	writeJSON(w, r, 200, u)
}

// handleLookup matches phone-book numbers against registered users.
func (s *Server) handleLookup(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Phones []string `json:"phones"`
	}
	if err := readJSON(r, &in); err != nil || len(in.Phones) > 3000 {
		fail(w, r, 400, "bad_request")
		return
	}
	norm := make([]string, 0, len(in.Phones))
	for _, p := range in.Phones {
		if n := normalizePhone(p); phoneRe.MatchString(n) {
			norm = append(norm, n)
		}
	}
	rows, err := s.db.QueryContext(r.Context(),
		`SELECT `+userCols+` FROM users WHERE phone = ANY($1) AND name<>'' AND id<>$2`, pq.Array(norm), uidOf(r))
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	defer rows.Close()
	out := []*User{}
	for rows.Next() {
		u, err := s.scanUser(rows)
		if err == nil {
			out = append(out, u)
		}
	}
	writeJSON(w, r, 200, out)
}

// ---------- chats ----------

func (s *Server) handleChats(w http.ResponseWriter, r *http.Request) {
	chats, err := s.listChats(r.Context(), uidOf(r), nil)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, chats)
}

func (s *Server) handleChat(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		fail(w, r, 400, "bad_id")
		return
	}
	c, err := s.getChat(r.Context(), uidOf(r), id)
	if err != nil {
		fail(w, r, 404, "not_found")
		return
	}
	writeJSON(w, r, 200, c)
}

func (s *Server) handleDirect(w http.ResponseWriter, r *http.Request) {
	var in struct {
		User int64 `json:"user"`
	}
	if err := readJSON(r, &in); err != nil {
		fail(w, r, 400, "bad_request")
		return
	}
	me := uidOf(r)
	ctx := r.Context()
	if in.User == me {
		fail(w, r, 400, "self")
		return
	}
	if _, err := s.getUser(ctx, in.User); err != nil {
		fail(w, r, 404, "not_found")
		return
	}
	a, b := me, in.User
	if a > b {
		a, b = b, a
	}
	key := fmt.Sprintf("%d:%d", a, b)
	var chatID int64
	err := s.db.QueryRowContext(ctx, `SELECT id FROM chats WHERE direct_key=$1`, key).Scan(&chatID)
	if isNoRows(err) {
		tx, err := s.db.BeginTx(ctx, nil)
		if err != nil {
			fail(w, r, 500, "db")
			return
		}
		defer tx.Rollback()
		err = tx.QueryRowContext(ctx, `
INSERT INTO chats(kind, direct_key, created_by) VALUES($1,$2,$3)
ON CONFLICT (direct_key) DO UPDATE SET direct_key=EXCLUDED.direct_key RETURNING id`,
			ChatDirect, key, me).Scan(&chatID)
		if err != nil {
			fail(w, r, 500, "db")
			return
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO chat_members(chat_id,user_id) VALUES($1,$2),($1,$3) ON CONFLICT DO NOTHING`,
			chatID, me, in.User); err != nil {
			fail(w, r, 500, "db")
			return
		}
		if err := tx.Commit(); err != nil {
			fail(w, r, 500, "db")
			return
		}
	} else if err != nil {
		fail(w, r, 500, "db")
		return
	}
	c, err := s.getChat(ctx, me, chatID)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, c)
}

func (s *Server) handleGroup(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Title   string  `json:"title"`
		Avatar  string  `json:"avatar"`
		Members []int64 `json:"members"`
	}
	if err := readJSON(r, &in); err != nil {
		fail(w, r, 400, "bad_request")
		return
	}
	title := strings.TrimSpace(truncate(in.Title, 64))
	if title == "" || len(in.Members) == 0 || len(in.Members) > 499 {
		fail(w, r, 400, "bad_group")
		return
	}
	me := uidOf(r)
	ctx := r.Context()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	defer tx.Rollback()
	var chatID int64
	if err := tx.QueryRowContext(ctx, `INSERT INTO chats(kind,title,avatar,created_by) VALUES($1,$2,$3,$4) RETURNING id`,
		ChatGroup, title, truncate(in.Avatar, 64), me).Scan(&chatID); err != nil {
		fail(w, r, 500, "db")
		return
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO chat_members(chat_id,user_id,role) VALUES($1,$2,2)`, chatID, me); err != nil {
		fail(w, r, 500, "db")
		return
	}
	if _, err := tx.ExecContext(ctx, `
INSERT INTO chat_members(chat_id,user_id) SELECT $1, id FROM users WHERE id = ANY($2) AND id<>$3
ON CONFLICT DO NOTHING`, chatID, pq.Array(in.Members), me); err != nil {
		fail(w, r, 500, "db")
		return
	}
	if err := tx.Commit(); err != nil {
		fail(w, r, 500, "db")
		return
	}
	s.systemMessage(ctx, chatID, me, "group_created")
	s.notifyChat(ctx, chatID)
	c, err := s.getChat(ctx, me, chatID)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, c)
}

func (s *Server) handleAddMembers(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	var in struct {
		Members []int64 `json:"members"`
	}
	if !ok || readJSON(r, &in) != nil || len(in.Members) == 0 {
		fail(w, r, 400, "bad_request")
		return
	}
	me := uidOf(r)
	ctx := r.Context()
	var role, kind int
	err := s.db.QueryRowContext(ctx, `SELECT cm.role, c.kind FROM chat_members cm JOIN chats c ON c.id=cm.chat_id
WHERE cm.chat_id=$1 AND cm.user_id=$2`, id, me).Scan(&role, &kind)
	if err != nil || kind != ChatGroup || role < 1 {
		fail(w, r, 403, "forbidden")
		return
	}
	if _, err := s.db.ExecContext(ctx, `INSERT INTO chat_members(chat_id,user_id) SELECT $1, id FROM users WHERE id = ANY($2)
ON CONFLICT DO NOTHING`, id, pq.Array(in.Members)); err != nil {
		fail(w, r, 500, "db")
		return
	}
	s.systemMessage(ctx, id, me, "members_added")
	s.notifyChat(ctx, id)
	c, _ := s.getChat(ctx, me, id)
	writeJSON(w, r, 200, c)
}

func (s *Server) handleLeave(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		fail(w, r, 400, "bad_id")
		return
	}
	me := uidOf(r)
	ctx := r.Context()
	var kind int
	if err := s.db.QueryRowContext(ctx, `SELECT kind FROM chats WHERE id=$1`, id).Scan(&kind); err != nil || kind != ChatGroup {
		fail(w, r, 400, "not_group")
		return
	}
	s.systemMessage(ctx, id, me, "member_left")
	_, _ = s.db.ExecContext(ctx, `DELETE FROM chat_members WHERE chat_id=$1 AND user_id=$2`, id, me)
	s.notifyChat(ctx, id)
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

func (s *Server) handleMute(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	var in struct {
		Muted bool `json:"muted"`
	}
	if !ok || readJSON(r, &in) != nil {
		fail(w, r, 400, "bad_request")
		return
	}
	_, _ = s.db.ExecContext(r.Context(), `UPDATE chat_members SET muted=$1 WHERE chat_id=$2 AND user_id=$3`, in.Muted, id, uidOf(r))
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

// ---------- messages ----------

func (s *Server) handleMessages(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		fail(w, r, 400, "bad_id")
		return
	}
	ctx := r.Context()
	if !s.isMember(ctx, id, uidOf(r)) {
		fail(w, r, 403, "forbidden")
		return
	}
	before, _ := strconv.ParseInt(r.URL.Query().Get("before"), 10, 64)
	after, _ := strconv.ParseInt(r.URL.Query().Get("after"), 10, 64)
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	var msgs []*Message
	var err error
	if after > 0 {
		msgs, err = s.queryMessages(ctx, `WHERE m.chat_id=$1 AND m.id>$2 ORDER BY m.id ASC LIMIT $3`, id, after, limit)
	} else {
		msgs, err = s.queryMessages(ctx, `WHERE m.chat_id=$1 AND ($2=0 OR m.id<$2) ORDER BY m.id DESC LIMIT $3`, id, before, limit)
	}
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, msgs)
}

// handleSync returns everything new since the client's last seen message id —
// used after reconnecting on a flaky network.
func (s *Server) handleSync(w http.ResponseWriter, r *http.Request) {
	after, _ := strconv.ParseInt(r.URL.Query().Get("after"), 10, 64)
	const limit = 300
	msgs, err := s.queryMessages(r.Context(), `
WHERE m.chat_id IN (SELECT chat_id FROM chat_members WHERE user_id=$1) AND m.id>$2
ORDER BY m.id ASC LIMIT $3`, uidOf(r), after, limit+1)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	more := len(msgs) > limit
	if more {
		msgs = msgs[:limit]
	}
	writeJSON(w, r, 200, map[string]any{"msgs": msgs, "more": more})
}

// systemMessage stores a service message (group created, member left...) and broadcasts it.
func (s *Server) systemMessage(ctx ctxT, chatID, from int64, code string) {
	var id int64
	err := s.db.QueryRowContext(ctx, `INSERT INTO messages(chat_id,sender_id,cid,kind,text) VALUES($1,$2,$3,$4,$5) RETURNING id`,
		chatID, from, "sys-"+randHex(8), MsgSystem, code).Scan(&id)
	if err != nil {
		return
	}
	if m, err := s.getMessage(ctx, id); err == nil {
		s.broadcastToChat(ctx, chatID, out{T: "msg", Msg: m}, nil)
	}
}

// notifyChat pushes the fresh chat object to every member (new group, members changed).
func (s *Server) notifyChat(ctx ctxT, chatID int64) {
	ids, err := s.memberIDs(ctx, chatID)
	if err != nil {
		return
	}
	for _, uid := range ids {
		if !s.hub.online(uid) {
			continue
		}
		if c, err := s.getChat(ctx, uid, chatID); err == nil {
			s.hub.sendTo([]int64{uid}, encode(out{T: "chat", Chat: c}), nil)
		}
	}
}

// ---------- media ----------

var allowedMime = map[string]string{
	"image/jpeg": "image", "image/png": "image", "image/webp": "image", "image/gif": "image",
	"audio/mp4": "voice", "audio/aac": "voice", "audio/m4a": "voice", "audio/x-m4a": "voice",
	"audio/ogg": "voice", "audio/opus": "voice", "audio/mpeg": "voice", "audio/wav": "voice",
}

func (s *Server) mediaPath(id string) string {
	return filepath.Join(s.cfg.MediaDir, id[:2], id)
}

func (s *Server) handleUpload(w http.ResponseWriter, r *http.Request) {
	uid := uidOf(r)
	if !s.limiter.allow(fmt.Sprintf("up:%d", uid), 120, time.Hour) {
		fail(w, r, 429, "too_many")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, s.cfg.MaxUploadMB<<20)
	file, hdr, err := r.FormFile("file")
	if err != nil {
		fail(w, r, 400, "no_file")
		return
	}
	defer file.Close()

	head := make([]byte, 512)
	n, _ := io.ReadFull(file, head)
	head = head[:n]
	mime := http.DetectContentType(head)
	if _, ok := allowedMime[mime]; !ok {
		// audio containers are often not sniffed; trust declared type for audio only
		declared := strings.ToLower(r.FormValue("mime"))
		if declared == "" {
			declared = strings.ToLower(hdr.Header.Get("Content-Type"))
		}
		if allowedMime[declared] == "voice" {
			mime = declared
		} else {
			fail(w, r, 415, "bad_type")
			return
		}
	}
	id := randHex(16)
	p := s.mediaPath(id)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		fail(w, r, 500, "fs")
		return
	}
	f, err := os.Create(p)
	if err != nil {
		fail(w, r, 500, "fs")
		return
	}
	size, err := io.Copy(f, io.MultiReader(strings.NewReader(string(head)), file))
	f.Close()
	if err != nil {
		os.Remove(p)
		fail(w, r, 400, "too_large")
		return
	}
	atoi := func(k string) int { v, _ := strconv.Atoi(r.FormValue(k)); return v }
	info := MediaInfo{ID: id, Mime: mime, Size: size, W: atoi("w"), H: atoi("h"), Dur: atoi("d")}
	if _, err := s.db.ExecContext(r.Context(),
		`INSERT INTO media(id,owner_id,mime,size,width,height,duration_ms) VALUES($1,$2,$3,$4,$5,$6,$7)`,
		info.ID, uid, info.Mime, info.Size, info.W, info.H, info.Dur); err != nil {
		os.Remove(p)
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, info)
}

func (s *Server) handleMedia(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if len(id) != 32 {
		http.NotFound(w, r)
		return
	}
	var mime string
	var created time.Time
	if err := s.db.QueryRowContext(r.Context(), `SELECT mime, created_at FROM media WHERE id=$1`, id).Scan(&mime, &created); err != nil {
		if err == sql.ErrNoRows {
			http.NotFound(w, r)
		} else {
			http.Error(w, "db", 500)
		}
		return
	}
	f, err := os.Open(s.mediaPath(id))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", mime)
	// media never changes: clients cache forever, no re-downloads on slow networks
	w.Header().Set("Cache-Control", "private, max-age=31536000, immutable")
	w.Header().Set("ETag", `"`+id+`"`)
	http.ServeContent(w, r, "", created, f) // supports Range requests (resume/seek)
}
