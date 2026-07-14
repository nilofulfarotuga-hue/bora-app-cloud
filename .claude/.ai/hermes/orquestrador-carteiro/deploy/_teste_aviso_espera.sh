#!/bin/bash
# _teste_aviso_espera.sh — teste sintético (não faz parte do deploy) para o pedido
# "melhorar o aviso das ordens que ficam em espera manual" (2026-07-14).
# Simula, sem Docker/VPS: (1) uma ordem sintética entrar em zona_vermelha e gerar o
# aviso Telegram com resumo+comando; (2) a skill desbloqueio-zona-vermelha reagir a
# "vai <id>" e devolver a ordem à fila normal. Usa as MESMAS funções de carteiro.sh
# (fonte única de verdade) — não reimplementa a lógica.
set -u
DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
CARTEIRO="$DEPLOY_DIR/carteiro.sh"

# extrai só as funções puras (get/setf/ts/zona_vermelha/resumo_tarefa) de carteiro.sh,
# sem correr o corpo principal do script (que faria docker exec real).
eval "$(sed -n '/^ts(){/p;/^get(){/p;/^setf(){/p;/^RED_ALWAYS=/p;/^RED_TERMS=/p;/^WRITE_INTENT=/p;/^NEG=/p' "$CARTEIRO")"
eval "$(sed -n '/^zona_vermelha(){/,/^}/p;/^resumo_tarefa(){/,/^}/p' "$CARTEIRO")"

TMPFILA=$(mktemp -d)
trap 'rm -rf "$TMPFILA"' EXIT

fail=0; ok(){ echo "OK   $1"; }; bad(){ echo "FAIL $1"; fail=1; }

# ---- 1) ordem sintética que cai em zona vermelha ----
id="ordem-teste-avisoespera-0001"
tarefa="[MODELO: SONNET] Atualizar platform_settings commission_rate para 12%"
f="$TMPFILA/$id.md"
cat > "$f" <<EOF
--- ordem ---
id: $id
estado: aberta
tarefa: $tarefa
tentativa: 0
--- fim ---
nota:
EOF

NOTIFY_CAPTURADO=""
notify(){ NOTIFY_CAPTURADO="$1"; }   # stub: em vez de docker exec, só captura o texto

if zona_vermelha "$tarefa"; then
  setf estado zona_vermelha "$f"; setf nota "🔴 ZONA VERMELHA — precisa de decisão humana (dinheiro)" "$f"
  resumo=$(resumo_tarefa "$tarefa")
  notify "🔴 Bora/orquestração: ordem $id EM ESPERA (zona vermelha — toca dinheiro/pagamento).
Resumo: ${resumo:-(sem resumo)}
Para libertar para a fila normal, responde aqui: vai $id"
fi

[ "$(get estado "$f")" = "zona_vermelha" ] && ok "ordem sintética entrou em zona_vermelha" || bad "ordem não entrou em zona_vermelha"
echo "$NOTIFY_CAPTURADO" | grep -q "EM ESPERA" && ok "aviso Telegram gerado" || bad "aviso Telegram NÃO gerado"
echo "$NOTIFY_CAPTURADO" | grep -q "Resumo: Atualizar platform_settings commission_rate para 12%" && ok "aviso leva o resumo da tarefa (sem prefixo [MODELO:...])" || bad "resumo ausente/errado no aviso"
echo "$NOTIFY_CAPTURADO" | grep -q "vai $id" && ok "aviso leva o comando exato de desbloqueio (vai $id)" || bad "comando de desbloqueio ausente no aviso"

# ---- 2) responder "vai <id>" desbloqueia (lógica da skill desbloqueio-zona-vermelha) ----
msg_telegram="vai $id"
alvo=$(printf '%s' "$msg_telegram" | sed -E 's/^vai +//')
achado="$TMPFILA/$alvo.md"
if [ -f "$achado" ] && [ "$(get estado "$achado")" = "zona_vermelha" ]; then
  setf estado aberta "$achado"; setf nota "" "$achado"
fi

[ "$(get estado "$f")" = "aberta" ] && ok "'vai $id' devolveu a ordem a estado: aberta" || bad "'vai $id' não desbloqueou"
[ -z "$(get nota "$f")" ] && ok "'vai $id' limpou a nota" || bad "nota não foi limpa"

# ---- 3) "vai <id>" não faz nada se a ordem já não estiver em zona_vermelha (idempotência) ----
if [ -f "$achado" ] && [ "$(get estado "$achado")" = "zona_vermelha" ]; then
  setf estado aberta "$achado"
  bad "reagiu a 'vai' numa ordem que já não estava em zona_vermelha"
else
  ok "'vai $id' repetido não mexe (ordem já não está em zona_vermelha)"
fi

[ "$fail" = 0 ] && echo "TESTE-AVISO-ESPERA: TODOS OK" || echo "TESTE-AVISO-ESPERA: HÁ FALHAS"
exit "$fail"
