# Relatório — agente ADMIN-GERAL (ronda de correção 04/10/2026, relançada)

Ramo: `agente-admin-geral` @ b21f9a51 (commitado; nada empurrado para ramos de publicação).
CI: `analise-admin-geral` = b21f9a51 + os 2 commits só-CI do workflow estrito → run **37234232305 VERDE**
(analyze sem erros, 7 avisos = igual à base; **955 testes, todos a passar**).

## FEITO

### 1. Notificações em massa (achado 06-admin #4)
- Migration **20261004151605** `admin_broadcasts_fila_e_confirmacao` (aplicada na 1.ª ronda; confirmada no ar e
  agora gravada em `supabase/migrations/`). Cron `execute-broadcast-queue` (jobid 97, minutos ímpares) ativo;
  as 3 linhas presas em "sending" desde 21/05 estão `failed` com nota (cópia `bkp_push_broadcasts_20261004`).
- Edge **execute-broadcast v8** (no ar, verify_jwt=false como antes) gravada em `supabase/functions/execute-broadcast/index.ts`.
- `admin_send_notification_screen.dart`: antes de enviar (Imediato ou Agendar) abre "Confirmar envio em massa"
  com o nº de pessoas e aparelhos (`admin_broadcast_preview`); trava de toque duplo; acorda a fila logo;
  deixou de chamar `admin_save_broadcast_in_app` (duplicava o sininho); hora de Lisboa; segmento "Clientes + parceiros".
- `admin_broadcasts_history_screen.dart`: usa `admin_list_broadcasts_v2` (com a nota do porquê), botão cancelar
  agendado (com confirmação, `admin_cancel_broadcast`), hora de Lisboa.
- PROVA: `admin_broadcast_preview('all_clients')` → 131 pessoas / 192 aparelhos.

### 2. Rotas dos avisos (06-admin #5)
`lib/main.dart` (só rotas): `/admin/appointments`, `/admin/receipts`, `/admin/support-escalations` (ecrã novo),
`/admin/carwash`, `/admin/encomendas-telefone`; mais `/admin/bloqueios`, `/admin/tvde/chats`, `/admin/reativacao`.
`/admin/acertos-semana` já existia. Contagem real em `admin_notifications`: appointments 10, support-escalations 2,
receipts 2, carwash 1. Teste novo `test/admin_geral_ronda_0410_test.dart` tranca as rotas.

### 3. Ecrãs novos / menu (06-admin #6 e #11)
Migrations **20261004205144** `admin_geral_ecras_auditoria_reativacao` e **20261004205343** `admin_geral_suporte_e_opcoes` (aplicadas).
- **Utilizadores bloqueados** (`admin_bloqueios_screen.dart`): `admin_blocked_users_list` (quem bloqueou quem, nomes,
  motivo); desbloquear com confirmação + `log_admin_action`. Política nova `blocked_users_admin_tudo`. (0 bloqueios hoje.)
- **Chat das corridas TVDE** (`admin_tvde_chats_screen.dart`): `admin_tvde_chats_list` + `admin_tvde_chat_mensagens`.
- **Suporte — falar com o Danilo** (`admin_support_escalations_screen.dart`): lista, conversa do assistente e
  "Responder" → `admin_support_escalation_responder` (resposta entra na conversa do suporte + sininho + auditoria).
- **Pedidos de acesso TVDE** e **Reclamações** (estava arquivada) entram no menu; **Mesas** (`admin_mesas_screen.dart`,
  política `tables_admin_tudo`), **Folgas da equipa** (`admin_folgas_screen.dart`, staff_availability_exceptions),
  **Opções de produto** (`admin_opcoes_produto_screen.dart`, `admin_opcoes_loja` + `admin_opcao_item_atualizar` auditado;
  políticas `option_groups_admin_tudo`/`option_items_admin_tudo`). Variantes (`product_variants`) têm 0 linhas → sem ecrã.
- **Encomendas de festa**: filtro "Festas (com data)" + escolher dia (dia de Lisboa) em `admin_orders_screen.dart`.
- PROVAS (DO+RAISE, desfeitas): chats=3 (1.º com 2 msgs); bloqueios=0; escalamento de teste → lista/pendente, conversa 4,
  responder ok → `answered`, 1 sininho, 1 mensagem no chat; opções: 6 grupos, item desligado ok, acréscimo 999 € recusado;
  2 linhas de auditoria; não-admin → `admin_required`.

### 4. Ações perigosas e auditoria (06-admin #10)
- Confirmação: pôr loja Offline (`admin_partner_detail_screen.dart` `_setAdminIsOnline`), desativar loja
  (`admin_partners_screen.dart` `_toggleActive`), forçar reserva (`admin_reservations_screen.dart`).
- Gatilho novo `trg_restaurants_auditoria_admin` (função `fn_restaurants_auditoria_admin`): quando um ADMIN muda
  comissão (`partner_commission_billing`), `app_markup_pct`, `is_partner`, `business_hours`, `is_online`,
  `is_active_admin`, pedido mínimo/taxa → linha `parceiro_editado` em `admin_audit_log` com antes/depois. Não muda valores;
  nunca bloqueia a edição. PROVA: update como admin → 1 linha de auditoria.

### 5. Hora de Lisboa (06-admin #9)
- `lib/utils/hora_lisboa_ext.dart` (novo): `toLisboa()` e `inicioDoDiaLisboaUtc()`.
- 37 ecrãs não-dinheiro passaram de `toLocal()` a `toLisboa()` (tickets, chats, WhatsApp, reservas, barbearias,
  TVDE, robôs, etc.; ficaram de fora 3 sítios que alimentam seletores de data). Datas cruas em UTC corrigidas em
  chat viewer, WhatsApp, suporte, motores, gorjetas, detalhe do entregador e do parceiro; métricas das barbearias
  "hoje" à meia-noite de Lisboa; detalhe do pedido em Lisboa.
- SQL: `admin_dashboard_metrics.orders_today`, `admin_get_reservations_stats`, `admin_list_waitlist_today` cortados
  ao dia de Lisboa (o dashboard atual já usa `admin_dashboard_metrics_v2`, que já estava em Lisboa).

### 6. CSV a sério (06-admin #12)
- Widget novo `lib/widgets/admin/admin_csv_button.dart` (AdminExportService, datas em Lisboa).
- Botões que só copiavam passam a descarregar: Caça-clientes, Lavagens, WhatsApp (contatos e conversa).
- CSV novo em: Tickets, Reservas, Agenda de marcações, Pedidos de acesso TVDE, Entregadores, Histórico de ações,
  Reclamações, Bloqueios, Chat TVDE, Suporte, Reativação.

### 7. Clientes parados — reativação (09-concorrencia #2)
- Settings (categoria marketing): `reativacao_ligada=false`, `reativacao_dias=14`, `reativacao_intervalo_dias=30`,
  `reativacao_titulo`, `reativacao_texto` (PT-PT), `reativacao_so_opt_in=true`.
- Tabela `reativacao_envios` (RLS ligada, sem acesso direto); `_reativacao_candidatos()`; `reativacao_processar()`
  (marca quem voltou até 14 dias; se ligado manda UM push via Edge `push-clientes-alvo` + sininho, máx. 500/dia);
  cron `reativacao-clientes-parados` jobid 102, 17:07 UTC (~18h Lisboa).
- Ecrã `admin_reativacao_screen.dart`: ligar/desligar (confirmação com nº de pessoas), dias, título, texto,
  só-opt-in, números (parados agora, enviados, voltaram) e últimos envios. `admin_reativacao_resumo`/`_configurar` (auditado).
- PROVA (desfeita): com opt-in → 0 candidatos; sem opt-in → 4; processar → 4 enviados (pedido pg_net 4249, não saiu
  por ter sido desfeito); 2.ª vez no mesmo dia → 0 (regra 1 a cada 30 dias). Depois: 0 envios, ligada=false.

### Pedidos de outros agentes
- despacho: os 4 settings `dispatch_*` já aparecem e são editáveis em Configurações (categoria dispatch, prefixo editável);
  `orders.accepted_at` no detalhe do pedido ("Aceite pela loja", Lisboa).
- app-estafeta: detalhe do pedido mostra `deixar_a_porta`, `foto_entrega_url` (imagem do bucket privado) e
  `foto_entrega_em`, e "Foto da entrega: Em falta" quando era obrigatória; `foto_entrega_obrigatoria` editável.
- cliente-app: `admin_complaints_screen.dart` mostra corpo completo, foto (linha "Foto: <url>"), filtro por
  categoria (incl. `order_issue`), abrir o pedido, hora de Lisboa e CSV.

## NÃO FEITO
- Confirmação ao "apagar rascunho de pagamento": é `admin_orphan_payments_screen.dart`, propriedade do admin-dinheiro → PEDIDO abaixo.
- Ecrã de `product_variants`: tabela vazia (0 linhas) — não fiz ecrã.
- Reativação nasce DESLIGADA e com "só quem aceitou promoções" (regra D3 de 23/09). Hoje isso dá 0 pessoas;
  sem o opt-in daria 4. Decisão do Danilo no ecrã.
- CSV não foi posto em todas as ~90 listas sem exportar; só nas principais acima.

## PRECISA DE CONFIRMAÇÃO
- Nada com DROP/DELETE em SQL. (Desbloquear utilizador e tirar folga apagam a linha pelo próprio painel, via
  política de admin e PostgREST, com registo em `admin_audit_log`.)

## PEDIDOS A OUTROS AGENTES
- PEDIDO A admin-dinheiro: `lib/screens/admin/admin_orphan_payments_screen.dart` `_deleteDraft` (l.46) — mostrar
  `showDialog` "Apagar este rascunho de pagamento? Não se desfaz." antes do `.delete()`, e registar com `log_admin_action`.
- PEDIDO A parceiro: há um gatilho NOVO meu em `restaurants` (`trg_restaurants_auditoria_admin`, AFTER UPDATE, só
  regista quando quem edita é admin). Se criarem `pausa_ate`, acrescentem-na à lista de colunas auditadas em
  `fn_restaurants_auditoria_admin`.
- PEDIDO A segurança: `log_admin_action(text,text,uuid,jsonb)` deixa qualquer utilizador autenticado escrever em
  `admin_audit_log` (não verifica admin) — fechar com `is_admin()` (os meus ecrãs só a chamam como admin).

## RISCOS
- `admin_partner_detail_screen.dart`, `admin_order_detail_screen.dart`, `admin_menu_registry.dart` e `main.dart` são
  partilhados: mexi só nas linhas acima (rotas, linhas de info, confirmações, entradas não-dinheiro do menu).
- `toLisboa()` devolve o relógio de parede de Lisboa — usado só para mostrar; os 3 sítios que alimentam seletores
  de data ficaram com `toLocal()`.
- `admin_gorjetas_screen.dart` (gorjetas): mudei só a data mostrada para Lisboa.
