#!/usr/bin/env python3
"""consolidador.py - MOTOR DE CONHECIMENTO (C1). Gera UM digest compacto e fresco.

Porque existe: o executor do loop arranca CEGO. Prova (auditoria 2026-07-20):
`carteiro.sh:502` corre `exec_ordem "$tarefa"` com a tarefa crua e o
`run-claude-loop.cmd:120` so junta o %GUARD% (disciplina de loop). Zero licoes.
Este script produz o ficheiro que o hook SessionStart (C2) vai injetar.

Principios (copiados do cortex_nightly.py, que ja provou o padrao):
  - stdlib-only, SO LEITURA sobre as fontes. Zero build, zero teste, zero LLM.
  - Escreve UM ficheiro, de forma ATOMICA (tmp + os.replace) -> nenhuma sessao
    apanha o digest a meio se calhar ler enquanto isto corre.
  - NUNCA faz git commit (regra do Danilo).
  - Teto DURO de tamanho: o digest nao pode sufocar o contexto do executor.
  - Frescura: aplica so factos `estado: atual`; `superado` fica na historia.

Uso:
  python consolidador.py               # corre (slot manual)
  python consolidador.py --slot 16h    # corre; auto-salta se a cadencia for "1x"
  python consolidador.py --dry-run     # imprime, nao escreve

Kill switch (por ordem de precedencia):
  1. ficheiro `.consolidador-parado` em knowledge/  -> para JA, sem rede
  2. platform_settings.knowledge_consolidator_enabled = false
"""
import io
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
KNOW = os.path.abspath(os.path.join(HERE, ".."))              # .../.ai/knowledge
AI = os.path.abspath(os.path.join(KNOW, ".."))                # .../.ai
REPO = os.path.abspath(os.path.join(AI, "..", ".."))          # raiz do bora_app
OUT = os.path.join(KNOW, "permanente", "procedural", "estado-atual-consolidado.md")
STATUS = os.path.join(KNOW, "inbox", "_reports", "digest-status.json")
PARAR = os.path.join(KNOW, ".consolidador-parado")

# Windows: stdout nasce cp1252 e rebenta em qualquer acento/seta do digest.
# (mesma familia da licao `convencoes.md` sobre encoding em Windows)
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

DRY = "--dry-run" in sys.argv
SLOT = "16h" if "--slot" in sys.argv and "16h" in sys.argv else "manual"

# --- Teto duro. 12 KB ~ 3.000 tokens. Passar disto e' sufocar o executor. ---
CAP_TOTAL = 12 * 1024
CAP_ARMADILHAS = 4600
CAP_LICOES = 3600
CAP_ABERTOS = 1800
CAP_REGRAS = 1600

INBOX_DIAS = 14          # so o inbox recente conta para "em aberto"
HOJE = date.today()

# Categorias por palavra-chave (id + origem + titulo). Ordem = precedencia.
CATEGORIAS = [
    ("orquestracao/loop", r"carteiro|orquestr|executor|loop|juiz|lock|ordem|fila|watchdog|heartbeat|parser|rate.?limit|anti.?trapaca"),
    ("base-de-dados/sql", r"\brls\b|rpc|migration|trigger|postgres|supabase|constraint|column|storage|bucket|policy"),
    ("flutter/ui", r"flutter|widget|ecra|screen|scroll|teclado|autocomplete|layout|provider|store\b"),
    ("dinheiro/pagamentos", r"stripe|pagamento|payout|token|refund|pricing|comiss|wallet|ledger|mbway"),
    ("infra/windows", r"crlf|eol|windows|powershell|docker|ssh|encoding|path|schtask|cron"),
    ("cerebro/memoria", r"cerebro|knowledge|memoria|obsidian|bibliotec|cortex|digest"),
]


# --------------------------------------------------------------------------
# frontmatter / leitura
# --------------------------------------------------------------------------
def read(path):
    try:
        with io.open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except Exception:
        return ""


def parse_front(text):
    """Devolve (dict_frontmatter, corpo). Aceita as 2 formas usadas no Cerebro:
    chaves em linhas proprias E a linha compacta `tema: x - escopo: y - estado: z`."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    raw, body = text[3:end], text[end + 4:]
    fm = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # linha compacta separada por · ou |
        for part in re.split(r"\s+[·|]\s+", line):
            if ":" in part:
                k, _, v = part.partition(":")
                k = k.strip().lower()
                if k and k not in fm:
                    fm[k] = v.strip()
    return fm, body


def pdate(s):
    if not s:
        return None
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", str(s))
    if not m:
        return None
    try:
        return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return None


def categoriza(blob):
    low = blob.lower()
    for nome, pat in CATEGORIAS:
        if re.search(pat, low):
            return nome
    return "geral"


def limpa(txt):
    """Achata markdown para uma linha legivel e curta."""
    txt = re.sub(r"`([^`]*)`", r"\1", txt)
    txt = re.sub(r"\*\*([^*]*)\*\*", r"\1", txt)
    txt = re.sub(r"\[\[([^\]]*)\]\]", r"\1", txt)
    txt = re.sub(r"\s+", " ", txt)
    return txt.strip(" -*·").strip()


# --------------------------------------------------------------------------
# fontes
# --------------------------------------------------------------------------
def iter_licoes():
    """Todas as licoes das 2 pastas. Devolve dicts ordenados por frescura."""
    out = []
    for sub in (("wiki", "licoes"), ("permanente", "procedural", "licoes")):
        d = os.path.join(KNOW, *sub)
        if not os.path.isdir(d):
            continue
        for nome in sorted(os.listdir(d)):
            if not nome.endswith(".md") or nome == "README.md":
                continue
            p = os.path.join(d, nome)
            txt = read(p)
            fm, body = parse_front(txt)
            if (fm.get("estado") or "").lower() == "superado":
                continue
            h1 = ""
            m = re.search(r"^#\s+(.+)$", body, re.M)
            if m:
                h1 = limpa(m.group(1))
                h1 = re.sub(r"^Li[cç][aã]o\s*[-—:]\s*", "", h1, flags=re.I)
            regra = extrai_regra(body)
            conf = pdate(fm.get("ultima_confirmacao")) or pdate(fm.get("atualizado"))
            out.append({
                "id": fm.get("id") or os.path.splitext(nome)[0],
                "zona": (fm.get("zona") or "?").lower(),
                "titulo": h1,
                "regra": regra,
                "data": conf,
                "cat": categoriza(" ".join([fm.get("id", ""), fm.get("origem", ""), h1])),
                "src": os.path.relpath(p, KNOW).replace("\\", "/"),
            })
    out.sort(key=lambda x: (x["data"] or date(2000, 1, 1)), reverse=True)
    return out


def extrai_regra(body):
    """Puxa o bloco accionavel da licao. As licoes do Bora usam 2 formas:
       `**Regra generalizavel.**` (paragrafo/bullets) e `- **Regra a aplicar:**`."""
    pat = re.compile(
        r"\*\*Regra(?:\s+(?:generaliz[aá]vel|a\s+aplicar))?\.?:?\*\*:?\s*(.*?)"
        r"(?=\n\s*\n\s*\*\*|\n\s*\n\s*#|\n\s*\n\s*>|\Z)",
        re.S | re.I,
    )
    m = pat.search(body)
    if not m:
        return ""
    bloco = m.group(1)
    pedacos = []
    for ln in bloco.splitlines():
        ln = limpa(ln)
        if len(ln) > 15:
            pedacos.append(ln)
    return " · ".join(pedacos[:3])[:400]


_MARK = r"(?:pend[êe]ncias?|em\s+aberto|por\s+fechar|falta\s+(?:s[óo]|apenas)|bloquead[oa]\s+por|blocker|TODO)"
# DOIS travoes contra falso-positivo (aprendido na 1a corrida, 2026-07-20): as paginas do
# Cerebro quebram linha a ~95 chars, entao (a) um marcador NU no inicio de linha e' quase
# sempre uma frase partida a meio -- exigimos **negrito** ou bullet; (b) o item verdadeiro
# continua nas linhas seguintes -- juntamo-las ate ao fim do paragrafo.
MARCADORES = re.compile(
    r"^\s*(?:"
    r"[-*+]\s+\*\*\s*%s\s*:?\s*\*\*"        # - **Pendência:**  /  - **Pendência**:
    r"|\*\*\s*%s\s*:?\s*\*\*"               # **Pendência:**
    r"|[-*+]\s+%s(?=\s*[:\-–])"             # - Pendência:
    r")\s*[:\-–]?\s*(.*)$" % (_MARK, _MARK, _MARK),
    re.I,
)
_CORTA = re.compile(r"^\s*(?:$|#{1,6}\s|[-*+]\s|\d+\.\s|\||>)")


def iter_abertos():
    """Itens explicitamente marcados como por-fechar, com a fonte a reboque.
    So o que esta marcado - nada de adivinhar o que e' um bug aberto."""
    alvos = []
    for rel in ("permanente/episodica/bugs-resolvidos.md",
                "permanente/episodica/decisoes.md",
                "_debt.md"):
        p = os.path.join(KNOW, rel)
        if os.path.isfile(p):
            alvos.append(p)
    inbox = os.path.join(KNOW, "inbox")
    corte = HOJE - timedelta(days=INBOX_DIAS)
    if os.path.isdir(inbox):
        for nome in os.listdir(inbox):
            if not nome.endswith(".md"):
                continue
            p = os.path.join(inbox, nome)
            try:
                mt = date.fromtimestamp(os.path.getmtime(p))
            except OSError:
                continue
            if mt >= corte:
                alvos.append(p)

    vistos, out = set(), []
    for p in alvos:
        linhas = read(p).splitlines()
        for i, ln in enumerate(linhas):
            m = MARCADORES.match(ln)
            if not m:
                continue
            pedacos = [m.group(1)]
            for cont in linhas[i + 1:]:          # junta a continuacao do paragrafo
                if _CORTA.match(cont):
                    break
                pedacos.append(cont)
                if len(" ".join(pedacos)) > 320:
                    break
            item = limpa(" ".join(pedacos))
            if len(item) < 20:
                continue
            if len(item) > 300:            # trunca no espaco, nunca descarta o item
                item = item[:297].rsplit(" ", 1)[0] + "…"
            chave = item.lower()[:80]
            if chave in vistos:
                continue
            vistos.add(chave)
            out.append({"item": item, "src": os.path.relpath(p, KNOW).replace("\\", "/")})
    return out


# --- (C) RUIDO: fragmentos que so fazem sentido colados ao paragrafo de origem.
# Injetar isto sem o contexto a volta ensina pouco e gasta o teto (2026-07-20).
_RUIDO = re.compile(
    r"^\s*(?:§|→|–|—)"                      # comeca por referencia/continuacao
    r"|^\s*decis[aã]o\s+[A-Za-z0-9]+\s*:"   # "Decisão B: ..."
    r"|^\s*escopo\b"                        # "Escopo APENAS markers E2E"
    r"|\.env\.test|markers\s+E2E"           # infra de teste, nao regra de negocio
    r"|^\s*\d+\s+produtos\b"                # "63 produtos wells.pt ..." = registo
    r"|foram\s+(?:deletad|removid|apagad|migrad)",  # relato do passado, nao invariante
    re.I,
)
# --- (A) PESO: o teto passa a cortar o menos critico, nao o que calha vir depois.
# DINHEIRO EM MOVIMENTO (o que a Lista Vermelha protege: valor cobrado/pago) vem
# ANTES de preco-de-catalogo. Sem esta separacao as dezenas de regras de scraper
# ("NUNCA produto sem preco") afogam as de pagamento - provado em 2026-07-20.
_MOVIMENTO = re.compile(
    r"refund|reembolso|payout|buffer|stripe|mb\s?way|wallet|ledger|comiss|"
    r"\bfee\b|pagamento|cobra|ganho|desconto|token|€",
    re.I,
)
_CATALOGO = re.compile(r"pre[çc]o|markup|pricing|produto|scraper|glovo", re.I)
_SEGURANCA = re.compile(r"\brls\b|service_role|auth\.|polic|bucket|jwt|secret|segur", re.I)


def peso(txt, src):
    if src == "CLAUDE.md":
        return 0                    # nucleo arquitetural: barato e inegociavel
    if _MOVIMENTO.search(txt):
        return 1                    # dinheiro real a mexer-se
    if _CATALOGO.search(txt):
        return 2                    # preco de catalogo / scraper
    if _SEGURANCA.search(txt):
        return 3
    return 4


def iter_regras():
    """Invariantes de negocio. Fonte: CLAUDE.md (nucleo) + linhas NUNCA/SEMPRE
    do business_rules.md (190 KB - nunca entra inteiro, so os imperativos).
    Ordenado por peso: dinheiro e seguranca entram primeiro, por construcao."""
    out = []
    claude_md = read(os.path.join(REPO, "CLAUDE.md"))
    m = re.search(r"###\s*Core Rules.*?\n(.*?)(?=\n##|\Z)", claude_md, re.S)
    if m:
        for ln in m.group(1).splitlines():
            ln = limpa(ln)
            if len(ln) > 10:
                out.append({"regra": ln, "src": "CLAUDE.md", "tag": "CM"})

    br = os.path.join(AI, "business_rules.md")
    if os.path.isfile(br):
        for bruto in read(br).splitlines():
            if not re.search(r"\b(NUNCA|SEMPRE|IMUT[ÁA]VEL|OBRIGAT[ÓO]RI)", bruto):
                continue
            if _RUIDO.search(bruto.strip().lstrip("-*+ ").lstrip(">").strip()):
                continue
            ln = limpa(bruto)
            if 25 < len(ln) < 260:
                out.append({"regra": ln, "src": "business_rules.md", "tag": "BR"})

    out.sort(key=lambda r: peso(r["regra"], r["src"]))     # sort estavel
    return out


# --------------------------------------------------------------------------
# kill switch
# --------------------------------------------------------------------------
def env_de(path, chaves):
    got = {}
    for ln in read(path).splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("#") or "=" not in ln:
            continue
        k, _, v = ln.partition("=")
        k = k.strip()
        if k in chaves:
            got[k] = v.strip().strip('"').strip("'")
    return got


def publica_estado(estado, preview):
    """C3: o digest vive no disco do PC — o app Flutter nunca lhe chega. Esta e' a
    ponte: grava o estado numa tabela para a Central de Autonomia o mostrar.
    BEST-EFFORT: se a rede/credencial falhar, o digest local ja esta escrito e
    valido; so o cartao do admin fica desatualizado. Nunca rebenta a corrida."""
    cfg = env_de(os.path.join(REPO, "backend", ".env"),
                 {"SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"})
    url = os.environ.get("SUPABASE_URL") or cfg.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or cfg.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        return "sem credenciais"
    linha = {
        "id": True,
        "gerado_em": estado["gerado_em"],
        "tamanho_bytes": estado["tamanho_bytes"],
        "licoes": estado["licoes"], "armadilhas": estado["armadilhas"],
        "em_aberto": estado["em_aberto"], "regras": estado["regras"],
        "cortadas": estado["cortadas"], "cadencia": estado["cadencia"],
        "preview": preview[:2000],
        "atualizado_em": datetime.now().isoformat(timespec="seconds"),
    }
    req = urllib.request.Request(
        "%s/rest/v1/knowledge_digest_status?on_conflict=id" % url.rstrip("/"),
        data=json.dumps(linha).encode("utf-8"),
        headers={"apikey": key, "Authorization": "Bearer " + key,
                 "Content-Type": "application/json",
                 "Prefer": "resolution=merge-duplicates,return=minimal"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return "ok (%s)" % r.status
    except (urllib.error.URLError, OSError) as e:
        return "falhou (%s)" % type(e).__name__


def le_settings():
    """Le as 2 chaves em platform_settings. RLS: SELECT so para `authenticated`,
    logo usa a service_role do backend/.env (gitignored). Devolve (dict, nota)."""
    cfg = env_de(os.path.join(REPO, "backend", ".env"),
                 {"SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"})
    url = os.environ.get("SUPABASE_URL") or cfg.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or cfg.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        return {}, "sem credenciais locais"
    alvo = ("%s/rest/v1/platform_settings?select=key,value"
            "&key=in.(knowledge_consolidator_enabled,knowledge_consolidator_cadence)"
            % url.rstrip("/"))
    req = urllib.request.Request(alvo, headers={
        "apikey": key, "Authorization": "Bearer " + key, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            linhas = json.loads(r.read().decode("utf-8"))
        return {d["key"]: d["value"] for d in linhas}, "ok"
    except (urllib.error.URLError, ValueError, KeyError, OSError) as e:
        return {}, "inacessivel (%s)" % type(e).__name__


# --------------------------------------------------------------------------
# montagem
# --------------------------------------------------------------------------
def secao(titulo, linhas, cap):
    """Junta linhas ate ao teto da seccao. Devolve (texto, usadas, cortadas)."""
    buf, usadas = [], 0
    tam = 0
    for ln in linhas:
        if tam + len(ln) + 1 > cap:
            break
        buf.append(ln)
        tam += len(ln) + 1
        usadas += 1
    cortadas = len(linhas) - usadas
    if cortadas > 0:
        buf.append("- _(+%d nao couberam no teto desta seccao)_" % cortadas)
    return titulo + "\n" + "\n".join(buf) + "\n", usadas, cortadas


def main():
    if os.path.isfile(PARAR):
        print("PARADO: existe %s (kill switch local)." % PARAR)
        return 0

    settings, nota_set = le_settings()
    ligado = settings.get("knowledge_consolidator_enabled")
    if ligado is False:
        print("PARADO: knowledge_consolidator_enabled=false.")
        return 0
    cadencia = settings.get("knowledge_consolidator_cadence") or "2x"
    if SLOT == "16h" and cadencia == "1x":
        print("SALTADO: cadencia=1x, o slot das 16h nao corre.")
        return 0

    licoes = iter_licoes()
    abertos = iter_abertos()
    regras = iter_regras()

    # ---- Bloco 1: armadilhas (a licao que tem regra accionavel) ----
    arm = ["- **%s** — %s _(%s)_" % (l["titulo"], l["regra"], l["id"])
           for l in licoes if l["regra"] and l["titulo"]]
    # ---- Bloco 2: restantes licoes, agrupadas por categoria ----
    porcat = {}
    for l in licoes:
        if l["regra"] and l["titulo"]:
            continue
        if not l["titulo"]:
            continue
        porcat.setdefault(l["cat"], []).append("  - %s _(%s)_" % (l["titulo"], l["id"]))
    lic = []
    for cat in sorted(porcat):
        lic.append("- **%s**" % cat)
        lic.extend(porcat[cat])

    ab = ["- %s _(%s)_" % (a["item"], a["src"]) for a in abertos]
    # Etiqueta compacta em vez de `_(business_rules.md)_`: 24 B -> 4 B por linha.
    # Com ~20 regras isso sao ~400 B recuperados DENTRO do mesmo teto.
    rg = ["- [%s] %s" % (r["tag"], r["regra"]) for r in regras]

    agora = datetime.now()
    cab = (
        "---\n"
        "id: estado-atual-consolidado\n"
        "tipo: conceito\n"
        "origem: [auto-gerado por _tools/consolidador.py]\n"
        "ultima_confirmacao: %s\n"
        "zona: verde\n"
        "confianca: auto\n"
        "estado: atual\n"
        "---\n\n"
        "# ESTADO ATUAL CONSOLIDADO — o que ja sabemos\n\n"
        "> **AUTO-GERADO** por `_tools/consolidador.py` em **%s**. Nao editar a mao.\n"
        "> Fontes: %d licoes vigentes · %d itens em aberto · %d regras. Toggle: %s.\n"
        "> Se esta pagina tiver mais de 24h, trata-a como possivelmente desatualizada.\n\n"
    ) % (HOJE.isoformat(), agora.strftime("%Y-%m-%d %H:%M"),
         len(licoes), len(abertos), len(regras), nota_set)

    partes = [cab]
    s1, u1, c1 = secao("## 1. ARMADILHAS — nao repetir estes erros\n", arm, CAP_ARMADILHAS)
    s2, u2, c2 = secao("\n## 2. LICOES VIGENTES POR CATEGORIA\n", lic, CAP_LICOES)
    s3, u3, c3 = secao("\n## 3. EM ABERTO / POR FECHAR\n", ab, CAP_ABERTOS)
    s4, u4, c4 = secao(
        "\n## 4. REGRAS DE NEGOCIO EM VIGOR\n"
        "_Ordem: dinheiro-em-movimento > preco-de-catalogo > seguranca > resto._\n"
        "_[CM]=CLAUDE.md · [BR]=business_rules.md_\n",
        rg, CAP_REGRAS)
    partes += [s1, s2, s3, s4]
    doc = "".join(partes)

    if len(doc.encode("utf-8")) > CAP_TOTAL:          # rede de seguranca final
        doc = doc.encode("utf-8")[:CAP_TOTAL].decode("utf-8", "ignore")
        doc += "\n\n> _(truncado no teto duro de %d bytes)_\n" % CAP_TOTAL

    tam = len(doc.encode("utf-8"))
    if DRY:
        sys.stdout.write(doc)
        print("\n--- DRY-RUN: %d bytes, nao escrito ---" % tam)
        return 0

    escreve_atomico(OUT, doc)
    estado = {
        "gerado_em": agora.isoformat(timespec="seconds"),
        "tamanho_bytes": tam,
        "licoes": len(licoes), "armadilhas": u1, "em_aberto": u3, "regras": u4,
        "cortadas": c1 + c2 + c3 + c4,
        "toggle": nota_set, "cadencia": cadencia, "slot": SLOT,
        "digest": os.path.relpath(OUT, KNOW).replace("\\", "/"),
    }
    escreve_atomico(STATUS, json.dumps(estado, ensure_ascii=False, indent=2))
    estado["admin"] = publica_estado(estado, doc)      # C3: ponte para o painel
    escreve_atomico(STATUS, json.dumps(estado, ensure_ascii=False, indent=2))
    print("OK: %s (%d bytes) · %d armadilhas · %d licoes · %d abertos · %d regras · admin=%s"
          % (estado["digest"], tam, u1, u2, u3, u4, estado["admin"]))
    return 0


def escreve_atomico(destino, conteudo):
    """tmp no MESMO volume + os.replace = troca atomica. Nenhum leitor apanha
    o ficheiro a meio (os.replace e' atomico tambem no Windows)."""
    d = os.path.dirname(destino)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    fd, tmp = tempfile.mkstemp(dir=d or ".", prefix=".tmp-", suffix=".part")
    try:
        with io.open(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(conteudo)
        os.replace(tmp, destino)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


if __name__ == "__main__":
    sys.exit(main())
