#!/bin/bash
# Abre o guardrail de git ao ramo `ios-lancamento` — missão ios-lancamento, 2026-09-07.
#
# PORQUE É UM SCRIPT E NÃO FOI FEITO PELA SESSÃO
# A sessão do Claude Code tem escrita negada em `.claude/hooks/` (tentado por
# Edit e por Bash — ambos recusados pela Trava). O Danilo autorizou a alteração;
# quem a aplica tem de ser um processo fora dessa restrição. É este.
#
# O QUE FAZ, exactamente três coisas:
#   1. Junta "ios-lancamento" a RAMOS_PERMITIDOS no git-guardrails.py local.
#   2. Aponta o .claude/settings.json local para a cópia LOCAL do hook
#      (estava a apontar para a árvore antiga do Desktop).
#   3. Prova que continua a bloquear o que tem de bloquear.
#
# O QUE NÃO FAZ: não desliga o hook, não mexe nas outras regras, não toca noutros
# ramos, não faz merge para produção.
#
# Correr com:  bash ios/tools/abrir-guardrail-para-ios.sh

set -euo pipefail

REPO="C:/BoraLocal/projetosflutter/bora_app"
PY="$REPO/.claude/hooks/git-guardrails.py"
SETTINGS="$REPO/.claude/settings.json"
ANTIGO_SH="C:/Users/danil/Desktop/projetosflutter/bora_app/.claude/hooks/git-guardrails.sh"
NOVO_SH="$REPO/.claude/hooks/git-guardrails.sh"

cd "$REPO"

echo "══════════ ANTES ══════════"
grep -n '^RAMOS_PERMITIDOS' "$PY" || true
grep -n 'git-guardrails.sh' "$SETTINGS" || true
BK="$REPO/.claude/hooks/git-guardrails.py.bak-$(date +%Y%m%d-%H%M%S)"
cp "$PY" "$BK"
cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
echo "cópias de segurança feitas."

# ── 1. lista de ramos ────────────────────────────────────────────────────────
python - "$PY" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
antigo = 'RAMOS_PERMITIDOS = ["autonomous-night-2026-04-29"]'
novo = (
    '# 2026-09-07 (missao ios-lancamento), por ordem do Danilo: juntou-se\n'
    '# "ios-lancamento". E o ramo de trabalho do lancamento na App Store e\n'
    '# nenhum workflow de publicacao dispara nele -- build_android.yml e\n'
    '# build_web_deploy.yml so correm em autonomous-night-2026-04-29 (lido dos\n'
    '# proprios YAML). O resto do guardrail fica igual: push forcado, --delete,\n'
    '# reset --hard, clean -f, branch -D e checkout . continuam bloqueados em\n'
    '# TODOS os ramos.\n'
    'RAMOS_PERMITIDOS = ["autonomous-night-2026-04-29", "ios-lancamento"]'
)
if 'ios-lancamento' in s:
    print('  (ja estava aberto — nada a fazer)')
else:
    assert s.count(antigo) == 1, 'ancora RAMOS_PERMITIDOS nao encontrada uma so vez'
    io.open(p, 'w', encoding='utf-8', newline='\n').write(s.replace(antigo, novo, 1))
    print('  lista de ramos actualizada.')
PY

# ── 2. settings.json a apontar para a copia local ────────────────────────────
python - "$SETTINGS" "$ANTIGO_SH" "$NOVO_SH" <<'PY'
import io, json, sys
p, antigo, novo = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding='utf-8').read()
if antigo in s:
    io.open(p, 'w', encoding='utf-8', newline='\n').write(s.replace(antigo, novo))
    print('  settings.json a apontar para a copia local.')
else:
    print('  (settings.json ja nao apontava para o Desktop)')
json.load(io.open(p, encoding='utf-8'))   # rebenta se o JSON ficou partido
print('  settings.json continua a ser JSON valido.')
PY

echo ""
echo "══════════ DEPOIS ══════════"
grep -n '^RAMOS_PERMITIDOS' "$PY"
grep -n 'git-guardrails.sh' "$SETTINGS"
python -c "import py_compile;py_compile.compile(r'$PY',doraise=True);print('  o guardrail compila.')"

# ── 3. prova de que continua a proteger ──────────────────────────────────────
echo ""
echo "══════════ PROVA — o que passa e o que continua barrado ══════════"
testa() {
  local desc="$1" cmd="$2" esperado="$3"
  local saida rc
  saida=$(printf '{"tool_input":{"command":%s}}' "$(python -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$cmd")" \
          | bash "$NOVO_SH" 2>&1) && rc=0 || rc=$?
  if [ "$esperado" = "passa" ]; then
    [ "$rc" = "0" ] && echo "  ✅ $desc — passa (correcto)" || echo "  ❌ $desc — foi BARRADO e não devia: $saida"
  else
    [ "$rc" = "2" ] && echo "  ✅ $desc — barrado (correcto)" || echo "  ❌ $desc — PASSOU e não devia (rc=$rc)"
  fi
}

testa "push para ios-lancamento"                "git push -u origin ios-lancamento" passa
testa "push para autonomous-night-2026-04-29"   "git push origin autonomous-night-2026-04-29" passa
testa "push para main"                          "git push origin main" barra
testa "push forcado para ios-lancamento"        "git push --force origin ios-lancamento" barra
testa "reset --hard"                            "git reset --hard HEAD~1" barra
testa "clean -fd"                               "git clean -fd" barra
testa "branch -D"                               "git branch -D ios-lancamento" barra
testa "apagar ramo remoto"                      "git push origin --delete ios-lancamento" barra

echo ""
echo "Se todas as linhas acima têm ✅, está feito. A cópia de segurança ficou em:"
echo "  $BK"
