#!/usr/bin/env python3
"""cortex_nightly.py — Manutencao noturna do Cortex (repo-side, DRY-RUN por defeito).

O cerebro cuida-se sozinho, MAS com trava humana:
  - DRY-RUN por defeito: PROPOE (escreve um relatorio); so aplica com --apply.
  - NUNCA toca paginas `zona: vermelha` (dinheiro/RLS/dispatch/pricing/tokens/stripe) -> so propoe.
  - Aditivo/reversivel: descartar = MOVER para inbox/_descartado (nunca apagar).

Faz:
  1. Confianca derivada por pagina (decaimento desde `ultima_confirmacao`).
  2. Regenera `_debt.md` (confianca < 50% OU > 180d OU origem NAO_VERIFICADO).
  3. Inbox aging: itens > 14 dias -> propoe promover (se referenciados) ou descartar.
  4. Contradiction scan (stub): cruza commits recentes de `wiki/codigo/` com sinais de negocio.

Uso:
  python cortex_nightly.py            # dry-run -> inbox/_reports/nightly-<hoje>.md
  python cortex_nightly.py --apply    # aplica: move inbox vencido p/ _descartado + reescreve _debt.md

Stdlib-only. Corre onde o cerebro VIVE (o repo). Ver ADR manutencao-cerebro-repo-side.
"""
import os, sys, re, json, subprocess
from datetime import date, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
KNOW = os.path.abspath(os.path.join(HERE, ".."))            # .../.ai/knowledge
INBOX = os.path.join(KNOW, "inbox")
DISCARD = os.path.join(INBOX, "_descartado")
REPORTS = os.path.join(INBOX, "_reports")
DEBT = os.path.join(KNOW, "_debt.md")
SIGNALS = os.path.join(INBOX, "_signals.json")             # opcional: pulso de negocio vindo do VPS

APPLY = "--apply" in sys.argv
TODAY = date.today()
AGE_LIMIT = 14        # dias no inbox antes de propor promover/descartar
CONF_FLOOR = 50.0     # abaixo disto = divida
STALE_DAYS = 180      # nao confirmado ha mais que isto = divida
PROTECTED = re.compile(r"dispatch|pricing|finalizepurchase|bora_tokens|stripe|\brls\b|wallet|ledger|refund|comiss|markup|service_fee", re.I)


def parse_front(text):
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm = {}
    for line in text[3:end].strip("\n").split("\n"):
        m = re.match(r"([a-zA-Z_]+):\s*(.*)$", line.strip())
        if m:
            fm[m.group(1)] = m.group(2).strip()
    return fm, text[end + 4:]


def pdate(s):
    try:
        return datetime.strptime((s or "")[:10], "%Y-%m-%d").date()
    except Exception:
        return None


def confidence(fm):
    origem = fm.get("origem", "")
    base = 40.0 if "NAO_VERIFICADO" in origem else 100.0
    d = pdate(fm.get("ultima_confirmacao", ""))
    if d:
        weeks = max(0.0, (TODAY - d).days / 7.0)
        base = max(0.0, base - weeks)             # -1%/semana
        vd = fm.get("validade_dias", "")
        if vd.isdigit() and (TODAY - d).days > int(vd):
            base = 0.0
    return round(base, 1)


def iter_pages():
    for root, dirs, files in os.walk(KNOW):
        dirs[:] = [d for d in dirs if d not in ("_arquivo", "_descartado", "_reports", "__pycache__", ".git")]
        for f in files:
            if f.endswith(".md"):
                yield os.path.join(root, f)


def read(p):
    try:
        with open(p, "r", encoding="utf-8") as fh:
            return fh.read()
    except Exception:
        return ""


def rel(p):
    return os.path.relpath(p, KNOW).replace("\\", "/")


def git(args):
    try:
        return subprocess.run(["git"] + args, cwd=KNOW, capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception:
        return ""


def main():
    debt, protected_touched = [], []
    for p in iter_pages():
        fm, _ = parse_front(read(p))
        if not fm:
            continue
        c = confidence(fm)
        d = pdate(fm.get("ultima_confirmacao", ""))
        stale = d and (TODAY - d).days > STALE_DAYS
        naoverif = "NAO_VERIFICADO" in fm.get("origem", "")
        if c < CONF_FLOOR or stale or naoverif:
            debt.append((rel(p), c, "NAO_VERIFICADO" if naoverif else ("stale>%dd" % STALE_DAYS if stale else "conf<%.0f" % CONF_FLOOR)))
        if fm.get("zona", "") == "vermelha":
            protected_touched.append(rel(p))

    # inbox aging (nunca toca _* internos)
    aged = []
    if os.path.isdir(INBOX):
        for f in sorted(os.listdir(INBOX)):
            fp = os.path.join(INBOX, f)
            if not os.path.isfile(fp) or not f.endswith(".md") or f == "README.md":
                continue
            fm, _ = parse_front(read(fp))
            d = pdate(fm.get("ultima_confirmacao", "")) or date.fromtimestamp(os.path.getmtime(fp))
            age = (TODAY - d).days
            if age > AGE_LIMIT:
                stem = f[:-3]
                referenced = any(("[[" + stem) in read(q) for q in iter_pages() if os.path.dirname(q).replace("\\", "/").endswith("wiki") or "/wiki/" in q.replace("\\", "/"))
                aged.append((f, age, "PROMOVER (referenciado)" if referenced else "DESCARTAR (nao referenciado)"))

    # contradiction scan (stub) — degrada com graca
    commits = git(["log", "--oneline", "-10", "--", ".obsidian-vault", "lib"]).splitlines()
    signals = {}
    if os.path.exists(SIGNALS):
        try:
            signals = json.load(open(SIGNALS, encoding="utf-8"))
        except Exception:
            signals = {}
    flags = []
    if signals.get("cancel_pct", 0) >= 20 and any(re.search(r"cancel|dispatch", c, re.I) for c in commits):
        flags.append("Commit recente mexeu em cancel/dispatch E cancelamentos >=20%% (sinal: %s)" % signals.get("cancel_pct"))
    if not signals:
        flags.append("[sem _signals.json do VPS] contradiction engine em modo parcial — ver ADR manutencao-cerebro-repo-side")

    # ---- report ----
    os.makedirs(REPORTS, exist_ok=True)
    lines = [
        "# Cortex nightly — %s  (%s)" % (TODAY.isoformat(), "APPLY" if APPLY else "DRY-RUN"),
        "",
        "## Divida (%d paginas)" % len(debt),
    ] + ["- `%s` — conf=%.1f%% — %s" % (r, c, why) for r, c, why in sorted(debt, key=lambda x: x[1])] + [
        "",
        "## Inbox aging (>%dd): %d" % (AGE_LIMIT, len(aged)),
    ] + ["- `%s` — %dd — %s" % (f, a, act) for f, a, act in aged] + [
        "",
        "## Zona vermelha (so PROPOSTA, nunca auto): %d" % len(protected_touched),
    ] + ["- `%s`" % r for r in protected_touched] + [
        "",
        "## Contradiction scan",
    ] + ["- %s" % f for f in flags]
    report = "\n".join(lines) + "\n"

    if APPLY:
        os.makedirs(DISCARD, exist_ok=True)
        moved = 0
        for f, a, act in aged:
            if act.startswith("DESCARTAR"):
                try:
                    os.replace(os.path.join(INBOX, f), os.path.join(DISCARD, f))
                    moved += 1
                except Exception:
                    pass
        with open(DEBT, "w", encoding="utf-8") as fh:
            fh.write("---\nid: knowledge-debt\ntipo: conceito\norigem: [gerado por _tools/cortex_nightly.py]\n"
                     "ultima_confirmacao: %s\nzona: verde\nconfianca: auto\n---\n\n" % TODAY.isoformat())
            fh.write("# KNOWLEDGE DEBT (auto-gerado %s)\n\n" % TODAY.isoformat())
            fh.write("| Pagina | Confianca | Motivo |\n|---|---|---|\n")
            for r, c, why in sorted(debt, key=lambda x: x[1]):
                fh.write("| `%s` | %.1f%% | %s |\n" % (r, c, why))
        report += "\n> APPLY: %d descartados movidos p/ _descartado; _debt.md reescrito.\n" % moved

    out = os.path.join(REPORTS, "nightly-%s.md" % TODAY.isoformat())
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(report)
    print(report)
    print("\n[cortex_nightly] relatorio: %s" % rel(out))


if __name__ == "__main__":
    main()
