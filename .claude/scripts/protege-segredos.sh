#!/usr/bin/env bash
# protege-segredos.sh — Trava de SEGREDOS (missão nunca-mais-travar, PASSO 3, 2026-08-01).
#
# NOTA DE LOCALIZAÇÃO: os outros guards vivem em `.claude/hooks/`, mas essa pasta é zona
# protegida e recusou a escrita (a Trava a proteger-se — comportamento correto). Este ficheiro
# fica em `.claude/scripts/` e é referenciado a partir do settings.json pelo caminho completo.
# Mover para `.claude/hooks/` é ato do Danilo, se preferir tudo no mesmo sítio.
#
# PORQUÊ: a auth do loop passou a viver em CLAUDE_CODE_OAUTH_TOKEN (token de subscrição
# sk-ant-oat01-…, ~1 ano de validade). O risco real NÃO é o código — é alguém colar o token
# num relatório de `.claude/.ai/reports/`, numa ordem do Córtex ou numa nota de missão, e isso
# ir parar ao git. Um token com um ano de vida num ficheiro versionado é um incidente lento.
#
# As travas existentes (`protege-dinheiro.sh`, `protege-banco.sh`) olham para DINHEIRO e DB;
# nenhuma olhava para credenciais. Esta é o terceiro guard, e é deliberadamente estreita:
# bloqueia SEGREDOS a entrar em ficheiros, não mais nada.
#
# Bloqueia (exit 2 = PreToolUse recusa a chamada):
#   · sk-ant-oat01-…  (token OAuth de subscrição — o do executor)
#   · sk-ant-api03-…  (chave de API)
#   · CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY seguidos de "=" e um valor real
# Em qualquer Write/Edit, e em comandos de shell que tragam o segredo inline.
#
# NÃO bloqueia o NOME da variável sozinho — senão nem esta missão se podia documentar. O que
# fica proibido é nome + valor. Referir `CLAUDE_CODE_OAUTH_TOKEN` num relatório é legítimo;
# colar `CLAUDE_CODE_OAUTH_TOKEN=<valor real>` não é.
set -u

payload=$(cat)

# Alvos: conteúdo a escrever (Write/Edit) e comandos de shell (Bash/PowerShell).
alvo=$(printf '%s' "$payload" | python -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
i = d.get("tool_input") or {}
partes = []
for k in ("content", "new_string", "command", "file_text"):
    v = i.get(k)
    if isinstance(v, str):
        partes.append(v)
sys.stdout.write("\n".join(partes))
' 2>/dev/null)

[ -n "${alvo:-}" ] || exit 0

achado=""
printf '%s' "$alvo" | grep -qE 'sk-ant-oat01-[A-Za-z0-9_-]{10,}' && achado="token OAuth de subscricao (sk-ant-oat01-...)"
[ -z "$achado" ] && printf '%s' "$alvo" | grep -qE 'sk-ant-api[0-9]{2}-[A-Za-z0-9_-]{10,}' && achado="chave de API Anthropic (sk-ant-api...)"
[ -z "$achado" ] && printf '%s' "$alvo" | grep -qE '(CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY)[[:space:]]*[=:][[:space:]]*["'\'']?[A-Za-z0-9_-]{16,}' && achado="variavel de credencial com valor real"

if [ -n "$achado" ]; then
  cat >&2 <<EOF
🔒 TRAVA DE SEGREDOS — escrita BLOQUEADA.

Detectado: $achado

Este conteudo ia parar a um ficheiro. O token do executor e' de SUBSCRICAO e dura ~1 ano —
num ficheiro versionado (codigo, relatorio em .claude/.ai/reports/, ordem do Cortex, nota de
missao) e' um incidente lento e silencioso.

O token vive SO no ambiente da maquina:
  setx /M CLAUDE_CODE_OAUTH_TOKEN "<token>"     (terminal como Administrador)

Se precisas de o referir num relatorio, escreve so o NOME da variavel, ou o comprimento
(ex.: "108 caracteres"), nunca o valor. Se o token ja foi exposto, revoga-o e gera outro
com 'claude setup-token'.
EOF
  exit 2
fi
exit 0
