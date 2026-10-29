"""Phone screenshots of the Bilim prototype in TK and RU (light theme)."""
import json, datetime, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
HTML = ROOT / "prototype" / "bilim.html"
OUT = ROOT / "presentation" / "shots"
OUT.mkdir(parents=True, exist_ok=True)
cur = json.load(open(ROOT / "content" / "curriculum.json", encoding="utf-8"))
g7 = {s["id"]: [t["lesson"] for t in s["topics"]] for s in next(g for g in cur["grades"] if g["grade"] == 7)["subjects"]}
today = datetime.date.today().isoformat()

def state(lang):
    best = {g7["math"][0]: 3, g7["math"][1]: 4, g7["physics"][0]: 3, g7["physics"][1]: 3,
            g7["geometry"][0]: 2, g7["english"][0]: 3, g7["history"][0]: 3, g7["biology"][0]: 4}
    cards = {f'{g7["math"][1]}#4': {"box": 0, "due": today}, f'{g7["geometry"][0]}#3': {"box": 1, "due": today},
             f'{g7["english"][0]}#4': {"box": 0, "due": today}}
    name = "Aýna" if lang == "tk" else "Айна"
    return {"user": {"name": name, "grade": 7, "phone": "+993 65 12 34 56"}, "grade": 7, "lang": lang,
            "xp": 1240, "streak": 12, "day": today, "best": best, "cards": cards, "last": g7["physics"][2]}

with sync_playwright() as p:
    b = p.chromium.launch()
    for lang in ("tk", "ru"):
        ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, color_scheme="light")
        page = ctx.new_page()
        page.goto(HTML.as_uri())
        page.wait_for_timeout(800)
        def shot(name):
            page.wait_for_timeout(400)
            if name in ("2-home", "9-grade2", "3-subject", "10-grade2-math"):
                page.evaluate("() => window.scrollTo(0, 0)"); page.wait_for_timeout(150)
            page.screenshot(path=str(OUT / f"{lang}-{name}.png"))
        # 1 login (fresh)
        page.evaluate("l => { localStorage.clear(); localStorage.setItem('bilim:lang', JSON.stringify(l)) }", lang)
        page.reload(); page.wait_for_timeout(800)
        shot("1-login")
        # seed a realistic student
        page.evaluate("s => { for (const [k,v] of Object.entries(s)) localStorage.setItem('bilim:'+k, JSON.stringify(v)) }", state(lang))
        page.reload(); page.wait_for_timeout(800)
        shot("2-home")
        page.click("[data-subject=physics]"); shot("3-subject")
        # a physics lesson whose first question is multiple choice
        lid = page.evaluate("""ids => ids.find(id => { const st = LESSONS[id][1].steps.find(s => isQ(s)); return st && st.type==='choice' && st.hint })""", g7["physics"])
        page.evaluate("id => startLesson(id)", lid); shot("4-theory")
        while page.evaluate("() => !isQ(view.items[view.i].step)"):
            page.click("#next")
        page.click("#hint"); shot("5-hint")
        right = page.evaluate("() => view.items[view.i].step.answer")
        page.click(f"[data-pick='{right}']"); page.click("#check"); shot("6-correct")
        # finish lesson answering correctly
        for _ in range(20):
            if page.query_selector(".result"): break
            if page.query_selector("#next"): page.click("#next"); continue
            t = page.evaluate("() => view.items[view.i].step.type")
            a = page.evaluate("() => view.items[view.i].step.answer")
            if t == "choice": page.click(f"[data-pick='{a}']")
            elif t == "truefalse": page.click(f"[data-pick='{0 if a else 1}']")
            else: page.fill("#ans", str(a).split("|")[0]); page.dispatch_event("#ans", "input")
            page.click("#check")
        shot("7-result")
        page.click("#finish"); page.click("[data-tab=help]")
        q = "Arhimed güýji näme?" if lang == "tk" else "Что такое сила Архимеда?"
        page.fill("#askIn", q); page.press("#askIn", "Enter"); shot("8-help")
        page.click("[data-tab=home]"); page.evaluate("() => { st.grade = 2; render() }"); shot("9-grade2")
        page.click("[data-subject=math]"); shot("10-grade2-math")
        ctx.close()
    b.close()
print(sorted(x.name for x in OUT.iterdir()))
