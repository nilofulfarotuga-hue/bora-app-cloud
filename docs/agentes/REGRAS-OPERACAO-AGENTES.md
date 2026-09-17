## REGRAS DE OPERAÇÃO EM PRODUÇÃO — para qualquer agente (ChatGPT, OpenCode, Hermes/Emerson, Claude Code, Claude.ai) · 16/09/2026

> Fonte viva: página `regras-operacao-agentes` em `public.claude_ai_memoria` (espelho no Córtex:
> `memoria-claude-ai-regras-operacao-agentes`). Antes de mexer em pedidos, estafetas, dinheiro ou
> migrações em produção, lê-a e segue-a à letra. Esta cópia existe para nenhum agente arrancar cego.

**Porque existe:** a 16/09 o ChatGPT pôs um pedido da Goola Açaí no nome do estafeta Ney com um
UPDATE direto na tabela `orders`. O Ney usa a Bora pelo navegador do iPhone, estava desligado e sem
notificações; como o pedido já tinha estafeta, o sistema deixou de chamar os outros e o pedido ficou
preso 10 minutos depois de pronto, com a cliente à espera, até a Claude.ai o passar ao Danilo.

### PODES, sem pedir

1. Ler tudo (SELECT) para investigar e responder ao Danilo.
2. Passar ou reservar um pedido a um estafeta **só assim**:
   `select public.ops_reassign_order('<id do pedido>', '<user_id do estafeta>', '<motivo>', '<chatgpt|opencode|hermes|claude-code>');`
   A função confirma que o estafeta está ligado, com sinal nos últimos 90 s e com notificações; se o
   pedido ainda não estiver pronto fica **reservado** e vira oferta normal quando a loja o marcar pronto
   (se ele não aceitar ou estiver desligado, o pedido segue para todos). Se devolver `ok=false`, **não
   tentes outro caminho**: diz ao Danilo o motivo em palavras simples. Só repetes com `p_forcar => true`
   se o Danilo mandar expressamente depois de saber o motivo.
3. Devolver um pedido a todos (tirar o estafeta ou a reserva):
   `select public.ops_release_order_driver('<id do pedido>', '<motivo>', '<agente>');`
4. Ver quem está mesmo disponível:
   `select user_id, name, phone, last_heartbeat_at, last_platform from drivers where is_online and last_heartbeat_at > now() - interval '90 seconds' and approval_status = 'approved' and coalesce(is_banned, false) = false;`
   e preferir quem está mais perto da loja.
5. Registar no Córtex o que fizeste (`cortex_reportar`: o quê, porquê, resultado).

### NÃO PODES, nunca

1. Fazer UPDATE, INSERT ou DELETE direto em `orders`, `tvde_rides`, `appointments`, `drivers`,
   `client_wallets`, `wallets`, `ledger_entries`, `bora_tokens`, `driver_balances`, `payouts` ou
   `platform_settings` de preços, comissões e taxas. Usa as funções próprias (`admin_*` e `ops_*`) ou
   pede à Claude.ai. **Toda mudança de `assigned_driver_id`/`driver_id` feita por ligação SQL direta
   fica registada em `order_driver_assignment_audit` e avisa o Danilo (Telegram + push); com a
   barreira ligada (`platform_settings.orders_driver_direct_update_block`) é recusada com
   "Usa public.ops_reassign_order".**
2. Mexer em dinheiro real (reembolso, crédito, cobrança, Stripe) sem o "vai" do Danilo.
3. Aplicar migrações ou fazer deploy nas zonas protegidas (`dispatch_engine`, `pricing`,
   `finalizePurchase`, `bora_tokens`, `stripe-webhook`, RLS de `orders`/`wallets`/`ledger`): propõe com
   `cortex_propor`. Qualquer outra migração aplicada em produção tem de ficar também no repo
   `bora-app-cloud` (`supabase/migrations`).
4. Atribuir um pedido a quem não vai receber (desligado, sem sinal, sem notificações, ou só no
   navegador com a página fechada) sem o Danilo saber.
5. Apagar dados. Correção de dados só com backup antes (`bkp_<nome>_AAAAMMDD`, com RLS ligada).
6. Dizer "feito" sem prova (SELECT, registo ou ficheiro).

### Identidade do estafeta (corrigida 3 vezes: Valdemir 16/08, Ney 16/09)

`user_id` manda em tudo o que a app vê e aceita (`assigned_driver_id`, `current_driver_offer_id`,
`driver_id`, créditos, tokens, saldo). `drivers.id` só para `tried_driver_ids` e matching interno.
No Flutter: `drivers.update(...).eq('user_id', uid)` e upsert com `onConflict: 'user_id'`; nunca
`.eq('id', <auth uid>)` em tabelas de papéis (verificador: `.claude/skills/identidade-estafeta`).

**DEPOIS de agir:** confirma por SELECT que ficou como querias (status do pedido, `assigned_driver_id`,
estafeta ligado) e diz ao Danilo o estado real numa frase curta, sem jargão.

Caminho do Danilo: no painel admin, "Pedidos parados" e o botão "Escolher estafeta" (com aviso vermelho
quando o estafeta não vai receber) e "Mandar para todos". O teu caminho: `ops_reassign_order` /
`ops_release_order_driver`.
