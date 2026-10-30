package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/coder/websocket"
)

type ctxT = context.Context

// ---------- hub: who is connected ----------

type Conn struct {
	uid  int64
	ws   *websocket.Conn
	send chan []byte
	once sync.Once
	done chan struct{}
}

func (c *Conn) close() { c.once.Do(func() { close(c.done) }) }

type Hub struct {
	mu    sync.RWMutex
	conns map[int64]map[*Conn]struct{}
}

func newHub() *Hub { return &Hub{conns: map[int64]map[*Conn]struct{}{}} }

func (h *Hub) add(c *Conn) (first bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	m := h.conns[c.uid]
	if m == nil {
		m = map[*Conn]struct{}{}
		h.conns[c.uid] = m
	}
	m[c] = struct{}{}
	return len(m) == 1
}

func (h *Hub) remove(c *Conn) (last bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	m := h.conns[c.uid]
	delete(m, c)
	if len(m) == 0 {
		delete(h.conns, c.uid)
		return true
	}
	return false
}

func (h *Hub) online(uid int64) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.conns[uid]) > 0
}

func (h *Hub) count() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.conns)
}

func (h *Hub) sendTo(uids []int64, payload []byte, except *Conn) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, uid := range uids {
		for c := range h.conns[uid] {
			if c == except {
				continue
			}
			select {
			case c.send <- payload:
			default:
				c.close() // client too slow: drop, it will resync on reconnect
			}
		}
	}
}

// ---------- protocol ----------

type in struct {
	T    string `json:"t"`
	CID  string `json:"cid,omitempty"`
	Chat int64  `json:"chat,omitempty"`
	K    int    `json:"k,omitempty"`
	Tx   string `json:"tx,omitempty"`
	M    string `json:"m,omitempty"`
	Re   int64  `json:"re,omitempty"`
	ID   int64  `json:"id,omitempty"`
	E    string `json:"e,omitempty"`
	Rec  bool   `json:"rec,omitempty"`
}

type out struct {
	T    string   `json:"t"`
	CID  string   `json:"cid,omitempty"`
	Msg  *Message `json:"msg,omitempty"`
	Chat any      `json:"chat,omitempty"`
	User int64    `json:"user,omitempty"`
	ID   int64    `json:"id,omitempty"`
	E    string   `json:"e,omitempty"`
	On   *bool    `json:"on,omitempty"`
	Seen int64    `json:"seen,omitempty"`
	Rec  bool     `json:"rec,omitempty"`
	Err  string   `json:"err,omitempty"`
}

func encode(o out) []byte {
	b, _ := json.Marshal(o)
	return b
}

func (s *Server) broadcastToChat(ctx ctxT, chatID int64, o out, except *Conn) {
	ids, err := s.memberIDs(ctx, chatID)
	if err != nil {
		return
	}
	s.hub.sendTo(ids, encode(o), except)
}

// ---------- connection lifecycle ----------

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	uid := uidOf(r)
	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// permessage-deflate with context takeover: repeated JSON keys compress very well
		CompressionMode:      websocket.CompressionContextTakeover,
		CompressionThreshold: 128,
		InsecureSkipVerify:   true, // native mobile clients send no Origin header
	})
	if err != nil {
		return
	}
	ws.SetReadLimit(64 << 10)
	c := &Conn{uid: uid, ws: ws, send: make(chan []byte, 256), done: make(chan struct{})}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if s.hub.add(c) {
		s.presence(ctx, uid, true)
	}
	defer func() {
		if s.hub.remove(c) {
			_, _ = s.db.Exec(`UPDATE users SET last_seen=now() WHERE id=$1`, uid)
			s.presence(context.Background(), uid, false)
		}
		ws.Close(websocket.StatusNormalClosure, "")
	}()

	// writer + keepalive
	go func() {
		ping := time.NewTicker(25 * time.Second)
		defer ping.Stop()
		for {
			select {
			case b := <-c.send:
				wctx, wc := context.WithTimeout(ctx, 20*time.Second)
				err := ws.Write(wctx, websocket.MessageText, b)
				wc()
				if err != nil {
					c.close()
					return
				}
			case <-ping.C:
				pctx, pc := context.WithTimeout(ctx, 20*time.Second)
				err := ws.Ping(pctx)
				pc()
				if err != nil {
					c.close()
					return
				}
			case <-c.done:
				cancel()
				return
			case <-ctx.Done():
				return
			}
		}
	}()

	_, _ = s.db.Exec(`UPDATE users SET last_seen=now() WHERE id=$1`, uid)
	c.send <- encode(out{T: "hello", User: uid})

	for {
		_, data, err := ws.Read(ctx)
		if err != nil {
			c.close()
			return
		}
		var m in
		if json.Unmarshal(data, &m) != nil {
			continue
		}
		s.dispatch(ctx, c, &m)
	}
}

func (s *Server) presence(ctx ctxT, uid int64, on bool) {
	rows, err := s.db.QueryContext(ctx, `
SELECT DISTINCT cm2.user_id FROM chat_members cm1
JOIN chats c ON c.id=cm1.chat_id AND c.kind=1
JOIN chat_members cm2 ON cm2.chat_id=cm1.chat_id AND cm2.user_id<>$1
WHERE cm1.user_id=$1`, uid)
	if err != nil {
		return
	}
	var peers []int64
	for rows.Next() {
		var id int64
		if rows.Scan(&id) == nil {
			peers = append(peers, id)
		}
	}
	rows.Close()
	s.hub.sendTo(peers, encode(out{T: "pres", User: uid, On: &on, Seen: time.Now().UnixMilli()}), nil)
}

func (s *Server) reply(c *Conn, o out) {
	select {
	case c.send <- encode(o):
	default:
	}
}

func (s *Server) dispatch(ctx ctxT, c *Conn, m *in) {
	switch m.T {
	case "ping":
		s.reply(c, out{T: "pong"})
	case "send":
		s.onSend(ctx, c, m)
	case "read":
		s.onRead(ctx, c, m)
	case "typing":
		if s.isMember(ctx, m.Chat, c.uid) {
			s.broadcastToChat(ctx, m.Chat, out{T: "typing", Chat: m.Chat, User: c.uid, Rec: m.Rec}, nil)
			// sender's own devices will ignore typing from self on client side
		}
	case "react":
		s.onReact(ctx, c, m)
	case "del":
		s.onDelete(ctx, c, m)
	case "edit":
		s.onEdit(ctx, c, m)
	}
}

func (s *Server) onSend(ctx ctxT, c *Conn, m *in) {
	if m.CID == "" || len(m.CID) > 64 {
		s.reply(c, out{T: "err", CID: m.CID, Err: "bad_cid"})
		return
	}
	if !s.isMember(ctx, m.Chat, c.uid) {
		s.reply(c, out{T: "err", CID: m.CID, Err: "forbidden"})
		return
	}
	text := strings.TrimSpace(m.Tx)
	var mediaID any
	switch m.K {
	case MsgText:
		if text == "" || utf8.RuneCountInString(text) > 4096 {
			s.reply(c, out{T: "err", CID: m.CID, Err: "bad_text"})
			return
		}
	case MsgImage, MsgVoice:
		var owner int64
		if err := s.db.QueryRowContext(ctx, `SELECT owner_id FROM media WHERE id=$1`, m.M).Scan(&owner); err != nil || owner != c.uid {
			s.reply(c, out{T: "err", CID: m.CID, Err: "bad_media"})
			return
		}
		mediaID = m.M
		text = truncate(text, 1024) // caption
	default:
		s.reply(c, out{T: "err", CID: m.CID, Err: "bad_kind"})
		return
	}
	var reply any
	if m.Re > 0 {
		reply = m.Re
	}
	var id int64
	err := s.db.QueryRowContext(ctx, `
INSERT INTO messages(chat_id,sender_id,cid,kind,text,media_id,reply_to) VALUES($1,$2,$3,$4,$5,$6,$7)
ON CONFLICT (sender_id,cid) DO NOTHING RETURNING id`,
		m.Chat, c.uid, m.CID, m.K, text, mediaID, reply).Scan(&id)
	dup := false
	if isNoRows(err) { // already received (client resent after reconnect)
		dup = true
		err = s.db.QueryRowContext(ctx, `SELECT id FROM messages WHERE sender_id=$1 AND cid=$2`, c.uid, m.CID).Scan(&id)
	}
	if err != nil {
		log.Println("send:", err)
		s.reply(c, out{T: "err", CID: m.CID, Err: "db"})
		return
	}
	msg, err := s.getMessage(ctx, id)
	if err != nil {
		s.reply(c, out{T: "err", CID: m.CID, Err: "db"})
		return
	}
	s.reply(c, out{T: "ack", CID: m.CID, Msg: msg})
	if dup {
		return
	}
	_, _ = s.db.ExecContext(ctx, `UPDATE chat_members SET last_read_id=GREATEST(last_read_id,$1) WHERE chat_id=$2 AND user_id=$3`,
		id, m.Chat, c.uid)
	s.broadcastToChat(ctx, m.Chat, out{T: "msg", Msg: msg}, c)
}

func (s *Server) onRead(ctx ctxT, c *Conn, m *in) {
	res, err := s.db.ExecContext(ctx, `UPDATE chat_members SET last_read_id=$1 WHERE chat_id=$2 AND user_id=$3 AND last_read_id<$1`,
		m.ID, m.Chat, c.uid)
	if err != nil {
		return
	}
	if n, _ := res.RowsAffected(); n > 0 {
		s.broadcastToChat(ctx, m.Chat, out{T: "read", Chat: m.Chat, User: c.uid, ID: m.ID}, nil)
	}
}

func (s *Server) msgChat(ctx ctxT, msgID int64) (chat, sender int64, ok bool) {
	err := s.db.QueryRowContext(ctx, `SELECT chat_id, sender_id FROM messages WHERE id=$1 AND NOT deleted`, msgID).Scan(&chat, &sender)
	return chat, sender, err == nil
}

func (s *Server) onReact(ctx ctxT, c *Conn, m *in) {
	chat, _, ok := s.msgChat(ctx, m.ID)
	if !ok || !s.isMember(ctx, chat, c.uid) {
		return
	}
	if m.E == "" {
		_, _ = s.db.ExecContext(ctx, `DELETE FROM reactions WHERE message_id=$1 AND user_id=$2`, m.ID, c.uid)
	} else {
		if utf8.RuneCountInString(m.E) > 8 {
			return
		}
		_, _ = s.db.ExecContext(ctx, `INSERT INTO reactions(message_id,user_id,emoji) VALUES($1,$2,$3)
ON CONFLICT (message_id,user_id) DO UPDATE SET emoji=$3`, m.ID, c.uid, m.E)
	}
	s.broadcastToChat(ctx, chat, out{T: "rx", Chat: chat, ID: m.ID, User: c.uid, E: m.E}, nil)
}

func (s *Server) onDelete(ctx ctxT, c *Conn, m *in) {
	chat, sender, ok := s.msgChat(ctx, m.ID)
	if !ok || sender != c.uid {
		return
	}
	_, _ = s.db.ExecContext(ctx, `UPDATE messages SET deleted=true, text='', media_id=NULL WHERE id=$1`, m.ID)
	if msg, err := s.getMessage(ctx, m.ID); err == nil {
		s.broadcastToChat(ctx, chat, out{T: "upd", Msg: msg}, nil)
	}
}

func (s *Server) onEdit(ctx ctxT, c *Conn, m *in) {
	chat, sender, ok := s.msgChat(ctx, m.ID)
	text := strings.TrimSpace(m.Tx)
	if !ok || sender != c.uid || text == "" || utf8.RuneCountInString(text) > 4096 {
		return
	}
	_, _ = s.db.ExecContext(ctx, `UPDATE messages SET text=$1, edited_at=now() WHERE id=$2 AND kind=1`, text, m.ID)
	if msg, err := s.getMessage(ctx, m.ID); err == nil {
		s.broadcastToChat(ctx, chat, out{T: "upd", Msg: msg}, nil)
	}
}
