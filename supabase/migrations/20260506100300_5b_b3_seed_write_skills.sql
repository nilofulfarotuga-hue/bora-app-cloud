-- Sessão 5B-α B3 — Seed 2 skills WRITE shadow (Grupo 1)
-- OTP_RESEND adiado para 5B-β.
-- allowed_tools é jsonb (validado em A0).

INSERT INTO public.support_skills
  (skill_name, version, category, mode,
   requires_human_handoff, playbook_md,
   allowed_tools, active)
VALUES
(
  'UPDATE_DELIVERY_INSTRUCTIONS', 1, 'order_management',
  'write_shadow', false,
  $playbook$
## UPDATE_DELIVERY_INSTRUCTIONS

Quando activar: cliente quer mudar instruções de entrega
de um pedido activo (ex: "diz ao estafeta para deixar à porta",
"tocar à campainha 3B").

⚠️ NOTA TÉCNICA: A skill chama-se UPDATE_DELIVERY_INSTRUCTIONS
mas a coluna real na DB é orders.customer_notes. O RPC mapeia
automaticamente — não te preocupes com isso.

⚠️ Skill WRITE em modo shadow: PROPÕE acção.
Não é leitura — para consultar pedido usa
agent_get_user_orders_summary primeiro.

Passos:
1. Identificar order_id (usar agent_get_user_orders_summary
   se cliente não disser qual)
2. Confirmar novo texto (max 200 chars) com o cliente
3. Chamar agent_propose_action:
   - skill_name: "UPDATE_DELIVERY_INSTRUCTIONS"
   - action_type: "UPDATE_DELIVERY_INSTRUCTIONS"
   - action_payload: {order_id: "<id>", new_value: "<texto>"}
   - agent_reasoning: "Cliente pediu X para pedido Y"
4. Informar cliente: "Recebi. As instruções serão actualizadas
   após confirmação do admin."

Restrições:
- Status do pedido tem de ser: created, preparing, callingDriver
  ou driverAccepted
- NÃO permitido em: pickedUp, onTheWay, delivered, cancelled
  (já demasiado tarde)
- Texto máximo 200 chars (substitui texto antigo, não acumula)

Exemplo few-shot:
User: "podes pôr nas instruções para deixar na portaria"
→ [agent_get_user_orders_summary]
→ "Vejo o pedido activo da Pizza Hut. Confirmas que queres
   alterar as instruções para 'deixar na portaria'?"
User: "sim"
→ [agent_propose_action skill_name=UPDATE_DELIVERY_INSTRUCTIONS
   action_type=UPDATE_DELIVERY_INSTRUCTIONS
   action_payload={order_id:"<id>", new_value:"deixar na portaria"}
   agent_reasoning:"Cliente pediu mudança nas instruções"]
→ "Recebi. As instruções serão actualizadas em breve após
   confirmação do admin."
  $playbook$,
  '["agent_propose_action"]'::jsonb,
  true
),
(
  'UPDATE_DELIVERY_ADDRESS', 1, 'order_management',
  'write_shadow', false,
  $playbook$
## UPDATE_DELIVERY_ADDRESS

Quando activar: cliente quer mudar morada de entrega.

⚠️ Skill WRITE em modo shadow.

Passos:
1. Identificar order_id (usar agent_get_user_orders_summary)
2. Confirmar nova morada COMPLETA (rua, número, andar, código postal)
3. Verificar status: SÓ created ou preparing
4. Chamar agent_propose_action

Restrições CRÍTICAS:
- NUNCA mudar morada quando status é callingDriver ou posterior
  (estafeta pode estar a caminho do pickup)
- Morada deve ser na zona servida (Guarda, Portugal)
- Fora de zona → escala humano via skill HUMAN_REQUEST
- A morada substitui completamente a anterior; coords (lat/lng)
  são reset e re-geocoded no próximo dispatch

Exemplo few-shot:
User: "preciso mudar morada para Rua X 5"
→ [agent_get_user_orders_summary, vejo pedido em status=preparing]
→ "Ainda dá para mudar — o pedido está em preparação.
   Confirmas a morada completa: Rua X, 5, Guarda?"
User: "sim, andar 2 esquerdo"
→ [agent_propose_action skill_name=UPDATE_DELIVERY_ADDRESS
   action_type=UPDATE_DELIVERY_ADDRESS
   action_payload={order_id:"<id>", new_address:"Rua X, 5, 2º Esq, Guarda"}
   agent_reasoning:"Cliente quer alterar morada antes do pickup"]
→ "Recebi. A morada será actualizada após confirmação do admin."
  $playbook$,
  '["agent_propose_action"]'::jsonb,
  true
);
