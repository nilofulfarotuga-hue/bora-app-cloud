# -*- coding: utf-8 -*-
"""
evolution_engine.py — motor mecânico da meta-skill evolution-engine (Fase 5, missão
noturna 2026-07-09/10). READ-ONLY sobre as skills; escreve SÓ o relatório de propostas
em .claude/.ai/knowledge/inbox/evolution-report-<data>.md (+ estado em scripts/state/).

5 capacidades (deteção mecânica; a redação de drafts é do agente, o gate é do Juiz):
  1. padrões    — tópico repetido ≥3× nos nomes de reports sem skill correspondente
  2. reescrita  — falhas/execucoes > 30% (com execucoes ≥ 1)
  3. arquivo    — ultima_execucao há > 90 dias
  4. fusão      — descrições de 2 skills com semelhança > 70% (difflib)
  5. divisão    — SKILL.md > 600 linhas

Governança: propostas 🔴 (skill toca dinheiro/auth) = SÓ PROPOSTA (Danilo aplica).
Propostas já rejeitadas (estado 'rejeitada' em state/propostas.json) NÃO se repropõem.
A própria evolution-engine nunca é alvo de draft — só aviso 'AUTO-MODIFICAÇÃO'.
"""

import argparse
import difflib
import io
import json
import re
import sys
from collections import Counter
from datetime import date, datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO = SCRIPT_DIR.parents[3]  # .claude/skills/evolution-engine/scripts -> repo
SKILLS_DIR = REPO / ".claude" / "skills"
REPORTS_DIR = REPO / ".claude" / ".ai" / "reports"
INBOX = REPO / ".claude" / ".ai" / "knowledge" / "inbox"
STATE_FILE = SCRIPT_DIR / "state" / "propostas.json"

RED_ZONE_PAT = re.compile(
    r"stripe|pricing|refund|promo|payout|pagamento|wallet|token|comiss|fee_|"
    r"platform_setting|deploy-edge|ledger|settlement|auth\b", re.IGNORECASE)

SELF = "evolution-engine"

STOPWORDS = {
    "loop", "relatorio", "report", "sessao", "session", "fix", "bug", "plano",
    "auditoria", "investigacao", "resumo", "final", "noite", "noturna", "fase",
    "2026", "bora", "app", "admin", "e2e", "tvde", "md", "e", "de", "do", "da"}


def parse_frontmatter(path):
    """Frontmatter simples (1 nível + metadata aninhada) -> dict plano."""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    except OSError:
        return {}
    if not lines or lines[0].strip() != "---":
        return {}
    out = {}
    for ln in lines[1:]:
        if ln.strip() in ("---", "..."):
            break
        m = re.match(r"^\s*([\w\-]+)\s*:\s*(.*)$", ln)
        if m:
            key, val = m.group(1), m.group(2).strip().strip('"').strip("'")
            if key not in out or ln[0] not in (" ", "\t"):
                out.setdefault(key, val)
            if ln[0] in (" ", "\t"):  # chave aninhada (metadata) tem prioridade p/ telemetria
                out[key] = val
    return out


def to_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def to_date(v):
    if not v or str(v).lower() in ("null", "none", "~", ""):
        return None
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", str(v))
    return date(int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def load_state():
    if STATE_FILE.is_file():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass
    return {"propostas": {}}


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def zone_of(name, desc):
    return "🔴" if RED_ZONE_PAT.search(name + " " + desc) else "🟢"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="não escreve relatório nem estado")
    ap.add_argument("--data", default=None, help="YYYY-MM-DD (default: hoje)")
    args = ap.parse_args()

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    today = to_date(args.data) or date.today()
    skills = {}
    for f in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        fm = parse_frontmatter(f)
        try:
            n_lines = len(f.read_text(encoding="utf-8", errors="replace").split("\n"))
        except OSError:
            n_lines = 0
        skills[f.parent.name] = {
            "desc": fm.get("description", ""),
            "execucoes": to_int(fm.get("execucoes")),
            "falhas": to_int(fm.get("falhas")),
            "ultima": to_date(fm.get("ultima_execucao")),
            "linhas": n_lines,
        }

    proposals = []  # (key, capacidade, zona, alvo, evidencia, acao)

    # 2. reescrita — taxa de falha
    for name, s in skills.items():
        ex, fa = s["execucoes"], s["falhas"]
        if ex and fa is not None and ex > 0 and fa / ex > 0.30:
            proposals.append((
                "reescrita:" + name, "Reescrever", zone_of(name, s["desc"]), name,
                "falhas/execucoes = {}/{} = {:.0f}%".format(fa, ex, 100 * fa / ex),
                "draft v+1 pelo agente; Juiz compara v atual vs v+1"))

    # 3. arquivo — 90d sem uso (só com data conhecida)
    for name, s in skills.items():
        if s["ultima"] and (today - s["ultima"]).days > 90:
            proposals.append((
                "arquivo:" + name, "Arquivar", zone_of(name, s["desc"]), name,
                "ultima_execucao {} ({} dias)".format(s["ultima"], (today - s["ultima"]).days),
                "mover para _arquivo/ (nunca apagar)"))

    # 4. fusão — descrições >70% semelhantes
    names = sorted(skills)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            da, db = skills[a]["desc"], skills[b]["desc"]
            if len(da) > 40 and len(db) > 40:
                ratio = difflib.SequenceMatcher(None, da.lower(), db.lower()).ratio()
                if ratio > 0.70:
                    zona = "🔴" if "🔴" in (zone_of(a, da), zone_of(b, db)) else "🟢"
                    proposals.append((
                        "fusao:{}+{}".format(a, b), "Fundir", zona, "{} + {}".format(a, b),
                        "descrições {:.0f}% sobrepostas".format(100 * ratio),
                        "proposta de fusão (uma skill absorve a outra)"))

    # 5. divisão — >600 linhas
    for name, s in skills.items():
        if s["linhas"] > 600:
            proposals.append((
                "divisao:" + name, "Dividir", zone_of(name, s["desc"]), name,
                "SKILL.md com {} linhas (>600)".format(s["linhas"]),
                "proposta de split por responsabilidade"))

    # 1. padrões — tópicos repetidos ≥3× nos reports sem skill correspondente
    tokens = Counter()
    if REPORTS_DIR.is_dir():
        for f in REPORTS_DIR.glob("*.md"):
            for t in re.split(r"[^a-z0-9]+", f.stem.lower()):
                if len(t) >= 4 and t not in STOPWORDS and not t.isdigit():
                    tokens[t] += 1
    skill_blob = " ".join(names).lower()
    for tok, cnt in tokens.most_common(40):
        if cnt >= 3 and tok not in skill_blob:
            proposals.append((
                "padrao:" + tok, "Detetar padrão", "🟢", "(skill nova?) tópico '" + tok + "'",
                "{} reports com '{}' no nome e nenhuma skill correspondente".format(cnt, tok),
                "avaliar skill nova com draft (agente redige, Juiz avalia)"))

    # governança: dedup contra estado + guarda de auto-modificação
    state = load_state()
    seen = state.get("propostas", {})
    fresh, skipped_rejected = [], 0
    for p in proposals:
        key = p[0]
        if seen.get(key, {}).get("estado") == "rejeitada":
            skipped_rejected += 1
            continue
        fresh.append(p)
    for p in fresh:
        seen.setdefault(p[0], {"estado": "proposta", "primeira_vez": str(today)})
    state["propostas"] = seen

    # relatório
    out_path = INBOX / "evolution-report-{}.md".format(today)
    buf = io.StringIO()
    buf.write("---\nid: evolution-report-{}\ntipo: relatorio\n".format(today))
    buf.write("origem: [evolution-engine v1 — análise mecânica sobre telemetria + reports]\n")
    buf.write("ultima_confirmacao: {}\nzona: verde\nconfianca: auto\n---\n\n".format(today))
    buf.write("# 🧬 Evolution Report — {}\n\n".format(today))
    buf.write("> Gerado por `evolution_engine.py` (deteção mecânica). Drafts = agente; gate = Juiz.\n")
    buf.write("> 🟢 = draft possível após Juiz · 🔴 = SÓ PROPOSTA (dinheiro/auth — Danilo aplica).\n\n")
    buf.write("Skills analisadas: **{}** · Propostas novas: **{}** · Rejeitadas (não repropostas): {}\n\n".format(
        len(skills), len(fresh), skipped_rejected))

    # Higiene do Cérebro (F4 2026-07-10): 5 piores páginas >60d, vindas do cortex_nightly
    stale_file = REPO / ".claude" / ".ai" / "knowledge" / "inbox" / "_reports" / "stale-pages.json"
    if stale_file.is_file():
        try:
            st = json.loads(stale_file.read_text(encoding="utf-8"))
            buf.write("## 🧹 Higiene do Cérebro — {} páginas >60d (5 piores)\n\n".format(st.get("total_60d", "?")))
            for pg in st.get("piores5", []):
                buf.write("- `{}` — {} dias{}\n".format(pg.get("pagina"), pg.get("dias"),
                          " 🔴 (só proposta)" if pg.get("zona_vermelha") else ""))
            buf.write("\n")
        except (OSError, ValueError):
            pass

    # Loop Economy (F1 2026-07-10): sinalizar loops suspeitos quando houver telemetria
    buf.write("## 🔁 Loops (Loop Economy)\n\n")
    buf.write("Telemetria de loops (custo_acumulado × retorno) ainda sem dados — o economy check "
              "dispara a partir do 1.º ciclo com os pares preenchidos em `loops.md`. Regra: muitas "
              "execuções + custo alto + retorno ≈ 0 → propor otimizar/arquivar (🟢/🔵 NUNCA auto).\n\n")
    if fresh:
        buf.write("| Capacidade | Zona | Alvo | Evidência | Ação recomendada |\n|---|---|---|---|---|\n")
        for _, cap, zona, alvo, ev, acao in fresh:
            nota = " ⚠️ AUTO-MODIFICAÇÃO — só o Danilo" if SELF in alvo else ""
            buf.write("| {} | {} | `{}` | {} | {}{} |\n".format(cap, zona, alvo, ev, acao, nota))
    else:
        buf.write("Nenhuma proposta nova neste ciclo.\n")
    buf.write("\n*Estado de propostas em `.claude/skills/evolution-engine/scripts/state/propostas.json`"
              " — marcar `\"estado\": \"rejeitada\"` para não repropor.*\n")
    report = buf.getvalue()

    print("Skills analisadas: {} | propostas novas: {} | suprimidas (rejeitadas): {}".format(
        len(skills), len(fresh), skipped_rejected))
    for _, cap, zona, alvo, ev, _ in fresh[:15]:
        print("  {} {} -> {} ({})".format(zona, cap, alvo, ev))
    if len(fresh) > 15:
        print("  ... +{} propostas no relatório".format(len(fresh) - 15))

    if args.dry_run:
        print("[dry-run] relatório NÃO escrito ({})".format(out_path))
        return 0
    INBOX.mkdir(parents=True, exist_ok=True)
    out_path.write_text(report, encoding="utf-8")
    save_state(state)
    print("Relatório: {}".format(out_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
