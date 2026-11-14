#!/usr/bin/env bash
# ===========================================================================
#  MOTOR DE CONHECIMENTO (C2) — hook SessionStart: injeta o digest no contexto.
#
#  Porque existe: o executor do loop arrancava CEGO. Prova (auditoria 2026-07-20):
#  carteiro.sh:502 corre `exec_ordem "$tarefa"` com a tarefa crua e o
#  run-claude-loop.cmd:120 so junta o %GUARD%. Zero licoes, zero Cerebro.
#  Este hook e' o unico ponto onde o conhecimento entra — e NAO toca no
#  carteiro.sh nem no run-claude-loop.cmd (a esteira que funciona fica intacta).
#
#  Porque vive aqui e nao em .claude/hooks/: a Trava protege .claude/hooks/**
#  (protege-dinheiro.sh:54). Este script e' zona verde (so le e imprime), por
#  isso vive ao lado do consolidador que o alimenta. O settings.json aponta ca'.
#
#  LEI: FAIL-OPEN. Se o digest faltar, estiver vazio ou algo rebentar, sai 0
#  SEM emitir nada e a sessao arranca na mesma. Um hook de contexto NUNCA pode
#  ser o motivo de uma sessao nao comecar.
# ===========================================================================
set +e

AQUI="$(cd "$(dirname "$0")" && pwd)"
DIGEST="$AQUI/../permanente/procedural/estado-atual-consolidado.md"
LOG="$AQUI/../inbox/_reports/injecao-digest.log"
MAX_BYTES=14336          # teto de seguranca; o digest ja tem teto proprio de 12 KB
# 14/11/2026 (missao sistema-conteudo-14-11, bloco 1.2): as ultimas 25 linhas da pagina
# erros-aprendidos do livro entram NO TOPO (antes do digest, para nao serem cortadas se a
# saida do gancho passar do limite). Copia local renovada de hora a hora pela tarefa
# agendada BoraRenovarLivro (~/.claude/livro/renovar-livro.cmd -> livro-ao-acordar.mjs).
# Caminho absoluto de reserva porque o executor do loop corre como outro utilizador (hermes).
ULTIMAS="$HOME/.claude/cache/livro/erros-ultimas.md"
[ -s "$ULTIMAS" ] || ULTIMAS="/c/Users/danil/.claude/cache/livro/erros-ultimas.md"

# O proprio log e' best-effort: se a pasta nao existir, nem uma linha de erro
# pode escapar para o stderr do hook.
registra() {
  [ -d "$(dirname "$LOG")" ] 2>/dev/null || return 0
  printf '%s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG" 2>/dev/null
  return 0
}

[ -s "$DIGEST" ] || { registra "SEM-DIGEST (fail-open, sessao arranca sem contexto extra)"; exit 0; }

# ARMADILHA WINDOWS (apanhada 2026-07-20): `command -v python3` devolve o STUB da
# Microsoft Store (WindowsApps/python3), que nao e' Python — imprime o anuncio da
# loja e sai 49. Nao basta ENCONTRAR o interpretador: tem de se PROVAR que corre.
#
# ARMADILHA 2 (apanhada 2026-07-20 pela prova no loop REAL): o executor corre
# como o utilizador `hermes` (SSH), nao como `danil`. O Python esta instalado
# POR-UTILIZADOR do danil, entao para o hermes `where python` nao devolve nada
# e o hook fazia fail-open -> o executor arrancava cego. Prova:
#   whoami -> laptop-2q09vqa1\hermes ; where python -> nao encontrado
#   mas C:\Users\danil\...\Python312\python.exe existe no disco.
# Por isso: depois do PATH, tentar caminhos ABSOLUTOS conhecidos.
PY=""
tenta_py() {
  [ -n "$1" ] || return 1
  case "$1" in *WindowsApps*) return 1;; esac         # stub da Store, nunca serve
  "$1" -c "print(1)" >/dev/null 2>&1 || return 1      # prova de vida
  PY="$1"; return 0
}

for cand in python python3 py; do
  tenta_py "$(command -v "$cand" 2>/dev/null)" && break
done

if [ -z "$PY" ]; then                                  # PATH nao serviu (caso hermes)
  for abs in /c/Users/danil/AppData/Local/Programs/Python/Python*/python.exe \
             /c/Python*/python.exe \
             "/c/Program Files/Python"*/python.exe; do
    tenta_py "$abs" && break
  done
fi

[ -n "$PY" ] || { registra "SEM-PYTHON-UTIL (fail-open)"; exit 0; }

# O python monta o JSON — escapar markdown a mao e' como se parte um hook.
saida=$("$PY" - "$DIGEST" "$MAX_BYTES" "$ULTIMAS" <<'PYEOF' 2>/dev/null
import hashlib, io, json, os, sys, time

# ARMADILHA WINDOWS (apanhada 2026-07-20, 3a vez no mesmo dia): o stdout nasce
# cp1252 e QUALQUER seta/acento vindo do digest rebenta o print. Duas redes:
# (1) forcar utf-8 no stdout; (2) ensure_ascii=True -> o JSON sai em \uXXXX,
# valido em qualquer codepage. Um hook nao pode depender da consola.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

try:
    caminho, teto = sys.argv[1], int(sys.argv[2])
    with io.open(caminho, "r", encoding="utf-8", errors="replace") as fh:
        corpo = fh.read()
    if not corpo.strip():
        sys.exit(0)                      # vazio = fail-open silencioso

    if len(corpo.encode("utf-8")) > teto:
        corpo = corpo.encode("utf-8")[:teto].decode("utf-8", "ignore")

    # Carimbo de frescura: o executor tem de saber se isto ja apodreceu.
    horas = (time.time() - os.path.getmtime(caminho)) / 3600.0
    if horas > 24:
        frescura = ("ATENCAO: este resumo tem %.0fh (>24h) - o consolidador pode estar parado. "
                    "Trata-o como possivelmente desatualizado e confirma antes de agir." % horas)
    else:
        frescura = "Gerado ha %.1fh - fresco." % horas

    # CANARIO: prova verificavel de que este bloco chegou ao modelo. Deriva do
    # conteudo, entao tambem prova QUAL digest chegou.
    canario = hashlib.sha256(corpo.encode("utf-8")).hexdigest()[:8]

    cabecalho = (
        "# CONHECIMENTO ACUMULADO DO BORA (injetado automaticamente)\n\n"
        "DIGEST-BORA-OK: %s\n\n"
        "%s\n\n"
        "Isto e' o que o projeto ja aprendeu - licoes de erros passados, regras de negocio em "
        "vigor e assuntos por fechar. LE ANTES DE AGIR: se a tarefa tocar algo aqui descrito, "
        "segue a regra registada em vez de reinventar. Nao repitas os erros da seccao ARMADILHAS.\n\n"
        "PRIMEIRO DE TUDO, ANTES DE QUALQUER PLANO: le PADRAO_BORA.md na raiz do repositorio. "
        "E' a lei da casa - a lista fechada do que uma categoria ou papel novo tem de ter para "
        "estar lancado, a regra dos gemeos (onde cada verdade vive), as regras de prova, as de "
        "publicacao e segredos, como o Danilo trabalha, e as zonas que nao se tocam. Cada regra "
        "la dentro tem a cicatriz real que a originou, com data.\n\n"
        "---\n\n"
    ) % (canario, frescura)

    # 14/11 (bloco 1.2): ultimas 25 linhas de erros-aprendidos, no TOPO. Falha aqui = sem o bloco.
    ultimas = ""
    try:
        cam_u = sys.argv[3] if len(sys.argv) > 3 else ""
        if cam_u and os.path.isfile(cam_u):
            with io.open(cam_u, "r", encoding="utf-8", errors="replace") as fu:
                linhas_u = [l.rstrip() for l in fu.read().splitlines() if l.strip()]
            corpo_u = [l if len(l) <= 180 else l[:177] + "..." for l in linhas_u[1:26]]
            if corpo_u:
                horas_u = (time.time() - os.path.getmtime(cam_u)) / 3600.0
                ultimas = (
                    "# ERROS-APRENDIDOS - ULTIMAS 25 LINHAS DO LIVRO (copia local de ha %.1fh)\n\n"
                    "Correcoes do Danilo a todos os agentes. Nao repitas nenhuma. Quando ele te "
                    "corrigir, grava NA HORA com a skill aprender (select public.livro_aprender(...)).\n\n"
                    "%s\n\n---\n\n" % (horas_u, "\n".join(corpo_u))
                )
    except Exception:
        ultimas = ""

    # 14/11 (bloco 2.5, medido com /context): a saida de um gancho acima de ~10 000 caracteres vai
    # para ficheiro e NAO entra no contexto (o digest de 15 KB estava a perder-se quase todo).
    # Teto total de 9500 caracteres: as 25 linhas primeiro, o digest leva o que sobra.
    TETO_TOTAL = 9500
    sobra = TETO_TOTAL - len(ultimas) - len(cabecalho)
    if sobra < len(corpo):
        corpo = corpo[:max(sobra - 80, 0)] + "\n\n[... digest cortado para caber no contexto; ficheiro inteiro: .claude/.ai/knowledge/permanente/procedural/estado-atual-consolidado.md]"

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": ultimas + cabecalho + corpo,
        }
    }, ensure_ascii=True))
    sys.stderr.write("canario=%s bytes=%d\n" % (canario, len(corpo.encode("utf-8"))))
except Exception as e:                   # fail-open a serio
    sys.exit(0)
PYEOF
)

# So emite se o python devolveu JSON valido. Lixo -> silencio -> sessao normal.
case "$saida" in
  '{"hookSpecificOutput"'*) printf '%s\n' "$saida"; registra "OK bytes=${#saida} source=${CLAUDE_SESSION_SOURCE:-?}" ;;
  *)                        registra "SAIDA-INVALIDA (fail-open)" ;;
esac
exit 0
