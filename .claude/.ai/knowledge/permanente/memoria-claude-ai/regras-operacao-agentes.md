---
id: memoria-claude-ai-regras-operacao-agentes
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-16
zona: verde
confianca: alta
estado: atual
---

# O que podes e o que não podes fazer no Bora em produção (ChatGPT, OpenCode, Hermes, Claude Code)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `regras-operacao-agentes`, origem `claude-ai`, atualizada em 2026-09-16T17:25:05.557746+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: regras operacao agentes · memoria claude.ai · claude_ai_memoria

Porque existe: a 16/09 o ChatGPT pôs um pedido da Goola Açaí no nome do estafeta Ney com um UPDATE direto na tabela orders. O Ney usa a Bora pelo navegador do iPhone, estava desligado e sem notificações, e como o pedido já tinha estafeta o sistema deixou de chamar os outros: o pedido ficou preso 10 minutos depois de pronto, com a cliente à espera, até a Claude.ai o passar ao Danilo. Estas regras existem para isso nunca mais acontecer. Valem para qualquer agente que mexa no Bora em produção.

PODES, sem pedir:
1. Ler tudo (SELECT) para investigar e responder ao Danilo.
2. Atribuir ou passar um pedido de entrega a um estafeta SÓ assim: select public.ops_reassign_order('<id do pedido>', '<user_id do estafeta>', '<motivo>', '<o teu nome: chatgpt, opencode, hermes ou claude-code>'); Esta função confirma que o estafeta está ligado, com sinal nos últimos 90 segundos e com notificações, e que o pedido já está pronto; depois passa o pedido, avisa o estafeta e deixa registo em admin_audit_log. Se devolver ok=false, NÃO tentes outro caminho: diz ao Danilo o motivo em palavras simples (exemplo: "o Ney está desligado, não vai receber o pedido"). Só repetes com p_forcar => true se o Danilo mandar expressamente depois de saber o motivo.
3. Para escolher estafeta, vê quem está mesmo disponível: select user_id, name, phone, last_heartbeat_at, lat, lng from drivers where is_online and last_heartbeat_at > now() - interval '90 seconds' and approval_status = 'approved' and coalesce(is_banned, false) = false; e prefere quem está mais perto da loja.
4. Registar no Córtex o que fizeste (cortex_reportar: o quê, porquê, resultado).

NÃO PODES, nunca:
1. Fazer UPDATE, INSERT ou DELETE direto em orders, tvde_rides, appointments, drivers, client_wallets, wallets, ledger_entries, bora_tokens, driver_balances, payouts ou platform_settings de preços, comissões e taxas. Usa as funções próprias (admin_* e ops_*) ou pede à Claude.ai.
2. Mexer em dinheiro real (reembolso, crédito, cobrança, Stripe) sem o "vai" do Danilo.
3. Aplicar migrações ou fazer deploy nas zonas protegidas (dispatch_engine, pricing, finalizePurchase, bora_tokens, stripe-webhook, RLS de orders/wallets/ledger): propõe com cortex_propor. Qualquer outra migração aplicada em produção tem de ficar também no repo bora-app-cloud (supabase/migrations).
4. Atribuir pedido a quem não vai receber (desligado, sem sinal, sem notificações, ou só no navegador com a página fechada) sem o Danilo saber.
5. Apagar dados. Correção de dados só com backup antes (bkp_<nome>_AAAAMMDD, com RLS ligada).
6. Dizer "feito" sem prova (SELECT, registo ou ficheiro).

DEPOIS de agir: confirma por SELECT que ficou como querias (status do pedido, assigned_driver_id, estafeta online) e diz ao Danilo o estado real numa frase curta, sem jargão.

Caminho do Danilo: no painel admin, o botão de escolher estafeta (quando estiver pronto). O teu caminho: a função ops_reassign_order.
