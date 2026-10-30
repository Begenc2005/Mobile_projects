package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/lib/pq"
)

type ctxKey struct{}

type User struct {
	ID    int64  `json:"id"`
	Phone string `json:"phone"`
	Name  string `json:"name"`
}

func me(r *http.Request) *User {
	u, _ := r.Context().Value(ctxKey{}).(*User)
	return u
}

func auth(h http.HandlerFunc) http.HandlerFunc { return authMW(h, false) }

// optAuth: вход не обязателен, но если токен есть — пользователь известен.
func optAuth(h http.HandlerFunc) http.HandlerFunc { return authMW(h, true) }

func authMW(h http.HandlerFunc, optional bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if optional && tok == "" {
			h(w, r)
			return
		}
		if len(tok) < 20 {
			fail(w, r, 401, "auth")
			return
		}
		th := hashStr(tok)
		u := &User{}
		var blocked, stale bool
		err := db.QueryRow(`SELECT u.id,u.phone,u.name,u.blocked, s.seen_at < now()-interval '1 day'
			FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.th=$1`, th).
			Scan(&u.ID, &u.Phone, &u.Name, &blocked, &stale)
		if err != nil {
			fail(w, r, 401, "auth")
			return
		}
		if blocked {
			fail(w, r, 403, "blocked")
			return
		}
		if stale {
			db.Exec(`UPDATE sessions SET seen_at=now() WHERE th=$1`, th)
		}
		h(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, u)))
	}
}

// ---------- справочники ----------

func hMeta(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("ETag", metaTag)
	w.Header().Set("Cache-Control", "no-cache")
	if r.Header.Get("If-None-Match") == metaTag {
		w.WriteHeader(304)
		return
	}
	writeRaw(w, r, 200, metaJSON)
}

// ---------- вход по SMS ----------

func hAuthSend(w http.ResponseWriter, r *http.Request) {
	var in struct{ Phone string }
	if !readBody(r, &in) {
		fail(w, r, 400, "bad")
		return
	}
	p := normPhone(in.Phone)
	if p == "" {
		fail(w, r, 400, "phone")
		return
	}
	if !lim.allow("ip:"+clientIP(r), 20, time.Hour) ||
		!lim.allow("p1:"+p, 1, 55*time.Second) ||
		!lim.allow("ph:"+p, 6, time.Hour) {
		fail(w, r, 429, "wait")
		return
	}
	code := fmt.Sprintf("%06d", func() int64 { n, _ := rand.Int(rand.Reader, big.NewInt(1000000)); return n.Int64() }())
	if p == cfg.DemoPhone && cfg.DemoCode != "" {
		code = cfg.DemoCode
	}
	_, err := db.Exec(`INSERT INTO otps(phone,ch,exp,tries) VALUES($1,$2,now()+interval '5 min',0)
		ON CONFLICT(phone) DO UPDATE SET ch=$2, exp=now()+interval '5 min', tries=0`, p, hashStr(cfg.Secret, p, code))
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	if p != cfg.DemoPhone {
		// Без «ş» — SMS уходит в 7-битной кодировке, это дешевле. Формат удобен для автоподстановки iOS.
		msg := "Busluk kody: " + code
		if cfg.SMS == nil {
			log.Printf("SMS %s: %s", p, msg)
		} else if err := cfg.SMS.Send(p, msg); err != nil {
			log.Printf("SMS %s ошибка: %v", p, err)
			fail(w, r, 502, "sms")
			return
		}
	}
	writeJSON(w, r, 200, map[string]any{"ok": true, "len": 6})
}

func hAuthVerify(w http.ResponseWriter, r *http.Request) {
	var in struct{ Phone, Code string }
	if !readBody(r, &in) {
		fail(w, r, 400, "bad")
		return
	}
	p := normPhone(in.Phone)
	var ch []byte
	var tries int
	err := db.QueryRow(`UPDATE otps SET tries=tries+1 WHERE phone=$1 AND exp>now() RETURNING ch,tries`, p).Scan(&ch, &tries)
	if err != nil || tries > 5 {
		fail(w, r, 400, "expired")
		return
	}
	if string(ch) != string(hashStr(cfg.Secret, p, strings.TrimSpace(in.Code))) {
		fail(w, r, 400, "code")
		return
	}
	db.Exec(`DELETE FROM otps WHERE phone=$1`, p)
	u := &User{Phone: p}
	var blocked bool
	err = db.QueryRow(`INSERT INTO users(phone) VALUES($1) ON CONFLICT(phone) DO UPDATE SET phone=EXCLUDED.phone
		RETURNING id,name,blocked`, p).Scan(&u.ID, &u.Name, &blocked)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	if blocked {
		fail(w, r, 403, "blocked")
		return
	}
	tok := randHex(24)
	db.Exec(`INSERT INTO sessions(th,user_id) VALUES($1,$2)`, hashStr(tok), u.ID)
	writeJSON(w, r, 200, map[string]any{"token": tok, "user": u})
}

func hLogout(w http.ResponseWriter, r *http.Request) {
	db.Exec(`DELETE FROM sessions WHERE th=$1`, hashStr(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")))
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

func hMe(w http.ResponseWriter, r *http.Request) { writeJSON(w, r, 200, me(r)) }

func hMeSave(w http.ResponseWriter, r *http.Request) {
	var in struct{ Name string }
	if !readBody(r, &in) {
		fail(w, r, 400, "bad")
		return
	}
	n := strings.TrimSpace(in.Name)
	if utf8.RuneCountInString(n) > 40 {
		fail(w, r, 400, "name")
		return
	}
	u := me(r)
	db.Exec(`UPDATE users SET name=$1 WHERE id=$2`, n, u.ID)
	u.Name = n
	writeJSON(w, r, 200, u)
}

// ---------- лента и поиск ----------

// Item — краткая карточка. Короткие ключи экономят ~40% трафика списка.
type Item struct {
	I int64  `json:"i"`
	T string `json:"t"`
	P int64  `json:"p"`
	N bool   `json:"n,omitempty"` // цена договорная
	C int    `json:"c"`           // город
	G int    `json:"g"`           // категория
	F string `json:"f,omitempty"` // фото (миниатюра: /i/{f}_t.jpg)
	D int64  `json:"d"`           // дата поднятия, unix
	V bool   `json:"v,omitempty"` // VIP
	S int    `json:"s,omitempty"` // статус (только «мои»)
	X int64  `json:"x,omitempty"` // VIP до (только «мои»)
	W int    `json:"w,omitempty"` // просмотры (только «мои»)
}

const itemCols = `a.id,a.title,a.price,a.neg,a.city,a.cat,coalesce(a.photos[1],''),extract(epoch from a.bumped_at)::bigint,
	coalesce(a.vip_until>now(),false),a.status,coalesce(extract(epoch from a.vip_until)::bigint,0),a.views`

func scanItems(rows *sql.Rows, own bool) []Item {
	defer rows.Close()
	out := []Item{}
	for rows.Next() {
		var it Item
		if rows.Scan(&it.I, &it.T, &it.P, &it.N, &it.C, &it.G, &it.F, &it.D, &it.V, &it.S, &it.X, &it.W) == nil {
			if !own {
				it.S, it.X, it.W = 0, 0, 0
			}
			out = append(out, it)
		}
	}
	return out
}

var attrFilterRe = regexp.MustCompile(`^[a-z]+$`)

// Параметры: q (текст), g (категория, вкл. дочерние), c (город), r (регион),
// pmin/pmax, f=brand:toyota,year:2010-2018 (атрибуты), s=new|cheap|dear, o (смещение).
func hList(w http.ResponseWriter, r *http.Request) {
	qp := r.URL.Query()
	var where []string
	var args []any
	arg := func(v any) string { args = append(args, v); return "$" + strconv.Itoa(len(args)) }

	where = append(where, "status=0")
	if g, _ := strconv.Atoi(qp.Get("g")); g > 0 {
		where = append(where, "cat = ANY("+arg(pq.Array(catTree(g)))+")")
	}
	if c, _ := strconv.Atoi(qp.Get("c")); c > 0 {
		where = append(where, "city="+arg(c))
	} else if rg, _ := strconv.Atoi(qp.Get("r")); rg > 0 {
		where = append(where, "region="+arg(rg))
	}
	if v, err := strconv.ParseInt(qp.Get("pmin"), 10, 64); err == nil {
		where = append(where, "price>="+arg(v))
	}
	if v, err := strconv.ParseInt(qp.Get("pmax"), 10, 64); err == nil {
		where = append(where, "price<="+arg(v))
	}
	if qp.Get("ph") == "1" {
		where = append(where, "cardinality(photos)>0")
	}
	for _, f := range strings.Split(qp.Get("f"), ",") {
		k, v, ok := strings.Cut(f, ":")
		at := attrByK[k]
		if !ok || at == nil || !attrFilterRe.MatchString(k) {
			continue
		}
		if at.Y == "s" {
			b, _ := json.Marshal(map[string]string{k: v})
			where = append(where, "attrs @> "+arg(string(b))+"::jsonb")
			continue
		}
		lo, hi, _ := strings.Cut(v, "-")
		if n, err := strconv.ParseInt(lo, 10, 64); err == nil {
			where = append(where, "(attrs->>'"+k+"')::numeric >= "+arg(n))
		}
		if n, err := strconv.ParseInt(hi, 10, 64); err == nil {
			where = append(where, "(attrs->>'"+k+"')::numeric <= "+arg(n))
		}
	}
	q := norm(qp.Get("q"))
	if utf8.RuneCountInString(q) > 60 {
		q = string([]rune(q)[:60])
	}
	toks := strings.Fields(q)
	if len(toks) > 5 {
		toks = toks[:5]
	}
	for _, t := range toks {
		// подстрока ИЛИ похожее слово (опечатки): «таёта», «kamri», «kvartra»
		if utf8.RuneCountInString(t) >= 3 {
			where = append(where, "(sx LIKE "+arg("%"+t+"%")+" OR "+arg(t)+" <% sx)")
		} else {
			where = append(where, "sx LIKE "+arg("%"+t+"%"))
		}
	}
	cond := strings.Join(where, " AND ")

	order := "bumped_at DESC, id DESC"
	switch qp.Get("s") {
	case "cheap":
		order = "price=0, price ASC, id DESC"
	case "dear":
		order = "price DESC, id DESC"
	default:
		if q != "" {
			order = "word_similarity(" + arg(q) + ", sx) DESC, bumped_at DESC"
		}
	}
	off, _ := strconv.Atoi(qp.Get("o"))
	if off < 0 || off > 2000 {
		off = 0
	}
	const page = 20
	rows, err := db.Query(`SELECT `+itemCols+` FROM ads a WHERE `+cond+` ORDER BY `+order+
		` LIMIT `+strconv.Itoa(page+1)+` OFFSET `+strconv.Itoa(off), args...)
	if err != nil {
		log.Print("list: ", err)
		fail(w, r, 500, "db")
		return
	}
	items := scanItems(rows, false)
	more := len(items) > page
	if more {
		items = items[:page]
	}
	resp := map[string]any{"items": items, "more": more}

	// VIP-блок сверху первой страницы: до 4 случайных VIP с теми же фильтрами.
	if off == 0 {
		vrows, err := db.Query(`SELECT `+itemCols+` FROM ads a WHERE `+cond+
			` AND vip_until>now() ORDER BY random() LIMIT 4`, args[:len(args)-countOrderArgs(qp.Get("s"), q)]...)
		if err == nil {
			if v := scanItems(vrows, false); len(v) > 0 {
				resp["vip"] = v
			}
		}
		if g := suggestCats(qp.Get("q")); len(g) > 0 && qp.Get("g") == "" {
			resp["cats"] = g
		}
	}
	writeJSON(w, r, 200, resp)
}

func countOrderArgs(s, q string) int {
	if s != "cheap" && s != "dear" && q != "" {
		return 1
	}
	return 0
}

// Подсказки при наборе: категории (из памяти, мгновенно) + до 6 заголовков.
func hSuggest(w http.ResponseWriter, r *http.Request) {
	q := norm(r.URL.Query().Get("q"))
	resp := map[string]any{"cats": suggestCats(q)}
	if utf8.RuneCountInString(q) >= 3 {
		rows, err := db.Query(`SELECT DISTINCT ON (lower(title)) title FROM ads
			WHERE status=0 AND sx LIKE $1 ORDER BY lower(title) LIMIT 6`, "%"+q+"%")
		if err == nil {
			defer rows.Close()
			var t []string
			for rows.Next() {
				var s string
				rows.Scan(&s)
				t = append(t, s)
			}
			resp["t"] = t
		}
	}
	writeJSON(w, r, 200, resp)
}

// ---------- карточка ----------

type AdFull struct {
	Item
	B    string          `json:"b"`
	A    json.RawMessage `json:"a"`
	Ph   []string        `json:"ph"`
	Tel  string          `json:"tel,omitempty"`
	U    string          `json:"u,omitempty"`
	Own  bool            `json:"own,omitempty"`
	Seen int             `json:"seen"`
}

func loadAd(id int64) (*AdFull, int64, error) {
	a := &AdFull{}
	var uid int64
	var photos pq.StringArray
	var attrs []byte
	err := db.QueryRow(`SELECT `+itemCols+`, a.body, a.attrs, a.photos, a.tel, u.name, a.user_id
		FROM ads a JOIN users u ON u.id=a.user_id WHERE a.id=$1 AND a.status<>4`, id).
		Scan(&a.I, &a.T, &a.P, &a.N, &a.C, &a.G, &a.F, &a.D, &a.V, &a.S, &a.X, &a.W,
			&a.B, &attrs, &photos, &a.Tel, &a.U, &uid)
	a.A, a.Ph, a.Seen = attrs, photos, a.W
	return a, uid, err
}

func hAd(w http.ResponseWriter, r *http.Request) {
	a, uid, err := loadAd(pathID(r))
	if err != nil {
		fail(w, r, 404, "nf")
		return
	}
	u := me(r)
	a.Own = u != nil && u.ID == uid
	if !a.Own {
		if a.S != 0 {
			fail(w, r, 404, "nf")
			return
		}
		a.S, a.X, a.W = 0, 0, 0
		db.Exec(`UPDATE ads SET views=views+1 WHERE id=$1`, a.I)
	}
	if u == nil {
		a.Tel = "" // номер продавца — только вошедшим (защита от сборщиков номеров)
	}
	writeJSON(w, r, 200, a)
}

// ---------- создание и правка ----------

type AdIn struct {
	G     int            `json:"g"`
	C     int            `json:"c"`
	T     string         `json:"t"`
	B     string         `json:"b"`
	P     int64          `json:"p"`
	N     bool           `json:"n"`
	A     map[string]any `json:"a"`
	Ph    []string       `json:"ph"`
	Tel   string         `json:"tel"`
	attrs []byte
	sx    string
	reg   int
}

var photoRe = regexp.MustCompile(`^[0-9]+_[0-9a-f]{16}$`)

func (in *AdIn) validate(u *User) string {
	in.T = strings.TrimSpace(in.T)
	in.B = strings.TrimSpace(in.B)
	switch {
	case !isLeaf(in.G):
		return "cat"
	case cityByID[in.C] == nil:
		return "city"
	case utf8.RuneCountInString(in.T) < 3 || utf8.RuneCountInString(in.T) > 80:
		return "title"
	case utf8.RuneCountInString(in.B) > 3000:
		return "body"
	case in.P < 0 || in.P > 10_000_000_000:
		return "price"
	case len(in.Ph) > 8:
		return "photos"
	}
	in.reg = cityByID[in.C].G
	if in.Ph == nil {
		in.Ph = []string{}
	}
	pref := strconv.FormatInt(u.ID, 10) + "_"
	for _, p := range in.Ph {
		if !photoRe.MatchString(p) || !strings.HasPrefix(p, pref) {
			return "photos"
		}
		if _, err := os.Stat(cfg.DataDir + "/img/" + p + "_t.jpg"); err != nil {
			return "photos"
		}
	}
	if in.Tel = normPhone(in.Tel); in.Tel == "" {
		in.Tel = u.Phone
	}
	allowed := map[string]bool{}
	for _, k := range catAttrs(in.G) {
		allowed[k] = true
	}
	clean := map[string]any{}
	words := []string{in.T, in.B}
	for k, v := range in.A {
		at := attrByK[k]
		if !allowed[k] || at == nil {
			continue
		}
		if at.Y == "n" {
			f, ok := v.(float64)
			if !ok || f < 0 || f > 1e9 {
				return "attr"
			}
			clean[k] = int64(f)
			continue
		}
		s, _ := v.(string)
		found := false
		for _, o := range at.O {
			if o.K == s {
				found = true
				words = append(words, o.R, o.T)
			}
		}
		if !found {
			return "attr"
		}
		clean[k] = s
	}
	in.attrs, _ = json.Marshal(clean)
	in.sx = norm(strings.Join(words, " "))
	return ""
}

func hAdCreate(w http.ResponseWriter, r *http.Request) {
	u := me(r)
	var in AdIn
	if !readBody(r, &in) {
		fail(w, r, 400, "bad")
		return
	}
	if e := in.validate(u); e != "" {
		fail(w, r, 400, e)
		return
	}
	var today int
	db.QueryRow(`SELECT count(*) FROM ads WHERE user_id=$1 AND created_at>now()-interval '1 day'`, u.ID).Scan(&today)
	if today >= 20 {
		fail(w, r, 429, "limit")
		return
	}
	var id int64
	err := db.QueryRow(`INSERT INTO ads(user_id,cat,city,region,title,body,price,neg,attrs,photos,tel,sx)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,
		u.ID, in.G, in.C, in.reg, in.T, in.B, in.P, in.N, in.attrs, pq.Array(in.Ph), in.Tel, in.sx).Scan(&id)
	if err != nil {
		log.Print("create: ", err)
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, map[string]int64{"id": id})
}

func ownAd(r *http.Request) (int64, []string, bool) {
	var photos pq.StringArray
	id := pathID(r)
	err := db.QueryRow(`SELECT photos FROM ads WHERE id=$1 AND user_id=$2 AND status<>4`, id, me(r).ID).Scan(&photos)
	return id, photos, err == nil
}

func hAdUpdate(w http.ResponseWriter, r *http.Request) {
	id, old, ok := ownAd(r)
	if !ok {
		fail(w, r, 404, "nf")
		return
	}
	var in AdIn
	if !readBody(r, &in) {
		fail(w, r, 400, "bad")
		return
	}
	if e := in.validate(me(r)); e != "" {
		fail(w, r, 400, e)
		return
	}
	_, err := db.Exec(`UPDATE ads SET cat=$2,city=$3,region=$4,title=$5,body=$6,price=$7,neg=$8,attrs=$9,photos=$10,tel=$11,sx=$12
		WHERE id=$1`, id, in.G, in.C, in.reg, in.T, in.B, in.P, in.N, in.attrs, pq.Array(in.Ph), in.Tel, in.sx)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	keep := map[string]bool{}
	for _, p := range in.Ph {
		keep[p] = true
	}
	for _, p := range old {
		if !keep[p] {
			removePhoto(p)
		}
	}
	writeJSON(w, r, 200, map[string]int64{"id": id})
}

func hAdDelete(w http.ResponseWriter, r *http.Request) {
	id, photos, ok := ownAd(r)
	if !ok {
		fail(w, r, 404, "nf")
		return
	}
	db.Exec(`UPDATE ads SET status=4, photos='{}' WHERE id=$1`, id)
	for _, p := range photos {
		removePhoto(p)
	}
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

// st=1 — скрыть, st=0 — показать снова (истёкшее объявление продлевается бесплатно).
func hAdState(w http.ResponseWriter, r *http.Request) {
	id, _, ok := ownAd(r)
	var in struct{ St int }
	if !ok || !readBody(r, &in) || (in.St != 0 && in.St != 1) {
		fail(w, r, 400, "bad")
		return
	}
	res, err := db.Exec(`UPDATE ads SET status=$2::smallint,
		bumped_at = CASE WHEN status=3 AND $2::smallint=0 THEN now() ELSE bumped_at END
		WHERE id=$1 AND status IN (0,1,3)`, id, in.St)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		fail(w, r, 403, "blocked")
		return
	}
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

func hReport(w http.ResponseWriter, r *http.Request) {
	var in struct{ Reason string }
	readBody(r, &in)
	if !lim.allow(fmt.Sprint("rep:", me(r).ID), 10, 24*time.Hour) {
		fail(w, r, 429, "wait")
		return
	}
	reason := []rune(in.Reason)
	if len(reason) > 300 {
		reason = reason[:300]
	}
	db.Exec(`INSERT INTO reports(ad_id,user_id,reason) VALUES($1,$2,$3)`, pathID(r), me(r).ID, string(reason))
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

func hMyAds(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query(`SELECT `+itemCols+` FROM ads a WHERE user_id=$1 AND status<>4
		ORDER BY created_at DESC LIMIT 200`, me(r).ID)
	if err != nil {
		fail(w, r, 500, "db")
		return
	}
	writeJSON(w, r, 200, map[string]any{"items": scanItems(rows, true)})
}
