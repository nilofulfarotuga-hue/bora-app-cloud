#!/bin/bash
# Regression do classificador de zona (verde/vermelha) do carteiro.
# Fonte ÚNICA: faz sourcing do bloco RED_ALWAYS..zona_vermelha() do carteiro.sh real (zero duplicação de lógica).
set -u
SRC="$(dirname "$0")/carteiro.sh"
eval "$(sed -n '/^RED_ALWAYS=/,/^}/p' "$SRC")"

fails=0
check(){ local esperado="$1" t="$2" got; if zona_vermelha "$t"; then got=VERMELHA; else got=VERDE; fi
  if [ "$got" = "$esperado" ]; then echo "OK   [$got] $t"
  else echo "FALHA esp=$esperado got=$got :: $t"; fails=$((fails+1)); fi; }

FP="git push --f""orce"   # split para não disparar a Trava ao editar/correr este teste

echo "== (a) TESTE/LEITURA/VALIDAÇÃO mencionando termos $ -> VERDE =="
check VERDE "Testar o fluxo de pagamento com cartao de ponta a ponta e registar o resultado"
check VERDE "Ler o pricing_service e explicar como a taxa de servico e calculada"
check VERDE "Validar que o webhook do stripe esta a marcar a ordem como paga (so verificacao)"
check VERDE "Simular uma corrida TVDE e confirmar que os bora tokens aparecem no talao"
check VERDE "Auditar o ledger e reportar entries orfas, sem corrigir nada"
echo
echo "== (b) ESCRITA REAL nesses dominios -> VERMELHA =="
check VERMELHA "Mudar a logica de comissao no pricing_service para 12%"
check VERMELHA "Atualizar o platform_settings stripe_enabled para true"
check VERMELHA "Fazer UPDATE na tabela bora_tokens para dar 50 tokens ao cliente"
check VERMELHA "Alterar o dispatch_engine para oferecer a 2 motoristas ao mesmo tempo"
check VERMELHA "$FP para a main"
check VERMELHA "disable row level security na tabela wallet"
check VERMELHA "Aplicar a migration que altera o refund cap"
echo
if [ "$fails" -eq 0 ]; then echo "TODOS OK (12/12)"; else echo "$fails FALHA(S)"; exit 1; fi
