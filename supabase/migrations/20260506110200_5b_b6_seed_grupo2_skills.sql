-- Sessão 5B-β1 B4 — Seed 3 skills Grupo 2 (write_shadow)
-- ACCOUNT_UPDATE, PASSWORD_RESET, CANCEL_PRE_PURCHASE
INSERT INTO public.support_skills
  (skill_name, version, category, mode,
   requires_human_handoff, playbook_md,
   allowed_tools, active)
VALUES
(
  'CANCEL_PRE_PURCHASE', 1, 'order_management',
  'write_shadow', false,
  $playbook$
## CANCEL_PRE_PURCHASE

Quando activar: cliente quer cancelar pedido pré-entrega
(status: created ou preparing).

⚠️ Acção IRREVERSÍVEL. Confirmar SEMPRE antes.
⚠️ Após admin aprovar: o sistema chama admin-cancel-order
   (Stripe refund automático em 3-5 dias úteis).

Passos:
1. agent_get_user_orders_summary → identificar pedido
2. Confirmar status: SÓ created ou preparing
3. Pedir confirmação ao cliente:
   "Tens a certeza? O pedido será cancelado e recebes
    o reembolso em 3-5 dias úteis (cartão) ou imediato
    (saldo Bora)."
4. Após confirmação → agent_propose_action_cancel
5. Informar: aguarda aprovação admin

Restrições CRÍTICAS:
- NUNCA callingDriver/driverAccepted/pickedUp/onTheWay
- Se estafeta já aceite → escala humano (HUMAN_REQUEST)
- Não cancelar delivered/cancelled

Reason recomendado: "client_request" (enum admin-cancel-order)

Exemplo few-shot:
User: "quero cancelar o meu pedido"
→ [agent_get_user_orders_summary]
→ "Vejo pedido Pizza Hut em preparação. Confirmas
   cancelamento? Reembolso automático após aprovação."
User: "sim"
→ [agent_propose_action_cancel skill=CANCEL_PRE_PURCHASE
   payload={order_id:'<id>', reason:'client_request: cliente desistiu'}
   reasoning='Cliente confirmou cancelamento pré-dispatch']
→ "Recebi. Aguarda aprovação (1-5min)."
  $playbook$,
  '["agent_propose_action","agent_propose_action_cancel"]'::jsonb,
  true
),
(
  'PASSWORD_RESET', 1, 'account_support',
  'write_shadow', false,
  $playbook$
## PASSWORD_RESET

Quando activar: cliente não consegue aceder e precisa
reset password.

Passos:
1. Confirmar identidade: pedir nome registado
2. NÃO pedir email — sistema usa automaticamente o email
   da conta autenticada (auth.users)
3. agent_propose_action_password com payload={}
4. Informar cliente

Restrições:
- Máx 2 resets por sessão
- Confirmação identidade OBRIGATÓRIA antes de propor
- Email vai SEMPRE para o registado na conta

Exemplo few-shot:
User: "esqueci a password"
→ "Para confirmar, qual o teu nome registado?"
User: "Maria Silva"
→ [agent_propose_action_password skill=PASSWORD_RESET
   payload={} reasoning='Cliente confirmou: Maria Silva']
→ "Vais receber email em 1-2 minutos após aprovação admin."
  $playbook$,
  '["agent_propose_action","agent_propose_action_password"]'::jsonb,
  true
),
(
  'ACCOUNT_UPDATE', 1, 'account_support',
  'write_shadow', false,
  $playbook$
## ACCOUNT_UPDATE

Quando activar: cliente quer actualizar nome OU telefone.

⚠️ NUNCA email, password, role, wallet, tokens, fcm_token.
   RPC bloqueia explicitamente esses campos (FORBIDDEN_FIELD).

Campos permitidos:
- name (2-100 chars) — nota: payload usa "name", não "full_name"
- phone (formato E.164: +351912345678)

Exemplo few-shot:
User: "quero mudar o nome para Ana Costa"
→ "Confirmas: Ana Costa?"
User: "sim"
→ [agent_propose_action_account skill=ACCOUNT_UPDATE
   payload={name:'Ana Costa'}
   reasoning='Cliente quer actualizar nome']
→ "Recebi. Será actualizado em breve após aprovação admin."

User: "novo telefone +351911222333"
→ "Confirmas: +351911222333?"
User: "sim"
→ [agent_propose_action_account
   payload={phone:'+351911222333'}
   reasoning='Cliente quer actualizar telefone']
  $playbook$,
  '["agent_propose_action","agent_propose_action_account"]'::jsonb,
  true
);
