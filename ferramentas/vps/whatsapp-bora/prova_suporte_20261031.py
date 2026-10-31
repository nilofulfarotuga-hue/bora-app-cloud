# -*- coding: utf-8 -*-
"""Prova do suporte que responde a tudo (31/10), contra o cerebro a correr, SEM enviar nada (POST /prova, modo prova:
regista com enviada=false, Telegram em silencio). Numero de teste falso 351900000001 (nunca clientes reais).
    cd /opt/whatsapp-bora && python3 /tmp/prova_suporte_20261031.py
"""
import re
import sys
import time

sys.path.insert(0, "/opt/whatsapp-bora")
from cerebro import provas as P  # noqa: E402

NUM = P.DESCONHECIDO
CASOS = [
    ("b3-suporte", "oi", lambda s: re.search(r"(ol[aá]|bom dia|boa tarde|boa noite|oi)", s, re.I) and re.search(r"ajud", s, re.I) and "nao tenho resposta" not in s.lower()),
    ("b3-suporte", "quanto é a entrega para 6 km", lambda s: "3,50" in s or "3.50" in s),
    ("b3-suporte", "o meu pedido está atrasado", lambda s: bool(s) and not re.search(r"n[aã]o tenho resposta", s, re.I)),
    ("b3-suporte", "como ganho os salgados da Keli", lambda s: bool(s) and not re.search(r"n[aã]o tenho resposta", s, re.I)),
    ("b3-suporte", "quero ser parceiro", lambda s: bool(s) and re.search(r"(loja|restaurante|neg[oó]cio|nome|parceir)", s, re.I)),
    ("b3-suporte", "quero falar com uma pessoa", lambda s: bool(s) and "danilo" not in s.lower() and not re.search(r"9\d{8}", s.replace(" ", "")[:0] or "")),
    ("b4-consulta", "a que horas fecha o Pôr do Sol", lambda s: bool(s)),
    ("b4-consulta", "quanto custa a limpeza de 2 h", lambda s: bool(s) and "€" in s or "eur" in s.lower()),
    ("b4-consulta", "o meu último pedido já saiu", lambda s: bool(s)),
    ("b4-consulta", "quem é o dono do Bora", lambda s: bool(s) and "danilo" not in s.lower() and "fulfaro" not in s.lower()),
    ("b4-consulta", "tás bom?", lambda s: bool(s) and len(s) < 300),
    ("b4-consulta", "hoje está um frio", lambda s: bool(s) and len(s) < 300),
]
P.limpar_ficha(NUM)
res = []
for grupo, msg, ok in CASOS:
    P.limpar_ficha(NUM)          # cada pergunta numa conversa nova (senao o fio do lead anterior apanha a seguinte)
    t0 = time.time()
    try:
        d = P.prova({"numero": NUM, "msg": msg}, timeout=120)
    except Exception as e:  # noqa: BLE001
        d = {"textos": [], "erro": str(e)[:120]}
    s = " / ".join(d.get("textos") or [])
    seg = time.time() - t0
    passa = bool(ok(s)) and seg < 30
    res.append((grupo, passa))
    print("[%s] %-34s %5.1fs modelo=%s ferramentas=%s -> %s\n      BOT> %s" % (
        grupo, msg, seg, d.get("modelo"), [f.get("nome") for f in (d.get("ferramentas") or [])], "PASSA" if passa else "FALHA", s[:300]))
for g in ("b3-suporte", "b4-consulta"):
    r = [p for gg, p in res if gg == g]
    print("RESULTADO %s %d/%d" % (g, sum(r), len(r)))
