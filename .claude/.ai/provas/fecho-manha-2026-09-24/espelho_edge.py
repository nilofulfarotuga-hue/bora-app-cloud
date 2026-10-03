# -*- coding: utf-8 -*-
"""Espelho das Edge Functions: baixa o corpo de producao (Management API, multipart) e compara com o repo.
Uso: python espelho_edge.py [--aplicar]   (sem --aplicar so relata). Diffs repo-vs-prod ficam em espelho_diffs/."""
import json, os, re, sys, urllib.request, shutil, subprocess, difflib, datetime
REF = "ojykpzwqrtusfeakzrna"
REPO = r"C:\BoraLocal\projetosflutter\bora_app\supabase\functions"
TMP = r"C:\BoraLocal\tmp\edge-espelho-2026-09-24"
tok = None
for ln in open(r"C:\BoraLocal\projetosflutter\bora_app\.supabase-token.env", encoding="utf-8"):
    m = re.search(r"(sbp_[A-Za-z0-9]+)", ln)
    if m: tok = m.group(1)
assert tok, "sem PAT"
H = {"Authorization": "Bearer " + tok}
def get(url, accept=None):
    h = dict(H)
    if accept: h["Accept"] = accept
    r = urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=60)
    return r.read(), r.headers
fns = json.loads(get(f"https://api.supabase.com/v1/projects/{REF}/functions")[0])
POR_SLUG = {f["slug"]: f for f in fns}
def parse_multipart(body, ctype):
    m = re.search(r'boundary="?([^";]+)"?', ctype)
    b = ("--" + m.group(1)).encode()
    out = {}
    for p in body.split(b):
        if b"Content-Disposition" not in p: continue
        head, _, data = p.partition(b"\r\n\r\n")
        fn = re.search(rb'filename="([^"]+)"', head)
        if not fn: continue
        if data.endswith(b"\r\n"): data = data[:-2]
        out[fn.group(1).decode()] = data
    return out
def rel_repo(slug, name):
    n = name.replace("\\", "/")
    n = re.sub(r"^user_fn_[^/]+/", "", n)
    if n.startswith("source/"): n = n[len("source/"):]
    if "_shared/" in n: return "_shared/" + n.split("_shared/", 1)[1]
    for pref in (f"supabase/functions/{slug}/", f"functions/{slug}/", f"{slug}/"):
        if n.startswith(pref): return f"{slug}/" + n[len(pref):]
    if n.startswith("supabase/functions/") or n.startswith("functions/"): return f"{slug}/" + n.split("/")[-1]
    return f"{slug}/" + n
NL = chr(10); CR = chr(13)
def norm(b): return b.replace((CR + NL).encode(), NL.encode())
aplicar = "--aplicar" in sys.argv
os.makedirs("espelho_diffs", exist_ok=True)
mudados = []
for f in sorted(fns, key=lambda x: x["slug"]):
    slug = f["slug"]
    body, hd = get(f"https://api.supabase.com/v1/projects/{REF}/functions/{slug}/body", "multipart/form-data")
    for name, data in parse_multipart(body, hd.get("Content-Type", "")).items():
        rp = rel_repo(slug, name)
        src = os.path.join(TMP, rp.replace("/", os.sep)); os.makedirs(os.path.dirname(src), exist_ok=True)
        open(src, "wb").write(data)
        repo_p = os.path.join(REPO, rp.replace("/", os.sep))
        flag = ""
        if not os.path.exists(repo_p): st = "SO-PROD"
        elif norm(open(repo_p, "rb").read()) == norm(data): st = "igual"
        else:
            st = "DIFERENTE"
            dt = subprocess.run(["git", "log", "-1", "--format=%cI", "--", repo_p], cwd=REPO, capture_output=True, text=True).stdout.strip()
            prod_dt = datetime.datetime.utcfromtimestamp(f["updated_at"] / 1000).strftime("%Y-%m-%d")
            a = norm(open(repo_p, "rb").read()).decode("utf-8", "replace").split(NL)
            bb = norm(data).decode("utf-8", "replace").split(NL)
            d = list(difflib.unified_diff(a, bb, "repo/" + rp, "prod/" + rp, lineterm=""))
            open(os.path.join("espelho_diffs", rp.replace("/", "__") + ".diff"), "w", encoding="utf-8").write(NL.join(d))
            nd = len([l for l in d if l[:1] in "+-" and not l.startswith(("+++", "---"))])
            flag = f" [repo commit {dt[:10]} vs prod {prod_dt}; {nd} linhas diff]"
        if st != "igual" and aplicar and not rp.startswith("_shared/"):
            os.makedirs(os.path.dirname(repo_p), exist_ok=True); shutil.copyfile(src, repo_p); flag += " -> APLICADO"; mudados.append(rp)
        if st != "igual": print(f"{slug:42s} v{f['version']:<3} jwt={str(f['verify_jwt']):5s} {st:9s} {rp} ({len(data)} b){flag}")
repo_slugs = {d for d in os.listdir(REPO) if os.path.isdir(os.path.join(REPO, d)) and d != "_shared"}
print("SO-REPO (nao existe em producao):", sorted(repo_slugs - set(POR_SLUG)))
print("TOTAL prod:", len(POR_SLUG), "repo antes:", len(repo_slugs), "ficheiros aplicados:", len(mudados))
