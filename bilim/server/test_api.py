import os, tempfile
os.environ["BILIM_DB"] = tempfile.mktemp(suffix=".db")
os.environ["BILIM_DEV"] = "1"
os.environ["BILIM_ADMIN_TOKEN"] = "adm"

from fastapi.testclient import TestClient
from main import app

c = TestClient(app)

def login(phone="+99365123456"):
    code = c.post("/api/auth/request", json={"phone": phone}).json()["dev_code"]
    assert c.post("/api/auth/verify", json={"phone": phone, "code": "000000x"}).status_code == 400
    t = c.post("/api/auth/verify", json={"phone": phone, "code": code, "name": "Test", "grade": 7, "lang": "tk"}).json()["token"]
    return {"Authorization": f"Bearer {t}"}

def test_flow():
    H = login()
    assert c.get("/api/me", headers=H).json()["grade"] == 7
    m = c.get("/api/content/manifest")
    assert m.status_code == 200 and len(m.json()["subjects"]) == 14
    cur = c.get("/api/content/curriculum").json()["grades"]
    assert [g["grade"] for g in cur] == list(range(1, 13))
    assert c.get("/api/content/manifest", headers={"if-none-match": m.headers["etag"]}).status_code == 304
    assert c.get("/api/content/subject/math").json()["id"] == "math"
    assert c.get("/api/content/subject/..%2Fmain").status_code == 404
    r = c.post("/api/progress", headers=H, json={"lesson_id": "math-7-linear", "correct": [2, 3], "wrong": [4], "total": 3}).json()
    assert r["xp_gained"] == 20 and r["streak"] == 1
    assert c.get("/api/progress", headers=H).json()["math-7-linear"]["best"] == 2
    assert c.get("/api/review", headers=H).json() == []          # due tomorrow, not today
    a = c.post("/api/ask", headers=H, json={"question": "?", "lesson_id": "math-7-linear", "step": 3, "lang": "ru"}).json()
    assert a["source"] == "hint" and "3x = 15" in a["answer"]
    assert c.post("/api/support", headers=H, json={"message": "Salam, kömek gerek"}).json()["ok"]
    assert c.get("/api/admin/tickets", headers={"x-admin": "adm"}).json()[0]["message"].startswith("Salam")
    assert c.get("/api/admin/stats", headers={"x-admin": "bad"}).status_code == 403

def test_auth_required():
    assert c.get("/api/me").status_code == 401
    assert c.post("/api/auth/request", json={"phone": "123"}).status_code == 422
