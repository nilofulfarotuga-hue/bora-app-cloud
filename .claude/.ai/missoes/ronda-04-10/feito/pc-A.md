# Bloco A — dinheiro das entregas (Claude Code no PC, 05/10/2026)

Ordem do Danilo: "faz tudo o que falta da revisão geral de 04/10. Eu autorizo." + "autorizo tudo" na conversa.
A Trava (settings.json deny + protege-banco.sh) proíbe editar e publicar stripe-webhook,
finalize-order-from-intent, refund, reprocess-refund, create-*-payment-intent e client-cancel-order.
Não foi contornada: o que mexe nessas funções ficou pronto em `pronto/stripe-webhook-v36/`.

## A.1 — valor cobrado pela Stripe (stripe_charge_cents)
- **Causa:** ninguém gravava `orders.stripe_charge_cents` (6 de 7 MB Way pagos estavam a 0). O limite de
  reembolso do banco compara com ele, por isso reembolsar um MB Way pago falhava sempre.
- **Feito (no ar):** função `registar_cobranca_stripe` (só service_role; migração 20261005085601);
  reconciliador v5 com a parte D, que lê a Stripe e grava; cron `payments-reconciler-cobrancas` de 10 em 10 min
  (20261005085945); ajudante `_shared/cobranca_stripe.ts` usado pelos cancelamentos.
- **Prova:** 7 pedidos preenchidos com o mesmo valor que a Stripe cobrou (lidos de volta no banco);
  função fechada a anon e a authenticated (has_function_privilege).
- **Falta (Trava):** gravar no próprio webhook e no finalize → `pronto/stripe-webhook-v36/` (v36 e v14).

## A.2 — admin-cancel-order devolve o que foi cobrado (v14, no ar)
- Stripe só o que a Stripe cobrou e ainda se pode devolver; carteira + tokens voltam à carteira (80/20,
  chave = id do pedido); nunca acima do preço; tokens só contam com `tokens_applied_count > 0`.
- **Encontrado:** o botão "Cancelar pedido" do painel estava parado desde 03/10 — a função `admin_cancel_order`
  tinha perdido o EXECUTE para quem tem sessão. Reposto (20261005090735); prova: cliente demo é recusado
  ("admin_required"), anon continua sem acesso.
- Falha parcial depois da Stripe → `refund_status = 'needs_review'` (o Reprocessar não lhe pega, não devolve a
  dobrar) + alerta pelo reconciliador. Stripe falhou → `failed` com o valor certo para o Reprocessar.

## A.3 — webhook 5xx + idempotência por event.id
- Tabela `stripe_webhook_events` aplicada (20261005091349; RLS ligada, 0 políticas, anon/authenticated sem acesso).
- O webhook v36 (pronto) usa-a e devolve 500 em falhas reais. **Simulação: v36 passa 10 de 10; o v35 do ar
  passa 1 de 10 com o mesmo guião.** Falta publicar (Trava).

## A.4 — índice único em orders(payment_intent_id)
- 0 duplicados antes. Aplicado (20261005084411). Prova: indexdef lido de volta.

## A.5 — pedidos "pagos sem cobrar"
- **Causa:** era o A.1 (valor cobrado a 0). Depois de preenchido sobrou 1 pedido (6c102c39, 16/09): MB Way
  falhou (a Stripe nunca cobrou), os 0,24 € de tokens voltaram à carteira, mas o estado diz "refunded".
  O dinheiro está certo; o rótulo está errado. Fica registado como achado `pago_sem_cobranca` no painel.

## A.6 — trava contra duplo toque e admin no servidor (no ar)
- `execute-cancellation` v15: **aceitava admin pelo `user_metadata`, que qualquer utilizador pode editar —
  qualquer conta podia aprovar e executar reembolsos.** Agora `is_admin()` no servidor. Trava atómica no pedido.
- `cancel-order-with-choice` v18: trava atómica (2.º toque → 409); MB Way também volta pela Stripe; reparte
  por fonte; recusa repetir depois de `needs_review`.
- Revisão de contexto limpo feita duas vezes; os defeitos que apanhou foram corrigidos antes de publicar.
- Publicação: 5 funções, cada ficheiro lido de volta do ar e igual ao disco (diff), cada uma responde pelo
  próprio código (400 de validação com a chave de serviço; 401 sem token).

## A.7 — webhook: reserva TVDE, plano, lavagem, gorjeta, reembolso a dobrar na lavagem
- **Lavagem a dobrar:** corrigido no `carwash-checkout` v2 (no ar): se a cobrança já tem devolução não devolve
  outra vez; chave de idempotência; nunca acima do cobrado.
- **Reserva TVDE por MB Way com a app fechada, km do plano, lavagem e gorjeta no webhook:** no v36 (pronto,
  simulado). A lavagem por cartão é só pré-autorizada e não chega ao webhook como paga — decisão para o Danilo.

## A.8 — crédito do estafeta não duplica
- O saldo somava sempre que o pedido voltava a "entregue". Corrigido (20261005084442).
- Prova (transacção desfeita): 20,25 → 24,25 → 24,25, uma só transacção.

## A.9 — repo igual ao ar
- `tmp-connect-link`: o repo tinha a versão antiga com senha escrita no código; agora é o stub 410 do ar.
- `confirm-mbway-payment`: não publicada e sem nenhuma chamada — apagada do repo.
- `stripe-webhook`: a cópia exacta do ar (v35) está em `pronto/stripe-webhook-v36/ar-v35-index.ts`; o ficheiro do
  repo está trancado.
- 5 migrações de hoje que só estavam no ar copiadas para o repo.

## Achado grave fora da lista (não mexido — dinheiro real)
- Pedido bba0f503 (12/09, cliente real): a carteira foi creditada **7 vezes** pelo mesmo cancelamento (antes de
  existir a chave de repetição) — 50,91 € creditados num pedido de 7,07 €. O saldo dela hoje é 0. Decidir.
- Pedidos 6158b439 e e1078830: MB Way + carteira somam mais do que o preço (o excedente da pré-autorização,
  regra do Danilo: não se devolve).

## Verificação
- `deno check` sem erros novos; `python .claude/juiz/anti_trapaca.py --base 8108952c` limpo;
  `flutter analyze` 0 erros (6 avisos antigos em ficheiros não tocados).
