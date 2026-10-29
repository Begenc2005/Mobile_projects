"""
Bilim API — lightweight backend for the Bilim school app.
Runs on a single Türkmentelekom VPS: FastAPI + SQLite (WAL), gzip, no heavy deps.

Env:
  BILIM_DB            path to sqlite file            (default ./bilim.db)
  BILIM_CONTENT       path to content folder         (default ../content)
  BILIM_DEV           "1" → SMS code returned in API (testing only)
  BILIM_ADMIN_TOKEN   token for /api/admin/*
  BILIM_SMS_URL       HTTP gateway for SMS (POST {phone, text})
  BILIM_AI_URL        OpenAI-compatible chat endpoint for the tutor (optional)
  BILIM_AI_KEY / BILIM_AI_MODEL
"""
import json, os, secrets, sqlite3, time, hashlib, re
from datetime import date, timedelta
from pathlib import Path
from contextlib import contextmanager

import httpx
from fastapi import FastAPI, HTTPException, Header, Request, Response
from fastapi.middleware.gzip import GZipMiddleware
from pydantic import BaseModel, Field

DB = os.getenv("BILIM_DB", "bilim.db")
CONTENT = Path(os.getenv("BILIM_CONTENT", Path(__file__).parent.parent / "content"))
DEV = os.getenv("BILIM_DEV") == "1"
ADMIN = os.getenv("BILIM_ADMIN_TOKEN", "")
LEITNER_DAYS = [1, 2, 4, 8, 16, 32]  # box → days until next review

app = FastAPI(title="Bilim API", version="1.0")
app.add_middleware(GZipMiddleware, minimum_size=500)

# ---------- DB ----------
SCHEMA = """
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, phone TEXT UNIQUE, name TEXT,
  grade INTEGER, lang TEXT DEFAULT 'tk', xp INTEGER DEFAULT 0, streak INTEGER DEFAULT 0,
  last_day TEXT, created REAL);
CREATE TABLE IF NOT EXISTS codes(phone TEXT PRIMARY KEY, code_hash TEXT, expires REAL, tries INTEGER DEFAULT 0, sent REAL);
CREATE TABLE IF NOT EXISTS tokens(token TEXT PRIMARY KEY, user_id INTEGER, created REAL);
CREATE TABLE IF NOT EXISTS progress(user_id INTEGER, lesson_id TEXT, best INTEGER, total INTEGER,
  attempts INTEGER, updated REAL, PRIMARY KEY(user_id, lesson_id));
CREATE TABLE IF NOT EXISTS cards(user_id INTEGER, lesson_id TEXT, step INTEGER, box INTEGER, due TEXT,
  PRIMARY KEY(user_id, lesson_id, step));
CREATE TABLE IF NOT EXISTS tickets(id INTEGER PRIMARY KEY, user_id INTEGER, message TEXT,
  reply TEXT, status TEXT DEFAULT 'open', created REAL);
"""

@contextmanager
def db():
    con = sqlite3.connect(DB, timeout=10)
    con.row_factory = sqlite3.Row
    try:
        yield con
        con.commit()
    finally:
        con.close()

with db() as c:
    c.executescript(SCHEMA)

def h(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()

def user_from(auth: str | None) -> sqlite3.Row:
    if not auth or not auth.startswith("Bearer "):
        raise HTTPException(401, "auth")
    with db() as c:
        u = c.execute("SELECT u.* FROM tokens t JOIN users u ON u.id=t.user_id WHERE t.token=?",
                      (h(auth[7:]),)).fetchone()
    if not u:
        raise HTTPException(401, "auth")
    return u

# ---------- content (cached in memory, served with ETag) ----------
_cache: dict[str, tuple[bytes, str]] = {}

def load(name: str) -> tuple[bytes, str]:
    if name not in _cache:
        p = CONTENT / f"{name}.json"
        if not re.fullmatch(r"[a-z_]+", name) or not p.exists():
            raise HTTPException(404, "not found")
        raw = json.dumps(json.loads(p.read_text("utf-8")), ensure_ascii=False, separators=(",", ":")).encode()
        _cache[name] = (raw, h(raw.decode())[:16])
    return _cache[name]

def serve(name: str, request: Request) -> Response:
    raw, etag = load(name)
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304)
    return Response(raw, media_type="application/json",
                    headers={"ETag": etag, "Cache-Control": "public, max-age=3600"})

@app.get("/api/content/manifest")
def manifest(request: Request):
    return serve("manifest", request)

@app.get("/api/content/curriculum")
def curriculum(request: Request):
    return serve("curriculum", request)

@app.get("/api/content/subject/{sid}")
def subject(sid: str, request: Request):
    return serve(sid, request)

def find_step(lesson_id: str, step: int) -> dict | None:
    sid = json.loads(load("manifest")[0]).get("lessonIndex", {}).get(lesson_id)
    if not sid:
        return None
    for l in json.loads(load(sid)[0])["lessons"]:
        if l["id"] == lesson_id and 0 <= step < len(l["steps"]):
            return l["steps"][step]
    return None

# ---------- auth: phone + SMS code ----------
class PhoneIn(BaseModel):
    phone: str = Field(pattern=r"^\+?993\d{8}$")

class VerifyIn(PhoneIn):
    code: str
    name: str | None = None
    grade: int | None = Field(None, ge=1, le=12)
    lang: str | None = Field(None, pattern="^(tk|ru)$")

def norm(p: str) -> str:
    return "+" + p.lstrip("+")

async def send_sms(phone: str, text: str):
    url = os.getenv("BILIM_SMS_URL")
    if url:
        async with httpx.AsyncClient(timeout=10) as cl:
            await cl.post(url, json={"phone": phone, "text": text})

@app.post("/api/auth/request")
async def auth_request(body: PhoneIn):
    phone = norm(body.phone)
    with db() as c:
        row = c.execute("SELECT sent FROM codes WHERE phone=?", (phone,)).fetchone()
        if row and time.time() - row["sent"] < 60:
            raise HTTPException(429, "wait 60s")
        code = f"{secrets.randbelow(10**6):06d}"
        c.execute("REPLACE INTO codes VALUES(?,?,?,0,?)", (phone, h(code), time.time() + 300, time.time()))
    await send_sms(phone, f"Bilim kody: {code}")
    return {"ok": True, **({"dev_code": code} if DEV else {})}

@app.post("/api/auth/verify")
def auth_verify(body: VerifyIn):
    phone = norm(body.phone)
    with db() as c:
        row = c.execute("SELECT * FROM codes WHERE phone=?", (phone,)).fetchone()
        if not row or row["expires"] < time.time() or row["tries"] >= 5:
            raise HTTPException(400, "code expired")
        if row["code_hash"] != h(body.code):
            c.execute("UPDATE codes SET tries=tries+1 WHERE phone=?", (phone,))
            raise HTTPException(400, "wrong code")
        c.execute("DELETE FROM codes WHERE phone=?", (phone,))
        u = c.execute("SELECT id FROM users WHERE phone=?", (phone,)).fetchone()
        if not u:
            c.execute("INSERT INTO users(phone,name,grade,lang,created) VALUES(?,?,?,?,?)",
                      (phone, body.name, body.grade, body.lang or "tk", time.time()))
            uid = c.execute("SELECT last_insert_rowid()").fetchone()[0]
        else:
            uid = u["id"]
        token = secrets.token_urlsafe(32)
        c.execute("INSERT INTO tokens VALUES(?,?,?)", (h(token), uid, time.time()))
    return {"token": token}

class ProfileIn(BaseModel):
    name: str | None = None
    grade: int | None = Field(None, ge=1, le=12)
    lang: str | None = Field(None, pattern="^(tk|ru)$")

@app.get("/api/me")
def me(authorization: str | None = Header(None)):
    u = user_from(authorization)
    return {k: u[k] for k in ("id", "phone", "name", "grade", "lang", "xp", "streak")}

@app.patch("/api/me")
def me_update(body: ProfileIn, authorization: str | None = Header(None)):
    u = user_from(authorization)
    with db() as c:
        for k, v in body.model_dump(exclude_none=True).items():
            c.execute(f"UPDATE users SET {k}=? WHERE id=?", (v, u["id"]))
    return me(authorization)

# ---------- progress + spaced repetition (Leitner) ----------
class ResultIn(BaseModel):
    lesson_id: str
    correct: list[int]      # step indexes answered right on first try
    wrong: list[int]        # step indexes answered wrong / with hint
    total: int

@app.post("/api/progress")
def save_progress(r: ResultIn, authorization: str | None = Header(None)):
    u = user_from(authorization)
    today = date.today()
    score = len(r.correct)
    with db() as c:
        c.execute("""INSERT INTO progress VALUES(?,?,?,?,1,?)
                     ON CONFLICT(user_id,lesson_id) DO UPDATE SET best=MAX(best,excluded.best),
                     attempts=attempts+1, updated=excluded.updated""",
                  (u["id"], r.lesson_id, score, r.total, time.time()))
        for step in r.wrong:          # mistakes → box 0, review tomorrow
            c.execute("REPLACE INTO cards VALUES(?,?,?,0,?)",
                      (u["id"], r.lesson_id, step, (today + timedelta(1)).isoformat()))
        for step in r.correct:        # promote existing cards
            row = c.execute("SELECT box FROM cards WHERE user_id=? AND lesson_id=? AND step=?",
                            (u["id"], r.lesson_id, step)).fetchone()
            if row:
                box = min(row["box"] + 1, len(LEITNER_DAYS) - 1)
                c.execute("UPDATE cards SET box=?, due=? WHERE user_id=? AND lesson_id=? AND step=?",
                          (box, (today + timedelta(LEITNER_DAYS[box])).isoformat(), u["id"], r.lesson_id, step))
        # XP + daily streak
        last = u["last_day"]
        streak = u["streak"] if last == today.isoformat() else (
            u["streak"] + 1 if last == (today - timedelta(1)).isoformat() else 1)
        c.execute("UPDATE users SET xp=xp+?, streak=?, last_day=? WHERE id=?",
                  (score * 10, streak, today.isoformat(), u["id"]))
    return {"ok": True, "xp_gained": score * 10, "streak": streak}

@app.get("/api/progress")
def get_progress(authorization: str | None = Header(None)):
    u = user_from(authorization)
    with db() as c:
        rows = c.execute("SELECT lesson_id,best,total,attempts FROM progress WHERE user_id=?", (u["id"],)).fetchall()
    return {r["lesson_id"]: dict(r) for r in rows}

@app.get("/api/review")
def review(authorization: str | None = Header(None)):
    u = user_from(authorization)
    with db() as c:
        rows = c.execute("SELECT lesson_id,step,box FROM cards WHERE user_id=? AND due<=? LIMIT 30",
                         (u["id"], date.today().isoformat())).fetchall()
    return [dict(r) for r in rows]

# ---------- help: AI tutor (optional) + support tickets ----------
class AskIn(BaseModel):
    question: str = Field(max_length=1000)
    lesson_id: str | None = None
    step: int | None = None
    lang: str = Field("tk", pattern="^(tk|ru)$")

TUTOR_PROMPT = {
    "tk": "Sen mekdep okuwçylaryna kömek edýän sabyrly mugallym. Türkmen dilinde gysga jogap ber. Jogaby göni aýtma — ädimme-ädim ugrukdyr.",
    "ru": "Ты терпеливый учитель для школьников. Отвечай кратко по-русски. Не давай готовый ответ сразу — направляй по шагам.",
}

@app.post("/api/ask")
async def ask(body: AskIn, authorization: str | None = Header(None)):
    user_from(authorization)
    step = find_step(body.lesson_id, body.step) if body.lesson_id and body.step is not None else None
    url, key = os.getenv("BILIM_AI_URL"), os.getenv("BILIM_AI_KEY")
    if url and key:
        ctx = json.dumps(step, ensure_ascii=False) if step else ""
        try:
            async with httpx.AsyncClient(timeout=30) as cl:
                r = await cl.post(url, headers={"Authorization": f"Bearer {key}"}, json={
                    "model": os.getenv("BILIM_AI_MODEL", "default"), "max_tokens": 400,
                    "messages": [{"role": "system", "content": TUTOR_PROMPT[body.lang] + ("\nSapak: " + ctx if ctx else "")},
                                 {"role": "user", "content": body.question}]})
                return {"answer": r.json()["choices"][0]["message"]["content"], "source": "ai"}
        except Exception:
            pass
    if step and step.get("hint"):
        return {"answer": step["hint"][body.lang], "source": "hint"}
    msg = {"tk": "Soragyňyz goldaw toparyna iberildi, gysga wagtda jogap bereris.",
           "ru": "Ваш вопрос передан в поддержку, ответим в ближайшее время."}
    with db() as c:
        c.execute("INSERT INTO tickets(user_id,message,created) VALUES((SELECT user_id FROM tokens WHERE token=?),?,?)",
                  (h(authorization[7:]), body.question, time.time()))
    return {"answer": msg[body.lang], "source": "support"}

class TicketIn(BaseModel):
    message: str = Field(min_length=2, max_length=2000)

@app.post("/api/support")
def support_new(t: TicketIn, authorization: str | None = Header(None)):
    u = user_from(authorization)
    with db() as c:
        c.execute("INSERT INTO tickets(user_id,message,created) VALUES(?,?,?)", (u["id"], t.message, time.time()))
    return {"ok": True}

@app.get("/api/support")
def support_list(authorization: str | None = Header(None)):
    u = user_from(authorization)
    with db() as c:
        return [dict(r) for r in c.execute(
            "SELECT id,message,reply,status,created FROM tickets WHERE user_id=? ORDER BY id DESC", (u["id"],))]

def admin(token: str | None):
    if not ADMIN or token != ADMIN:
        raise HTTPException(403, "admin")

@app.get("/api/admin/tickets")
def admin_tickets(x_admin: str | None = Header(None)):
    admin(x_admin)
    with db() as c:
        return [dict(r) for r in c.execute("SELECT * FROM tickets WHERE status='open' ORDER BY id")]

class ReplyIn(BaseModel):
    reply: str

@app.post("/api/admin/tickets/{tid}")
def admin_reply(tid: int, r: ReplyIn, x_admin: str | None = Header(None)):
    admin(x_admin)
    with db() as c:
        c.execute("UPDATE tickets SET reply=?, status='answered' WHERE id=?", (r.reply, tid))
    return {"ok": True}

@app.get("/api/admin/stats")
def admin_stats(x_admin: str | None = Header(None)):
    admin(x_admin)
    with db() as c:
        return {"users": c.execute("SELECT COUNT(*) FROM users").fetchone()[0],
                "lessons_done": c.execute("SELECT COUNT(*) FROM progress").fetchone()[0],
                "open_tickets": c.execute("SELECT COUNT(*) FROM tickets WHERE status='open'").fetchone()[0]}

@app.get("/health")
def health():
    return {"ok": True}
