# Procura fotos suspeitas (marcadores "sem imagem", ícones, imagens quase em branco) nas fotos descarregadas.
# Lê dados/fotos_<loja>.json e dados/raw_<loja>.json; escreve dados/fotos_suspeitas.json. Não toca na base.
import json, os, hashlib, collections
from PIL import Image

AQUI = os.path.dirname(os.path.abspath(__file__))
DADOS = os.path.join(AQUI, "dados")
FOTOS = r"C:\Users\danil\AppData\Local\Temp\farmacias-fotos"
# md5 do quadro "PRODUTO SEM IMAGEM DISPONÍVEL" (Nossa Farmácia) visto à mão a 11/11
PLACEHOLDER_MD5 = set()

out = {}
todas = []
for loja in ("farmacia-se-guarda", "farmacia-teixeira-guarda"):
    fotos = json.load(open(os.path.join(DADOS, f"fotos_{loja}.json"), encoding="utf8"))
    raw = {p["glovo_id"]: p for p in json.load(open(os.path.join(DADOS, f"raw_{loja}.json"), encoding="utf8"))["products"]}
    for gid, v in fotos.items():
        if v.get("status") != "ok":
            continue
        ext = v["photo_url"].rsplit(".", 1)[-1]
        pid = v["photo_url"].rsplit("/", 1)[-1].rsplit(".", 1)[0]
        f = os.path.join(FOTOS, loja, f"{pid}.{ext}")
        im = Image.open(f)
        w, h = im.size
        sm = im.convert("RGB").resize((64, 64))
        px = list(sm.getdata())
        branco = sum(1 for r, g, b in px if r > 235 and g > 235 and b > 235) / len(px)
        cores = len(set((r // 16, g // 16, b // 16) for r, g, b in px))
        todas.append({"loja": loja, "glovo_id": gid, "id": pid, "nome": raw[gid]["name"], "md5": v["md5"], "bytes": v["photo_bytes"],
                      "w": w, "h": h, "branco": round(branco, 3), "cores": cores, "src": v["src"], "ficheiro": f})

por_md5 = collections.defaultdict(list)
for t in todas:
    por_md5[t["md5"]].append(t)
suspeitas = []
for t in todas:
    razoes = []
    nomes = {x["nome"].split(" ")[0].lower() for x in por_md5[t["md5"]]}
    if len(nomes) > 1:
        razoes.append(f"mesma imagem em {len(por_md5[t['md5']])} produtos de marcas diferentes")
    if min(t["w"], t["h"]) < 150:
        razoes.append(f"muito pequena {t['w']}x{t['h']}")
    if t["cores"] <= 6:
        razoes.append(f"poucas cores ({t['cores']})")
    if t["branco"] > 0.93:
        razoes.append(f"quase branca ({t['branco']})")
    if razoes:
        t["razoes"] = razoes
        suspeitas.append(t)
json.dump(suspeitas, open(os.path.join(DADOS, "fotos_suspeitas.json"), "w", encoding="utf8"), ensure_ascii=False, indent=1)
print("fotos analisadas", len(todas), "suspeitas", len(suspeitas))
for s in suspeitas:
    print(s["loja"][9:12], s["bytes"], f'{s["w"]}x{s["h"]}', s["cores"], s["branco"], s["nome"][:45], "|", "; ".join(s["razoes"]))
