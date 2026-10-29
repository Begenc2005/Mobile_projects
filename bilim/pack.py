"""Build content, copy it into the app, and assemble the web prototype.
Run from project root: python3 pack.py"""
import json, os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
C = os.path.join(ROOT, "content")
subprocess.run([sys.executable, os.path.join(C, "build.py")], check=True)

man = json.load(open(os.path.join(C, "manifest.json"), encoding="utf-8"))
ids = [s["id"] for s in man["subjects"]]

# app assets
dst = os.path.join(ROOT, "app", "assets", "content")
shutil.rmtree(dst, ignore_errors=True); os.makedirs(dst)
for f in ids + ["manifest", "curriculum"]:
    shutil.copy(os.path.join(C, f + ".json"), dst)

# prototype
bundle = {"subjects": [json.load(open(os.path.join(C, f"{i}.json"), encoding="utf-8")) for i in ids],
          "curriculum": json.load(open(os.path.join(C, "curriculum.json"), encoding="utf-8"))}
tpl = open(os.path.join(ROOT, "prototype", "template.html"), encoding="utf-8").read()
out = tpl.replace("__CONTENT__", json.dumps(bundle, ensure_ascii=False, separators=(",", ":")))
open(os.path.join(ROOT, "prototype", "bilim.html"), "w", encoding="utf-8").write(out)
print(f"prototype: {len(out)//1024} KB")
