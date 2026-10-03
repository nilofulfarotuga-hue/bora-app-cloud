-- Sessão 5F B2 — Seed skill ASK_ROBOT_B
-- mode=escalate (pergunta encaminhada Robô A → Robô B)
-- allowed_tools=['agent_ask_robot_b'] — tool enforcement chatbot v7 B3
-- Idempotente via ON CONFLICT (skill_name UNIQUE).

INSERT INTO public.support_skills (
  skill_name, version, category, mode,
  requires_human_handoff, playbook_md,
  allowed_tools, examples, active
) VALUES (
  'ASK_ROBOT_B', 1, 'technical_support', 'escalate', false,
$playbook$
## ASK_ROBOT_B

Quando activar: cliente reporta problema técnico DA APP
(comportamento app — NÃO sobre pedido/pagamento/entrega/conta).

Exemplos típicos:
- "app não abre" / "app fecha sozinha"
- "botão X não funciona"
- "erro ao fazer pedido" *(erro técnico, não disputa)*
- "app muito lenta" / "ecrã preto"
- "não consigo fazer login com password certa"

NÃO usar para:
- Estado de pedido → ORDER_STATUS
- Pagamento / reembolso → skills payment / REFUND_*
- Entrega / morada → UPDATE_DELIVERY_ADDRESS
- Conta / dados pessoais → ACCOUNT_UPDATE
- Pedido falar com humano (sem problema técnico) → HUMAN_REQUEST

Diferenciação com HUMAN_REQUEST:
- ASK_ROBOT_B: bug ou comportamento inesperado da app
- HUMAN_REQUEST: cliente pede explicitamente humano

Passos:
1. Recolher info técnica:
   - O que aconteceu? (descrição)
   - Quando? (último uso, frequência)
   - Em que ecrã / acção?
   - Mensagem de erro? (se visível)
2. Sugerir soluções básicas primeiro:
   - Fechar app + reabrir
   - Verificar internet
   - Reiniciar telemóvel
3. Se o problema persiste → invocar tool agent_ask_robot_b com:
   - question: descrição completa (será anonimizada server-side)
   - context: { screen_name?, error_message?, frequency? }
4. Confirmar ao cliente: "Registei o problema para análise técnica.
   A equipa vai verificar e contactaremos se precisarmos mais info."

Exemplo de fluxo:
User: "a app fecha sempre que abro o mapa"
→ "Já tentaste fechar e reabrir a app? Internet estável?"
User: "sim, e acontece sempre que clico no mapa"
→ [agent_ask_robot_b
     question='App fecha quando abre o mapa, sempre reproduzível'
     context={"screen_name":"map","frequency":"always"}]
→ "Registei o problema. A equipa técnica vai analisar.
   Obrigado pela paciência!"
$playbook$,
  '["agent_ask_robot_b"]'::jsonb,
  '[]'::jsonb,
  true
)
ON CONFLICT (skill_name) DO NOTHING;
