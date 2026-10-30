package main

import (
	"context"
	"database/sql"
	"time"

	"github.com/lib/pq"
)

const schema = `
CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  phone TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  about TEXT NOT NULL DEFAULT '',
  avatar TEXT NOT NULL DEFAULT '',
  lang TEXT NOT NULL DEFAULT 'tk',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
CREATE TABLE IF NOT EXISTS sms_codes (
  phone TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS chats (
  id BIGSERIAL PRIMARY KEY,
  kind SMALLINT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  avatar TEXT NOT NULL DEFAULT '',
  direct_key TEXT UNIQUE,
  created_by BIGINT REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS chat_members (
  chat_id BIGINT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role SMALLINT NOT NULL DEFAULT 0,
  last_read_id BIGINT NOT NULL DEFAULT 0,
  muted BOOLEAN NOT NULL DEFAULT false,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (chat_id, user_id)
);
CREATE INDEX IF NOT EXISTS chat_members_user ON chat_members(user_id);
CREATE TABLE IF NOT EXISTS media (
  id TEXT PRIMARY KEY,
  owner_id BIGINT NOT NULL REFERENCES users(id),
  mime TEXT NOT NULL,
  size BIGINT NOT NULL,
  width INT NOT NULL DEFAULT 0,
  height INT NOT NULL DEFAULT 0,
  duration_ms INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS messages (
  id BIGSERIAL PRIMARY KEY,
  chat_id BIGINT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  sender_id BIGINT NOT NULL REFERENCES users(id),
  cid TEXT NOT NULL,
  kind SMALLINT NOT NULL,
  text TEXT NOT NULL DEFAULT '',
  media_id TEXT REFERENCES media(id),
  reply_to BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  edited_at TIMESTAMPTZ,
  deleted BOOLEAN NOT NULL DEFAULT false,
  UNIQUE (sender_id, cid)
);
CREATE INDEX IF NOT EXISTS messages_chat ON messages(chat_id, id);
CREATE TABLE IF NOT EXISTS reactions (
  message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL,
  PRIMARY KEY (message_id, user_id)
);
`

func migrate(db *sql.DB) error {
	_, err := db.Exec(schema)
	return err
}

// ---------- JSON models (short keys = less traffic on slow networks) ----------

const (
	ChatDirect = 1
	ChatGroup  = 2

	MsgText   = 1
	MsgImage  = 2
	MsgVoice  = 3
	MsgSystem = 4
)

type User struct {
	ID     int64  `json:"id"`
	Phone  string `json:"phone"`
	Name   string `json:"name"`
	About  string `json:"about,omitempty"`
	Avatar string `json:"avatar,omitempty"`
	Lang   string `json:"lang,omitempty"`
	Seen   int64  `json:"seen"`
	Online bool   `json:"on"`
}

type MediaInfo struct {
	ID   string `json:"id"`
	Mime string `json:"mt"`
	Size int64  `json:"sz"`
	W    int    `json:"w,omitempty"`
	H    int    `json:"h,omitempty"`
	Dur  int    `json:"d,omitempty"`
}

type Message struct {
	ID        int64              `json:"id"`
	Chat      int64              `json:"chat"`
	From      int64              `json:"from"`
	CID       string             `json:"cid"`
	Kind      int                `json:"k"`
	Text      string             `json:"tx,omitempty"`
	Media     *MediaInfo         `json:"m,omitempty"`
	Reply     int64              `json:"re,omitempty"`
	TS        int64              `json:"ts"`
	Edited    bool               `json:"ed,omitempty"`
	Deleted   bool               `json:"del,omitempty"`
	Reactions map[string][]int64 `json:"rx,omitempty"`
}

type Member struct {
	ID     int64  `json:"id"`
	Name   string `json:"name"`
	Phone  string `json:"phone"`
	Avatar string `json:"avatar,omitempty"`
	Seen   int64  `json:"seen"`
	Online bool   `json:"on"`
	Read   int64  `json:"rd"`
	Role   int    `json:"role,omitempty"`
}

type Chat struct {
	ID      int64    `json:"id"`
	Kind    int      `json:"kind"`
	Title   string   `json:"title,omitempty"`
	Avatar  string   `json:"avatar,omitempty"`
	Members []Member `json:"members"`
	Last    *Message `json:"last,omitempty"`
	Unread  int      `json:"unread"`
	MyRead  int64    `json:"myRead"`
	Muted   bool     `json:"muted,omitempty"`
	Created int64    `json:"created"`
}

func ms(t time.Time) int64 { return t.UnixMilli() }

// ---------- queries ----------

const userCols = `id, phone, name, about, avatar, lang, last_seen`

func (s *Server) scanUser(row interface{ Scan(...any) error }) (*User, error) {
	var u User
	var seen time.Time
	if err := row.Scan(&u.ID, &u.Phone, &u.Name, &u.About, &u.Avatar, &u.Lang, &seen); err != nil {
		return nil, err
	}
	u.Seen = ms(seen)
	u.Online = s.hub.online(u.ID)
	return &u, nil
}

func (s *Server) getUser(ctx context.Context, id int64) (*User, error) {
	return s.scanUser(s.db.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE id=$1`, id))
}

const msgSelect = `
SELECT m.id, m.chat_id, m.sender_id, m.cid, m.kind, m.text, m.reply_to, m.created_at,
       m.edited_at IS NOT NULL, m.deleted,
       md.id, md.mime, md.size, md.width, md.height, md.duration_ms
FROM messages m LEFT JOIN media md ON md.id = m.media_id `

func scanMessage(row interface{ Scan(...any) error }) (*Message, error) {
	var m Message
	var reply sql.NullInt64
	var created time.Time
	var mID, mMime sql.NullString
	var mSize sql.NullInt64
	var mW, mH, mD sql.NullInt32
	if err := row.Scan(&m.ID, &m.Chat, &m.From, &m.CID, &m.Kind, &m.Text, &reply, &created,
		&m.Edited, &m.Deleted, &mID, &mMime, &mSize, &mW, &mH, &mD); err != nil {
		return nil, err
	}
	m.TS = ms(created)
	m.Reply = reply.Int64
	if m.Deleted {
		m.Text = ""
		return &m, nil
	}
	if mID.Valid {
		m.Media = &MediaInfo{ID: mID.String, Mime: mMime.String, Size: mSize.Int64,
			W: int(mW.Int32), H: int(mH.Int32), Dur: int(mD.Int32)}
	}
	return &m, nil
}

func (s *Server) getMessage(ctx context.Context, id int64) (*Message, error) {
	m, err := scanMessage(s.db.QueryRowContext(ctx, msgSelect+`WHERE m.id=$1`, id))
	if err != nil {
		return nil, err
	}
	if err := s.attachReactions(ctx, []*Message{m}); err != nil {
		return nil, err
	}
	return m, nil
}

func (s *Server) queryMessages(ctx context.Context, where string, args ...any) ([]*Message, error) {
	rows, err := s.db.QueryContext(ctx, msgSelect+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Message{}
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, s.attachReactions(ctx, out)
}

func (s *Server) attachReactions(ctx context.Context, msgs []*Message) error {
	if len(msgs) == 0 {
		return nil
	}
	ids := make([]int64, 0, len(msgs))
	idx := map[int64]*Message{}
	for _, m := range msgs {
		ids = append(ids, m.ID)
		idx[m.ID] = m
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT message_id, emoji, user_id FROM reactions WHERE message_id = ANY($1)`, pq.Array(ids))
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var mid, uid int64
		var e string
		if err := rows.Scan(&mid, &e, &uid); err != nil {
			return err
		}
		m := idx[mid]
		if m.Reactions == nil {
			m.Reactions = map[string][]int64{}
		}
		m.Reactions[e] = append(m.Reactions[e], uid)
	}
	return rows.Err()
}

func (s *Server) isMember(ctx context.Context, chatID, uid int64) bool {
	var ok bool
	_ = s.db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM chat_members WHERE chat_id=$1 AND user_id=$2)`, chatID, uid).Scan(&ok)
	return ok
}

func (s *Server) memberIDs(ctx context.Context, chatID int64) ([]int64, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT user_id FROM chat_members WHERE chat_id=$1`, chatID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// listChats returns chats of user (all, or only the given ids).
func (s *Server) listChats(ctx context.Context, uid int64, only []int64) ([]*Chat, error) {
	q := `
SELECT c.id, c.kind, c.title, c.avatar, c.created_at, cm.last_read_id, cm.muted, lm.id,
  (SELECT count(*) FROM messages x
     WHERE x.chat_id=c.id AND x.id>cm.last_read_id AND x.sender_id<>$1 AND NOT x.deleted)
FROM chat_members cm
JOIN chats c ON c.id = cm.chat_id
LEFT JOIN LATERAL (SELECT id, created_at FROM messages WHERE chat_id=c.id ORDER BY id DESC LIMIT 1) lm ON true
WHERE cm.user_id=$1 AND ($2::bigint[] IS NULL OR c.id = ANY($2))
ORDER BY COALESCE(lm.created_at, c.created_at) DESC
LIMIT 500`
	var onlyArg any
	if only != nil {
		onlyArg = pq.Array(only)
	}
	rows, err := s.db.QueryContext(ctx, q, uid, onlyArg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var chats []*Chat
	idx := map[int64]*Chat{}
	var lastIDs []int64
	var chatIDs []int64
	for rows.Next() {
		var c Chat
		var created time.Time
		var last sql.NullInt64
		if err := rows.Scan(&c.ID, &c.Kind, &c.Title, &c.Avatar, &created, &c.MyRead, &c.Muted, &last, &c.Unread); err != nil {
			return nil, err
		}
		c.Created = ms(created)
		c.Members = []Member{}
		chats = append(chats, &c)
		idx[c.ID] = &c
		chatIDs = append(chatIDs, c.ID)
		if last.Valid {
			lastIDs = append(lastIDs, last.Int64)
		}
	}
	rows.Close()
	if len(chats) == 0 {
		return []*Chat{}, nil
	}
	// members
	mrows, err := s.db.QueryContext(ctx, `
SELECT cm.chat_id, u.id, u.name, u.phone, u.avatar, u.last_seen, cm.last_read_id, cm.role
FROM chat_members cm JOIN users u ON u.id=cm.user_id
WHERE cm.chat_id = ANY($1) ORDER BY cm.joined_at`, pq.Array(chatIDs))
	if err != nil {
		return nil, err
	}
	defer mrows.Close()
	for mrows.Next() {
		var cid int64
		var m Member
		var seen time.Time
		if err := mrows.Scan(&cid, &m.ID, &m.Name, &m.Phone, &m.Avatar, &seen, &m.Read, &m.Role); err != nil {
			return nil, err
		}
		m.Seen = ms(seen)
		m.Online = s.hub.online(m.ID)
		idx[cid].Members = append(idx[cid].Members, m)
	}
	mrows.Close()
	// last messages
	if len(lastIDs) > 0 {
		msgs, err := s.queryMessages(ctx, `WHERE m.id = ANY($1)`, pq.Array(lastIDs))
		if err != nil {
			return nil, err
		}
		for _, m := range msgs {
			if c := idx[m.Chat]; c != nil {
				c.Last = m
			}
		}
	}
	return chats, nil
}

func (s *Server) getChat(ctx context.Context, uid, chatID int64) (*Chat, error) {
	chats, err := s.listChats(ctx, uid, []int64{chatID})
	if err != nil {
		return nil, err
	}
	if len(chats) == 0 {
		return nil, sql.ErrNoRows
	}
	return chats[0], nil
}
