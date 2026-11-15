# Missão 9 painel-admin-15-11: auditoria do painel admin (S1 a S6)

15/11/2026, Claude Code no PC. Ordem do Danilo de 12:55, transmitida pela Claude.ai às 12:58 (caixa 56).
Seis ajudantes de contexto limpo, só leitura: leram o código do ramo `ai/2026-11-15-app` e conferiram cada
chamada no servidor só com SELECT (funções e parâmetros em `pg_proc`, colunas, regras de acesso em
`pg_policies`, registos da API). Depois eu confirmei por SELECT os achados maiores. Este documento é a lista
que o Juiz confere e o Refinador usa. Linhas de código aproximadas (estado do ramo às 13:00).

Legenda: **ERRO** = dá erro; **NADA** = carrega mas não faz nada ou mostra vazio; **CONFUSO** = funciona mas
engana; **CÓDIGO** = conserto no ramo; **SERVIDOR** = proposta (a Claude.ai aplica); **DINHEIRO** = só relatório.

## O que confirmei eu por SELECT (prova)

1. A tabela `orders` não tem nenhuma regra de leitura para o admin: só `orders_select_client`,
   `orders_select_driver` e `orders_select_partner`. Nenhuma migração criou ou apagou uma regra de admin em
   `orders`. Onze sítios do painel leem `orders` diretamente: o admin vê só os pedidos da própria conta.
   O mesmo em `driver_balances` e `driver_transactions` (só "o próprio") e em `support_tickets`. As outras
   tabelas do painel têm regra de admin (266 regras usam `is_admin()`). → SERVIDOR P1.
2. 17 dos 22 estafetas têm `drivers.id` diferente do `user_id`, e nenhum desses 17 ids é uma conta. Os
   pedidos, saldos e transações estão pelo `user_id`.
3. O mapa ao vivo mostra 3: a lógica de `admin_live_drivers` devolve 3 linhas, há 2 estafetas ligados
   (`drivers.is_online`), e a proposta P2 devolve 2.
4. `admin_update_driver` tem 2 versões no servidor (8 e 10 parâmetros).
5. `admin_audit_log` só tem regra de leitura: inserir diretamente é recusado.
6. Central do robô: existem `admin_suporte_sessoes(p_limite, p_so_nao_lidas)` e
   `admin_suporte_conversa(p_session_id)`; faltam as outras 5 funções e `admin_bulk_approve_skill_suggestions`.
7. FALSO ALARME rejeitado (S6): "qualquer conta pode escrever na auditoria pelo `log_admin_action`". As duas
   versões começam por `_audit_chamada_direta_nao_admin()`, que ignora a chamada direta de quem não é admin.

## S1. Operação do dia, Pedidos ao vivo, mapa

- **Mapa ao vivo, ERRO "3"**: um dos 2 estafetas ligados tem duas linhas de posição (uma com `drivers.id`,
  outra com o `user_id`); `admin_live_drivers` não tira repetidos (`admin_live_orders_map_screen.dart:236`).
  O cartão AGORA conta `drivers.is_online` e diz 2. Causa de fundo: o gatilho
  `trg_sync_drivers_to_driver_locations` grava por `drivers.id` e a app pelo `user_id` (11 linhas repetidas,
  2 órfãs). SERVIDOR P2 (função sem repetidos) e CÓDIGO (juntar repetidos e contar só quem tem GPS de 5 min).
  O gatilho é entrada do despacho: só com ordem do Danilo.
- **Mapa, ERRO**: `admin_live_orders` não inclui `readyForPickup` (pedido pronto na loja desaparece);
  "Ativos" conta tudo o que não é pendente (:228-235). SERVIDOR P2 + CÓDIGO. CONFUSO: sem legenda; cor do
  comentário errada (:22 vs :138); erro cru (:303).
- **Pedidos, NADA (P1)**: lê `orders` diretamente (:107-115): 10 de 108. O detalhe diz "Pedido não
  encontrado" para pedidos de outros (`admin_order_detail_screen.dart:69/:153`). SERVIDOR P1.
- **Encomendas por telefone**: OK; erros crus (:60, :86, :131, :205). CÓDIGO.
- **Cancelamentos, CONFUSO**: `admin_list_cancellations` só lê `cancellation_requests`: mostra 2 dos 58
  cancelados. CÓDIGO (frase) + SERVIDOR (ler `orders` cancelados).
- **Stripe — duas contas, ERRO**: "Eventos do webhook" lê `stripe_webhook_events` sem permissão; a mensagem
  diz que falta uma coluna (falso). CÓDIGO (mensagem certa) + SERVIDOR (função de leitura; área Stripe:
  pede "autorizo").
- **Filas dos entregadores, ERRO**: `admin_filas_estafetas` e `admin_rascunho_compra` não existem até se
  aplicar a migração `20261114190000` (caixas 39-45). O ecrã já avisa.
- OK: Pedidos parados (180 s = "3 min"), Pendências, Saúde da web, Saúde das chaves, Edições de pedidos,
  Ajustes de peso, Diferenças de favor, Pedidos de cancelamento, Ofertas e chamadas, Avisos que falharam,
  Erros da app, Pagamentos presos, Lembretes, Farmácias (mas CONFUSO: não são "operação do dia").
- Transversal: dois porteiros (`_admin_op_guard` só aceita o papel no token; `is_admin()` aceita também os
  emails do dono) → SERVIDOR P3. 15 ecrãs mostram erro técnico cru → CÓDIGO (`humanizeAdminRpcError`).

## S2. Dinheiro e acertos (82 chamadas conferidas, 80 OK)

- **ERRO** Fecho do mês, "Exportar DAC7": manda `p_ano`, a função é `admin_dac7_report(p_year)`
  (`admin_fecho_mensal_screen.dart:378`). CÓDIGO.
- **ERRO parcial** hub, "Reabrir" de estafeta: depois chama `compute_driver_settlement`, que em produção só
  postgres e service_role podem correr (o repo dá a authenticated). DINHEIRO (pede "autorizo").
- **NADA** Tokens: pede colunas `is_active` e `reason` que não existem (`admin_tokens_screen.dart:40`) e a
  regra de `bora_tokens` só mostra os do próprio. CÓDIGO (colunas) + SERVIDOR (leitura de admin; zona
  protegida bora_tokens).
- **NADA** Reembolsos estafetas: filtro e nome/MB Way leem `orders` (`admin_receipts_screen.dart:290/:497`).
  SERVIDOR P1.
- **NADA** Pagamentos órfãos, "Excluir rascunho": sem permissão de apagar. CÓDIGO (desativar com
  explicação) + SERVIDOR.
- **NADA** "Saques dos estafetas" e "Reservas de mesa": leem tabelas sem regra de admin. SERVIDOR P1.
- **CONFUSO** "Avisos do fecho": não filtra pela semana nem arquiva; "Pagar" só copia o número; "Reenviar
  recibos" manda a TODOS sem confirmar. CÓDIGO (textos e confirmação).
- **Os 4 pedidos com margem negativa** (o robô do talão leu bem os 4):
  - 2373a05b Continente 14/11: cliente 16,22 €, talão 13,09 €, estafeta 5,41 €, resultado -2,28 €. Catálogo
    desatualizado (vodka 10,95 € no catálogo, 12,99 € na loja); o robô corrigiu o preço 4 s depois, tarde
    para este pedido.
  - 48669acf Continente 31/10: -2,64 €. Melancia ao peso, depósito das garrafas (0,60 €) não cobrado, iogurte
    1,59 € vs 1,79 €. O robô aplicou 9,06 € à melancia certa e também, por engano, a outra melancia que não
    estava no pedido.
  - 56fa8623 Burger King 08/11: -0,56 €. Entrega grátis (limite 30 €) e extra bacon 0,91 € no catálogo vs
    2,50 € na loja; duas propostas do robô pendentes desde 09/11 (uma baixaria o preço do menu).
  - 3a1bbaa2 McDonald's 05/11 (dinheiro): -0,07 €. O catálogo estava acima do talão; a causa é a entrega
    grátis (limite 20 €) com um estafeta de 10 km. A proposta pendente do robô (baixar o cheeseburger)
    piorava a margem.
  - Fila "Preços por talão": 17 propostas pendentes (a mais antiga de 25/08); 960 aplicadas sozinhas.
- **"MB Way da Bora: <número>"**: vem da chave `bora_mbway_phone` (platform_settings). Aparece no painel, na
  app do parceiro ("Pague por MB Way para…", via `bora_mbway_para_cobranca()`, que qualquer sessão pode
  ler), nos emails do fecho semanal e nos comprovativos e lembretes. Não paga estafetas: é para onde quem
  deve paga à Bora. O mesmo número estava escrito à mão como exemplo na caixa de texto
  (`admin_acertos_semana_screen.dart:396`): CÓDIGO tira-o. Mudar o número é decisão do Danilo (lápis no hub).
- DECISÃO DO DANILO (só descrevo): número MB Way das dívidas; entrega grátis por limite e cestos pequenos
  de não-parceiros com margem ≤ 0 quando o estafeta custa 5,2-5,8 €; as 17 propostas de preço; depósito
  das garrafas e melancia ao peso; cobrar a diferença do talão ao cliente ou a Bora absorver.

## S3. Entregas

- **Ficha do entregador** (`admin_driver_detail_screen.dart`): saldo e aba Transações a zero (regra só do
  próprio + filtro por `drivers.id`, :129-133, :1903-1908); aba Pedidos 15 de 132 (sem regra de admin +
  filtro por `drivers.id`, :1754-1786); **Editar dados ERRO** (função ambígua, 8 ou 10 parâmetros;
  `vehicle_color` e `vehicle_make_model` nem carregam); **Forçar logout** não derruba a sessão (a Edge chama
  `auth.admin.signOut` com o id em vez do token) e um 403/404 aparece como "Falha de rede"; **link de
  redefinição** manda `drivers.id` (falha em 17 de 22); **Remover**: as 3 travas procuram só por
  `drivers.id` (deixa remover com pedido em curso ou dinheiro pendente). CÓDIGO (H1) + SERVIDOR.
- OK: Entregadores, Aprovações, Comércios da Guarda, Catálogo de favores, Configurações de despacho,
  Estafetas — fila e documentos, Escolher estafeta.
- CONFUSO: Reimportar (desfaz correções à mão); Preços Continente PVPR (lote de junho já aplicado; "Aplicar"
  escreveria preços de junho por cima dos de hoje — zona de preços, só aviso); despacho promete
  "distâncias" que não existem. CÓDIGO (textos).

## S4. Serviços, Limpeza/Lavagem/Casa, Reservas (93 funções conferidas)

- **ERRO** "Apagar prestador": 2 de 4 prestadores têm linha em `assistant_tenants` (chave estrangeira sem
  cascata) → erro técnico (`admin_service_provider_detail_screen.dart:2184`). CÓDIGO.
- **ERRO** "Forçar criar reserva": sem "Client User ID" não manda `p_client_user_id` → função não encontrada
  (`admin_reservations_screen.dart:238`). CÓDIGO.
- **NADA** Agenda, "Histórico": `appointment_reschedules` sem regra de admin. SERVIDOR P1.
- CONFUSO: IDs escritos à mão (reservas, agenda), mesas repetidas sem explicação, ~16 erros crus na Lavagem,
  ligar prestador sem documentos mostra erro cru. CÓDIGO.
- OK: Limpezas, Profissionais de limpeza, Lavagem (15 funções), Casa (27 funções), Métricas, Folgas,
  Marcações presas, Config.
- DINHEIRO/SEGURANÇA: `compute_provider_weekly_payout` não confere quem chama (qualquer sessão pode
  recalcular e gravar em `appointment_payouts`). Proposta de guarda "dono ou admin", só com "autorizo".

## S5. Arquivo Bora Motorista, marcações, gestão e pesquisa, sino

- Arquivo Bora Motorista (91 chamadas OK): **ERRO** Reservas › Histórico pede `created_at`, a coluna é `at`
  (`admin_tvde_reservas_screen.dart:90-93/:199`); **ERRO** Dívidas em dinheiro procura nomes por
  `drivers.id` (4 sem nome, :58-62); CONFUSO: diz "só consulta" mas os botões de agir funcionam. CÓDIGO.
- Marcações: OK; chips de pagamento em inglês. CÓDIGO.
- Pesquisa: não ignora acentos ("farmacias" não acha Farmácias); a lupa de pessoas procura estafetas só
  entre os ligados (2 de 22) e os pedidos nunca aparecem (regra de `orders`). CÓDIGO + SERVIDOR P1.
- **Sino "9+"**: conta até 100 linhas; há 1789 avisos por ler (948 do robô "(0 registos)", 250 do Bora
  Motorista fechado, 1462 com mais de 7 dias); 3 links sem rota; 38 tipos sem nome em português; arquivar só
  a arrastar. CÓDIGO (contagem exata só do que pede ação, rotas, nomes, botão). SERVIDOR: o robô
  `robot_auto_execute` só avisar quando mexeu em algo; arquivar os avisos vazios é um UPDATE em produção.
- POR CONFIRMAR (segurança, para a Claude.ai): 38 avisos críticos "chave roubada em uso", o último a 14/11
  12:08, a partir de uma ligação NOS; podem ser os robôs do próprio PC.
- Pelo caminho: um robô com a chave de serviço fez ~174 pedidos em 24 h a `/rest/v1/orders` com o "+" da
  data sem codificar; todos deram erro 400, calado.

## S6. Farmácias e robôs

- Farmácias (3 abas, 11 funções, 2 Edge): OK.
- **Central do robô do suporte, ERRO**: chama 5 funções que não existem; a conversa existe com outro nome de
  parâmetro. CÓDIGO (usar as que existem) + SERVIDOR (as 5 funções). A proposta de 05/11 não se aplica como
  está (recria `admin_suporte_conversa` com outro parâmetro).
- **Sugestões Skills IA, ERRO** no aprovar em massa: a migração `20260518210000` nunca foi aplicada
  (proposta já na caixa 50).
- **Assistentes, ERRO calado**: insere a auditoria diretamente (recusado). CÓDIGO.
- **Suporte — Tickets, NADA**: regra só do próprio (proposta já na caixa 55).
- CONFUSO: WhatsApp da loja não diz desde quando nem porquê está desligado; Lembretes promete envio diário
  parado desde 06/11; modelos de IA com nomes técnicos; ~40 erros crus. CÓDIGO.
- Farmácia (app do parceiro): `farmacia_prescricao_fechar_demo` não existe; o botão "Marcar como levantado"
  mostra a mensagem amigável de "não instalado" até se aplicar a proposta
  `docs/propostas/app-15-11/farmacias_servidor.PROPOSTA.sql` (parte B, já escrita nesta sessão).

## Área do estafeta e Área do parceiro (pedido do Danilo)

Feitas como ecrãs novos que usam só funções que já existem e auditam cada ação (H2 e H8). O que precisa de
função nova no servidor fica com o botão desligado e a frase "Precisa de uma função nova no servidor
(proposta enviada)": ligar/desligar por ele, avançar o estado do pedido, enviar documento por ele, fatura do
mês, sessão a sério no "Sair"; e do lado do parceiro aceitar, recusar, marcar pronto e o take-away por ele.
