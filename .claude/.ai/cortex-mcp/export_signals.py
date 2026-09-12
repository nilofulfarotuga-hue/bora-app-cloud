#!/usr/bin/env python3
# export_signals.py — tira a contradiction engine do "modo parcial".
# Lê o último pulso do Hermes (READ-ONLY) + commits recentes do brain e escreve
# inbox/_signals.json, que o cortex_nightly.py cruza (commit × negócio). Não toca produção.
import json, os, re, subprocess

BRAIN = "/opt/data/cortex-brain/.claude/.ai/knowledge"
PULSE_LOG = "/opt/data/daily-pulse/_pulse-log.jsonl"
OUT = os.path.join(BRAIN, "inbox", "_signals.json")


def last_pulse():
    try:
        with open(PULSE_LOG, encoding="utf-8") as f:
            lines = [l for l in f if l.strip()]
        return json.loads(lines[-1]) if lines else {}
    except Exception:
        return {}


def num(pat, text, d=0.0):
    m = re.search(pat, text)
    return float(m.group(1)) if m else d


p = last_pulse()
txt = " ".join(p.get("sinais", []))
cancel_pct = num(r"[Cc]ancelamento\s+(\d+(?:\.\d+)?)\s*%", txt)
crashes = int(num(r"(\d+)\s+crash", txt))
try:
    commits = subprocess.run(["git", "-C", BRAIN, "log", "--oneline", "-15"],
                             capture_output=True, text=True, timeout=15).stdout.splitlines()
except Exception:
    commits = []

out = {"gerado": p.get("ts"), "day": p.get("day"),
       "cancel_pct": cancel_pct, "crashes": crashes, "commits_recentes": commits[:15]}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print("signals ->", json.dumps({k: out[k] for k in ("day", "cancel_pct", "crashes")}))
