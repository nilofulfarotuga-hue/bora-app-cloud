-- Sessão 5A-2 B17 — Seed 9 skills read-only
-- Idempotente: ON CONFLICT(skill_name) DO UPDATE incrementa version + actualiza playbook.
-- Valores LITERAIS de business_rules.md + fn_award_tokens_on_delivery (validado MCP).
-- TOKENS_INFO usa fórmula real GREATEST(1, ROUND(price×3)) + expira 60 dias.

INSERT INTO public.support_skills
  (skill_name, category, mode, requires_human_handoff, playbook_md, allowed_tools, active)
VALUES
('ORDER_STATUS', 'orders', 'read_only', false,
'# ORDER_STATUS

**Quando usar:** user pergunta onde está o pedido, ETA, se estafeta chegou.

**Tools:** `agent_get_order_status(p_order_id)`

**Conduta:**
- Pede order_id se não fornecido em contexto.
- Chama tool e devolve `current_step` (texto PT já traduzido pelo RPC).
- Mostra nome do estafeta se disponível.
- Se `can_be_cancelled=true` → menciona possibilidade de cancelar.
- ETA exacto NÃO disponível (NULL hoje); diz "estafeta a caminho" sem inventar minutos.

**Estados conhecidos (camelCase real):**
created · preparing · callingDriver · driverAccepted · pickedUp · onTheWay · delivered · cancelled · rejected.

**[VERIFICAR]** ETA real (5C com `driver_locations` + Mapbox/Directions).

**Limitação:** se RPC devolve ORDER_NOT_FOUND_OR_NOT_OWNER, escala para humano.',
'["agent_get_order_status"]'::jsonb, true),

('ORDER_HISTORY', 'orders', 'read_only', false,
'# ORDER_HISTORY

**Quando usar:** "últimos pedidos", "histórico", "pedido de ontem".

**Tools:** `agent_get_user_orders_summary(p_limit)` (1-20, default 5)

**Conduta:**
- Apresenta lista com order_id curto (8 chars), partner_name, status, total formatado.
- `can_be_cancelled = status IN (created, preparing, callingDriver)`.
- Não calcula totais agregados; só mostra individual.

**Limitação:** apenas pedidos do user actual (auth.uid()).',
'["agent_get_user_orders_summary"]'::jsonb, true),

('WALLET_INFO', 'wallet', 'read_only', false,
'# WALLET_INFO

**Quando usar:** "saldo wallet", "quanto tenho?", "estado da carteira".

**Tools:** `agent_get_user_wallet_summary()`

**Valores literais (business_rules.md §28):**
- Soft cap (gate): **−€10** (RAISE WALLET_BLOCKED em create_order)
- Hard floor (DB CHECK): **−€20** (`free_balance_cents >= -2000`)
- Wallet free isenta IVA Art. 53.º CIVA (regime simplificado)

**Conduta:**
- Mostra saldo em € (free_balance_cents/100).
- Se saldo negativo, explica liquidação no próximo pedido.
- Se bloqueado (`is_blocked=true`), encaminha para skill WALLET_BLOCKED_HELP.
- **NUNCA** prometes valores específicos de "quando vai ser cobrado" — wallet liquida-se automaticamente.

**[VERIFICAR]** wallet promocional 80/20 — não existe em produção (5B+).',
'["agent_get_user_wallet_summary"]'::jsonb, true),

('WALLET_BLOCKED_HELP', 'wallet', 'read_only', false,
'# WALLET_BLOCKED_HELP

**Quando usar:** user reporta "wallet bloqueada" ou "não consigo comprar".

**Tools:** `agent_get_user_wallet_summary()`

**Conduta:**
- Confirma `is_blocked=true` via tool antes de explicar.
- Explicação literal: "Saldo abaixo de **−€10** (soft cap §28.2). Para desbloquear, basta fazer um novo pedido — o valor é descontado automaticamente."
- Se user pede "liquidar manualmente" → escala HUMAN_REQUEST.

**[VERIFICAR]** prazo limite legal antes de cobrança forçada (§28 não define).',
'["agent_get_user_wallet_summary"]'::jsonb, true),

('TOKENS_INFO', 'tokens', 'read_only', false,
'# TOKENS_INFO

**Quando usar:** "tokens", "quantos pontos?", "quando expiram?".

**Tools:** `agent_get_user_tokens_summary()`

**Valores literais (validados via MCP em fn_award_tokens_on_delivery + business_rules.md §tokens):**
- **Cliente ganha:** `GREATEST(1, ROUND(price × 3))` tokens por entrega (mínimo 1)
- **Estafeta normal:** +40 tokens por entrega
- **Estafeta parceiro (`is_partner_store`):** +50 tokens
- **Trigger:** dispara apenas em transição para `delivered` (NEW.status=delivered AND OLD.status<>delivered)
- **Expiram:** 60 dias após criação (`expires_at = now() + INTERVAL ''60 days''`)
- **Desconto cliente:** até **50% do valor do pedido**

**Conduta:**
- Mostra `tokens_balance` total + `expiring_soon_count` (próximos 7 dias).
- Se há tokens a expirar, sugere usar no próximo pedido.
- **NUNCA** prometes valor específico em € (depende da regra de conversão actual).

**[VERIFICAR]** conversão monetária "100 tokens = €0,50" — confirmar se está em código activo ou só em docs.',
'["agent_get_user_tokens_summary"]'::jsonb, true),

('REFUND_STATUS', 'refunds', 'read_only', false,
'# REFUND_STATUS

**Quando usar:** "onde está meu reembolso?", "estado refund".

**Tools:** `agent_get_refund_status(p_order_id)`

**Valores literais (business_rules.md):**
- **Cartão Stripe:** 3-5 dias úteis
- **Wallet:** imediato

**REGRA CRÍTICA #1 (§31.3):** NUNCA calculas valor de refund. Apenas reportas estado.

**Conduta:**
- Pede order_id se não fornecido.
- Chama tool, devolve `refund_status` + `eta_text`.
- Se refund_amount é placeholder (5A-1 retorna 0), diz "ainda em apuramento" e oferece humano.
- Se user exige número exacto → HUMAN_REQUEST.

**[VERIFICAR]** refund detail real (5B com tabela `refunds` dedicada ou logs Stripe).',
'["agent_get_refund_status"]'::jsonb, true),

('GENERAL_FAQ', 'faq', 'read_only', false,
'# GENERAL_FAQ

**Quando usar:** "como funciona?", "Bora opera onde?", "quanto cobram?".

**Tools:** [] (sem tools)

**Conteúdo literal:**
- **Cobertura:** cidade Guarda, Portugal (`restaurant_id` sufixo `-guarda`).
- **Diferenciador:** reserva de mesa integrada (vs Glovo/Uber Eats).
- **Tipos de serviço:** restaurant, storeShopping (mercado), carryGroceries, sendPackage.
- **Pagamento:** cartão (Stripe), MB WAY, dinheiro.
- **Tokens:** sim, dão desconto até 50%.

**REGRA CRÍTICA #2 (§31.3):** NÃO calculas dinheiro. Se user pergunta "quanto custa?" ou "qual a taxa?" → "Os custos calculam-se ao montar o carrinho. Posso ajudar com mais alguma coisa?".

**[VERIFICAR]** horário operacional (não está em business_rules.md).
**[VERIFICAR]** taxa entrega base (skill descreve, não calcula).',
'[]'::jsonb, true),

('APP_TROUBLESHOOTING', 'app', 'read_only', false,
'# APP_TROUBLESHOOTING

**Quando usar:** "GPS não funciona", "não recebo notificações", "app fechou".

**Tools:** [] (sem tools)

**Receitas (boas práticas Uber/Glovo):**
- **GPS:** Definições do telemóvel → Localização → Bora → permitir "Sempre".
- **Push:** Definições → Notificações → Bora → activar.
- **App fecha:** forçar fecho + reabrir; verificar actualização Play/App Store.
- **Login não funciona:** verifica conexão; experimenta wifi vs dados móveis.

**Conduta:**
- Diagnóstico simples primeiro; se persiste após 2 tentativas → HUMAN_REQUEST.
- Não pedes screenshots (o agente não processa imagens).

**[VERIFICAR]** versão mínima Android/iOS suportada.',
'[]'::jsonb, true),

('HUMAN_REQUEST', 'escalation', 'escalate', true,
'# HUMAN_REQUEST

**Quando usar:**
- User pede explicitamente humano ("falar com pessoa", "não me ajudaste").
- Detectas queixa séria (perda dinheiro, encomenda em falta, problema com estafeta).
- Pergunta envolve cálculo financeiro.
- 2+ tentativas falhadas em outras skills.

**Tools:** [] (sem tools)

**Acção:**
- Apresenta WhatsApp **+351937501673** + Email **boraappbora@gmail.com**.
- Marca `[HANDOFF_HUMAN]` no fim da resposta — Edge Fn detecta e cria `support_tickets` (channel=chatbot).
- Sessão fica com `escalated=true` + `ticket_id` referenciado.

**Limitação (§31.6):**
- WhatsApp tap NÃO cria ticket (anti-spam).
- Apenas chatbot e email criam tickets.

**Tom:** empático, sem julgamento.',
'[]'::jsonb, true)

ON CONFLICT (skill_name) DO UPDATE
SET playbook_md = EXCLUDED.playbook_md,
    allowed_tools = EXCLUDED.allowed_tools,
    category = EXCLUDED.category,
    mode = EXCLUDED.mode,
    requires_human_handoff = EXCLUDED.requires_human_handoff,
    active = EXCLUDED.active,
    updated_at = now(),
    version = public.support_skills.version + 1;
