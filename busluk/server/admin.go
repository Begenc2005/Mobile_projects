package main

import (
	"crypto/subtle"
	"net/http"
	"strconv"
)

func admin(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		t := r.Header.Get("X-Admin")
		if cfg.AdminToken == "" || subtle.ConstantTimeCompare([]byte(t), []byte(cfg.AdminToken)) != 1 {
			fail(w, r, 401, "admin")
			return
		}
		h(w, r)
	}
}

// Модерация: последние объявления; rep=1 — только с жалобами; q — поиск; st — статус.
func hAdminAds(w http.ResponseWriter, r *http.Request) {
	qp := r.URL.Query()
	where, args := "a.status<>4", []any{}
	if qp.Get("rep") == "1" {
		where += " AND EXISTS(SELECT 1 FROM reports x WHERE x.ad_id=a.id)"
	}
	if s := qp.Get("st"); s != "" {
		st, _ := strconv.Atoi(s)
		args = append(args, st)
		where += " AND a.status=$" + strconv.Itoa(len(args))
	}
	if q := norm(qp.Get("q")); q != "" {
		args = append(args, "%"+q+"%")
		where += " AND (a.sx LIKE $" + strconv.Itoa(len(args)) + " OR u.phone LIKE $" + strconv.Itoa(len(args)) + ")"
	}
	off, _ := strconv.Atoi(qp.Get("o"))
	rows, err := db.Query(`SELECT a.id,a.title,a.price,a.status,u.id,u.phone,u.blocked,
		coalesce(a.photos[1],''),coalesce(a.vip_until>now(),false),
		(SELECT count(*) FROM reports x WHERE x.ad_id=a.id),
		(SELECT coalesce(string_agg(reason,' | '),'') FROM (SELECT reason FROM reports x WHERE x.ad_id=a.id LIMIT 3) z),
		to_char(a.created_at,'DD.MM.YY HH24:MI')
		FROM ads a JOIN users u ON u.id=a.user_id WHERE `+where+` ORDER BY a.id DESC LIMIT 50 OFFSET `+strconv.Itoa(off), args...)
	if err != nil {
		fail(w, r, 500, err.Error())
		return
	}
	defer rows.Close()
	type row struct {
		ID      int64  `json:"id"`
		T       string `json:"t"`
		P       int64  `json:"p"`
		St      int    `json:"st"`
		UID     int64  `json:"uid"`
		Phone   string `json:"phone"`
		UBlock  bool   `json:"ublock"`
		F       string `json:"f"`
		Vip     bool   `json:"vip"`
		Reps    int    `json:"reps"`
		Reasons string `json:"reasons"`
		D       string `json:"d"`
	}
	out := []row{}
	for rows.Next() {
		var x row
		rows.Scan(&x.ID, &x.T, &x.P, &x.St, &x.UID, &x.Phone, &x.UBlock, &x.F, &x.Vip, &x.Reps, &x.Reasons, &x.D)
		out = append(out, x)
	}
	writeJSON(w, r, 200, out)
}

// {st: 0|2} — разблокировать/заблокировать; {vip: дни} — подарить VIP; {bump: true}.
func hAdminAd(w http.ResponseWriter, r *http.Request) {
	var in struct {
		St   *int
		Vip  int
		Bump bool
	}
	if !readBody(r, &in) {
		fail(w, r, 400, "bad")
		return
	}
	id := pathID(r)
	if in.St != nil && (*in.St == 0 || *in.St == 2) {
		db.Exec(`UPDATE ads SET status=$2 WHERE id=$1 AND status<>4`, id, *in.St)
		if *in.St == 0 {
			db.Exec(`DELETE FROM reports WHERE ad_id=$1`, id)
		}
	}
	if in.Vip > 0 && in.Vip <= 365 {
		db.Exec(`UPDATE ads SET vip_until=greatest(coalesce(vip_until,now()),now())+make_interval(days=>$2), bumped_at=now() WHERE id=$1`, id, in.Vip)
	}
	if in.Bump {
		db.Exec(`UPDATE ads SET bumped_at=now() WHERE id=$1`, id)
	}
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

func hAdminUser(w http.ResponseWriter, r *http.Request) {
	var in struct{ Block bool }
	if !readBody(r, &in) {
		fail(w, r, 400, "bad")
		return
	}
	id := pathID(r)
	db.Exec(`UPDATE users SET blocked=$2 WHERE id=$1`, id, in.Block)
	if in.Block {
		db.Exec(`UPDATE ads SET status=2 WHERE user_id=$1 AND status IN (0,1,3)`, id)
		db.Exec(`DELETE FROM sessions WHERE user_id=$1`, id)
	}
	writeJSON(w, r, 200, map[string]bool{"ok": true})
}

func hAdminStats(w http.ResponseWriter, r *http.Request) {
	s := map[string]int64{}
	var a, b, c, d, e, f int64
	db.QueryRow(`SELECT (SELECT count(*) FROM users),
		(SELECT count(*) FROM ads WHERE status=0),
		(SELECT count(*) FROM ads WHERE created_at>now()-interval '1 day'),
		(SELECT count(*) FROM ads WHERE vip_until>now()),
		(SELECT coalesce(sum(amount),0) FROM payments WHERE status=1 AND paid_at>date_trunc('month',now())),
		(SELECT coalesce(sum(amount),0) FROM payments WHERE status=1)`).Scan(&a, &b, &c, &d, &e, &f)
	s["users"], s["active"], s["today"], s["vip"] = a, b, c, d
	s["month_tmt"], s["total_tmt"] = e/cfg.Pay.Mult, f/cfg.Pay.Mult
	writeJSON(w, r, 200, s)
}

func hAdminPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(adminHTML))
}

const adminHTML = `<!doctype html><html lang=ru><meta charset=utf-8><meta name=viewport content="width=device-width">
<title>Buşluk — модерация</title>
<style>body{font:15px system-ui,sans-serif;margin:0;background:#f4f5f2;color:#1b1f1c}
header{background:#0a7d4f;color:#fff;padding:12px 16px;display:flex;gap:8px;flex-wrap:wrap;align-items:center}
header b{font-size:18px;margin-right:auto}input,select,button{font:inherit;padding:7px 10px;border-radius:8px;border:1px solid #ccd}
button{cursor:pointer;background:#fff}#stats{padding:10px 16px;color:#455}
.ad{display:flex;gap:10px;background:#fff;margin:8px 16px;padding:10px;border-radius:10px;align-items:center}
.ad img{width:64px;height:64px;object-fit:cover;border-radius:8px;background:#eee}.ad .m{flex:1;min-width:0}
.ad .t{font-weight:600}.s{font-size:13px;color:#667}.rep{color:#b3261e}.btns{display:flex;gap:4px;flex-wrap:wrap}
.blk{opacity:.55}</style>
<header><b>Buşluk · модерация</b><input id=tok type=password placeholder="ADMIN_TOKEN" size=12>
<input id=q placeholder="поиск / телефон" size=14><select id=f><option value="">Все</option><option value=rep>С жалобами</option><option value=2>Заблокированные</option></select>
<button onclick="load()">Показать</button></header><div id=stats></div><div id=list></div>
<script>
const $=id=>document.getElementById(id);try{$('tok').value=localStorage.t||''}catch(e){}
async function api(p,b){try{localStorage.t=$('tok').value}catch(e){}
 const r=await fetch(p,{method:b?'POST':'GET',headers:{'X-Admin':$('tok').value,'Content-Type':'application/json'},body:b?JSON.stringify(b):undefined});
 if(!r.ok)throw new Error(r.status);return r.json()}
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
async function load(){try{
 const s=await api('/v1/admin/stats');$('stats').textContent='Пользователей: '+s.users+' · активных: '+s.active+' · за сутки: '+s.today+' · VIP: '+s.vip+' · выручка за месяц: '+s.month_tmt+' TMT · всего: '+s.total_tmt+' TMT';
 const f=$('f').value;let p='/v1/admin/ads?q='+encodeURIComponent($('q').value);if(f==='rep')p+='&rep=1';else if(f)p+='&st='+f;
 const a=await api(p);$('list').innerHTML=a.map(x=>'<div class="ad '+(x.st==2?'blk':'')+'">'+(x.f?'<img src="/i/'+x.f+'_t.jpg">':'<img>')+
 '<div class=m><div class=t>'+(x.vip?'⭐ ':'')+esc(x.t)+'</div><div class=s>#'+x.id+' · '+x.p+' TMT · +'+x.phone+' · '+x.d+'</div>'+
 (x.reps?'<div class="s rep">Жалоб: '+x.reps+' — '+esc(x.reasons)+'</div>':'')+'</div><div class=btns>'+
 (x.st==2?'<button onclick="act('+x.id+',{st:0})">Вернуть</button>':'<button onclick="act('+x.id+',{st:2})">Блок</button>')+
 '<button onclick="act('+x.id+',{vip:7})">VIP 7д</button><button onclick="act('+x.id+',{bump:true})">Поднять</button>'+
 '<button onclick="usr('+x.uid+','+(!x.ublock)+')">'+(x.ublock?'Разбан':'Бан автора')+'</button></div></div>').join('')||'<p style="padding:16px">Пусто</p>';
}catch(e){$('stats').textContent='Ошибка: '+e.message}}
async function act(id,b){await api('/v1/admin/ads/'+id,b);load()}
async function usr(id,b){if(confirm(b?'Заблокировать автора и все его объявления?':'Разблокировать автора?')){await api('/v1/admin/users/'+id,{block:b});load()}}
if($('tok').value)load();
</script></html>`
