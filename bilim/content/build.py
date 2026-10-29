"""Builds app/server content from sources.

Sources:   src/<subject>.json      hand-written lessons (any grade)
           grades/g<N>.json        year plan per grade + lessons
Output:    <subject>.json          all lessons of a subject (all grades)
           curriculum.json         grade → subjects → topics (with lesson ids or null = coming soon)
           manifest.json           subject meta + per-grade summary (small, loaded first)
Run:  python3 build.py   (validates everything, fails loudly)
"""
import json, glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
META = {
    "turkmen":     ("✍️", "#2B8A3E", "Türkmen dili", "Туркменский язык"),
    "reading":     ("📖", "#D9480F", "Okamak", "Чтение"),
    "literature":  ("📜", "#C2255C", "Edebiýat", "Литература"),
    "math":        ("➗", "#2F6FEB", "Matematika", "Математика"),
    "geometry":    ("📐", "#3B5BDB", "Geometriýa", "Геометрия"),
    "world":       ("🌳", "#5C940D", "Daşky dünýä", "Окружающий мир"),
    "physics":     ("⚡", "#E8590C", "Fizika", "Физика"),
    "chemistry":   ("⚗️", "#12B886", "Himiýa", "Химия"),
    "biology":     ("🌱", "#40C057", "Biologiýa", "Биология"),
    "geography":   ("🌍", "#0C8599", "Geografiýa", "География"),
    "history":     ("🏛️", "#B08800", "Taryh", "История"),
    "informatics": ("💻", "#495057", "Informatika", "Информатика"),
    "russian":     ("📘", "#1971C2", "Rus dili", "Русский язык"),
    "english":     ("🇬🇧", "#7048E8", "Iňlis dili", "Английский язык"),
}
ORDER = list(META)
errors = []

def bi(x, where):
    if isinstance(x, str):
        return
    if not (isinstance(x, dict) and x.get("tk") and x.get("ru")):
        errors.append(f"{where}: needs tk+ru")

def check_lesson(l, where):
    if not re.fullmatch(r"[a-z]+-\d{1,2}-[a-z0-9-]+", l.get("id", "")):
        errors.append(f"{where}: bad id {l.get('id')}")
    bi(l.get("title"), where + " title")
    steps = l.get("steps", [])
    qs = 0
    for i, s in enumerate(steps):
        w = f"{where} step {i}"
        t = s.get("type")
        if t in ("theory", "example", "world"):
            bi(s.get("text"), w)
        elif t in ("choice", "input", "truefalse"):
            qs += 1
            for k in ("q", "hint", "explain"):
                bi(s.get(k), f"{w} {k}")
            if t == "choice":
                opts = s.get("options", [])
                if len(opts) < 2 or not isinstance(s.get("answer"), int) or not 0 <= s["answer"] < len(opts):
                    errors.append(f"{w}: answer index out of range")
                for o in opts: bi(o, f"{w} option")
            if t == "input" and not (isinstance(s.get("answer"), str) and s["answer"].strip()):
                errors.append(f"{w}: input answer must be non-empty string")
            if t == "truefalse" and not isinstance(s.get("answer"), bool):
                errors.append(f"{w}: truefalse answer must be bool")
        else:
            errors.append(f"{w}: unknown type {t}")
    if qs < 2:
        errors.append(f"{where}: fewer than 2 questions")

lessons = {sid: [] for sid in ORDER}
seen = set()

def add(sid, l, where):
    if sid not in META:
        errors.append(f"{where}: unknown subject {sid}"); return
    if l["id"] in seen:
        errors.append(f"{where}: duplicate id {l['id']}"); return
    seen.add(l["id"])
    before = len(errors)
    check_lesson(l, where)
    if len(errors) > before:
        return
    lessons[sid].append({k: l[k] for k in ("id", "grade", "title", "minutes", "steps") if k in l})

# hand-written lessons
for p in sorted(glob.glob(os.path.join(HERE, "src", "*.json"))):
    d = json.load(open(p, encoding="utf-8"))
    for l in d["lessons"]:
        add(d["id"], l, os.path.basename(p))

# year plan + generated lessons: plan.json, grades/g<N>/<subject>.json
plan_all = json.load(open(os.path.join(HERE, "plan.json"), encoding="utf-8"))
curriculum = {}
missing = []
for g in range(1, 13):
    plan = {sid: [{"title": t, "lesson": None} for t in topics]
            for sid, topics in plan_all[str(g)].items()}
    for sid in plan:
        p = os.path.join(HERE, "grades", f"g{g}", f"{sid}.json")
        if not os.path.exists(p):
            missing.append(f"g{g}/{sid}"); continue
        try:
            d = json.load(open(p, encoding="utf-8"))
        except Exception as e:
            errors.append(f"g{g}/{sid}: invalid JSON {e}"); continue
        for l in d.get("lessons", []):
            l["grade"] = g
            before = len(errors)
            add(sid, l, f"g{g}/{sid} {l.get('id')}")
            if len(errors) > before:
                continue
            ti = l.get("topic")
            topics = plan[sid]
            if isinstance(ti, int) and 0 <= ti < len(topics) and topics[ti]["lesson"] is None:
                topics[ti]["lesson"] = l["id"]
            else:
                topics.append({"title": l["title"], "lesson": l["id"]})
    curriculum[g] = plan
if missing:
    print("! not written yet:", ", ".join(missing))

# attach hand-written lessons to their grade plan
for sid, ls in lessons.items():
    for l in ls:
        plan = curriculum.get(l["grade"])
        if plan is None or any(t["lesson"] == l["id"] for t in plan.get(sid, [])):
            continue
        topics = plan.setdefault(sid, [])
        match = next((t for t in topics if t["lesson"] is None and
                      t["title"]["ru"].split()[0].lower() in l["title"]["ru"].lower()), None)
        if match: match["lesson"] = l["id"]
        else: topics.append({"title": l["title"], "lesson": l["id"]})

if errors:
    print(f"!! {len(errors)} problems (lessons skipped):"); print("\n".join(errors[:80]))

# write outputs
for sid, ls in lessons.items():
    icon, color, tk, ru = META[sid]
    ls.sort(key=lambda l: l["grade"])
    json.dump({"id": sid, "icon": icon, "color": color, "title": {"tk": tk, "ru": ru}, "lessons": ls},
              open(os.path.join(HERE, f"{sid}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

cur = {"grades": [{"grade": g, "subjects": [{"id": sid, "topics": curriculum[g][sid]}
                                             for sid in ORDER if sid in curriculum[g]]}
                  for g in sorted(curriculum)]}
json.dump(cur, open(os.path.join(HERE, "curriculum.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

manifest = {"version": 2,
            "subjects": [{"id": sid, "icon": META[sid][0], "color": META[sid][1],
                          "title": {"tk": META[sid][2], "ru": META[sid][3]}} for sid in ORDER],
            "lessonIndex": {l["id"]: sid for sid, ls in lessons.items() for l in ls}}
json.dump(manifest, open(os.path.join(HERE, "manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

n_l = sum(len(v) for v in lessons.values())
n_t = sum(len(t) for g in curriculum.values() for t in g.values())
print(f"OK: {len(curriculum)} grades, {n_t} topics, {n_l} lessons")
for g in sorted(curriculum):
    ready = sum(1 for t in curriculum[g].values() for x in t if x["lesson"])
    total = sum(len(t) for t in curriculum[g].values())
    print(f"  {g:>2} synp: {len(curriculum[g])} ders, {total} tema, {ready} sapak taýýar")
