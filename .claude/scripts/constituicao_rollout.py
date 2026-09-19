# -*- coding: utf-8 -*-
"""constituicao_rollout.py — F1 missão 2026-07-10: todos os agentes citam a constituição
no topo do contrato (1 linha, logo após o frontmatter). Idempotente; preserva EOL/UTF-8."""
import codecs
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
AGENTS = REPO / ".claude" / "agents"
LINE = "> 📜 Rejo-me pela [Constituição do Bora](../.ai/knowledge/permanente/semantica/constituicao.md) — os 10 princípios valem acima deste contrato."
SKIP = {"README.md"}

changed, skipped = [], []
for f in sorted(AGENTS.glob("*.md")):
    if f.name in SKIP:
        continue
    data = f.read_bytes()
    bom = data.startswith(codecs.BOM_UTF8)
    if bom:
        data = data[len(codecs.BOM_UTF8):]
    nl = "\r\n" if b"\r\n" in data else "\n"
    text = data.decode("utf-8").replace("\r\n", "\n")
    if "Constituição do Bora" in text:
        skipped.append(f.stem)
        continue
    lines = text.split("\n")
    ins = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                ins = i + 1
                break
    lines[ins:ins] = ["", LINE] if ins else [LINE, ""]
    out = "\n".join(lines)
    if nl == "\r\n":
        out = out.replace("\n", "\r\n")
    raw = out.encode("utf-8")
    if bom:
        raw = codecs.BOM_UTF8 + raw
    f.write_bytes(raw)
    changed.append(f.stem)

print("alterados:", len(changed), "| skip:", len(skipped))
print(", ".join(changed))
