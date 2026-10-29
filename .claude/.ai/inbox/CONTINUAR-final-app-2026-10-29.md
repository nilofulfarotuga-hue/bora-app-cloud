# CONTINUAR — final-app-2026-10-29

Atualizado: 29/10/2026 15:05 UTC (motor Fable 5.1; o Opus volta 1/11 18:00 Lisboa). Ler antes o ESPEC da
missão-mãe (`.claude/.ai/provas/missao-geral-2026-10-28/ESPEC.md`), o relatório de ontem
(`.claude/.ai/reports/OPUS-2026-10-28-missao-geral.md`) e o e2e_log (fluxo final-app-2026-10-29, ids 5100+).
Cópia de trabalho `C:\BoraLocal\wt-missao-geral-28-10`, ramo `missao-geral-2026-10-28`, último commit ffb5a8cc
(28 por cima de 9eed27ff). Sem push (o push do ramo foi recusado pela tranca: precisa do Danilo).

## Autorizações recebidas hoje (texto na base: cortex_red_proposals aprovada_danilo 14:22)
- 4 itens de dinheiro ("eu autorizo os 4 de dinheiro"): (1) acerto do estafeta a dinheiro — APLICADO
  (migração 20261029143048, backups bkp_fn_*_20261029, 12/12 pedidos sem saldo iguais); (2) pacote dos
  reembolsos — fica para o Claude.ai aplicar por MCP (client-cancel-order é zona vermelha no PC; LEIA-ME em
  docs/propostas/missao-geral-2026-10-28/bloco2; _shared v2 já no repo); (3) notify-tvde-driver do vale —
  conserto no repo (v24), deploy pendente; (4) platform_settings segredos (S1) — agente a preparar; aplicar
  a seguir com backup e prova.
- Adendos lidos: 1 (14:20), 2 (14:30), 3 (14:40, robô de documentos), 4 (15:00, melhor que Uber/Glovo).
  Bora Motorista passa a último; C3 e C6 saem.

## Feito e provado hoje
- 1.e auth 500 (banned_until infinity → 9999-12-31, 3 contas; 184 utilizadores listam a 200).
- 1.f repo público: NÃO fechar (iOS = ~7.800 min macOS/mês); custo no relatório.
- 1.a revisor do Bloco 1: APROVADO; consertos aplicados (commit 4b667a2f); pronto-para-publica-1 (e2e 5118).
- C1: 3 das 4 migrações aplicadas (20261029141848/141901/141912); admin_chamar_estafeta_ja → Claude.ai.
- E1 watermark 401 na VPS (consumidor-aprovadas, aprovador-vermelho): chave de servidor; 200 provado.
- driver_update_location 401 (app): consertos no commit ffb5a8cc; prova no ar só depois de publicar.
- Conta de teste demo.cliente com 10 € + 600 tokens (prop-76046159).
- Bloco 3 material da Boom (14 ficheiros no Storage; Claude.ai desenha).
- Bloco 9 Casa & Manutenção: proposta gravada (casa-manutencao-proposta).
- 6.b paridade mundo: 10 itens (paridade-mundo-2026-10-29), 5 pequenos por fazer no Bloco 7.
- Bloco 4 contabilista: BLOQUEADO (o Chrome do perfil Bora não está ligado à extensão; a Claude.ai pede o
  passo ao Danilo).

## Fechados entretanto (29/10 ~16:00)
- 1.b Boom N1-N5 nos ecrãs: commit e8d0b50a (416 testes verdes, totais = servidor).
- 5 lembretes + plano 14 dias: commit ab878ebb; 1.º envio real 14:31 (whatsapp_messages 1228); crons 09:30 + */10;
  nomes do dono fora do código (LEMBRETES_NOMES_DONO no .env da VPS).
- 8 livro comum: livro-indice vivo; https://livro.srv1786862.hstgr.cloud/LIVRO.md com senha (401/200); skills nos 2 sentidos.
- Boom-Emanuel: NIF/IBAN na base; King Elvis 16,10; textos; horário ±15; site publicado (commit 09a9927 no bora-site);
  27 preços de balcão preparados para o Claude.ai (prop-37fe46dc; docs/propostas/.../boom/PRECOS-BOOM-BALCAO-2026-10-29.md).
- C4 takeaway por telefone: página lojas-takeaway-precos (Tiago's sim, Fuku parcial, Amaya/Sakura sem dados).
- C5 Stripe Connect fase 2: só preparado (docs/propostas/.../C5_stripe_connect/01-03), à espera de autorizo.
- Dinheiro autorizado: (1) acerto do estafeta APLICADO (20261029143048); (2) reembolsos → Claude.ai (push do ramo
  recusado pela tranca); (3) TVDE vale no repo, deploy pendente; (4) S1 a preparar pelo agente de segurança.

## Fechados às 16:45 UTC (commits no ramo: ea108022, 2dc1d47f, 7c2602ff + o do notify-tvde-driver)
- S1 platform_settings segredos APLICADO (migração 20261029152540, e2e 5210): cliente comum 0 secretas,
  anon só a vista pública (87), admin vê tudo, preços iguais antes/depois (md5). A cópia para
  supabase/migrations foi recusada pela tranca (TRANCAS.md); o SQL está em docs/propostas/.../janela2/.
- TVDE vale a dinheiro: notify-tvde-driver v24 NO AR (e2e 5221). Armadilha: o repo estava atrás do ar
  (v23 nunca entrou); o repo ficou igual ao ar.
- Pacote dos reembolsos + SQL da Boom entregues ao Claude.ai em claude_ai_memoria (11 páginas
  reembolsos-b2-* e boom-precos-sql-2026-10-29, md5 provado; e2e 5222). Ele aplica por MCP.
- Robô de documentos (adendo 3) em modo sombra, com entrada no menu do painel; Receita do dia alvo
  alargado; robô WhatsApp da Boom ponta a ponta em teste (63 testes; janela demo até 30/10 15:36Z).
- Adendo 5 lido (e2e 5211): BLOCO 11 = itens 4, 5, 6, 7, 8 do plano-melhor-que-uber-glovo, só depois dos
  Blocos 1-8; desenho de cada um na página adendo-5-final-app-2026-10-29.
- Reportado pelos agentes, por fazer: estafeta demo a 23 km da Boom (oferta não chega; telemóvel em Guarda
  na segunda); takeaway_enabled da Boom = false (dono liga no painel); chave OpenCode Go expirada (401) e
  Gemini pago sem créditos (402) — precisam do Danilo; gatilho de tvde_driver_documents não feito.

## Fechados às 17:30 UTC (commits f0c7021b reels, a85b5585 tvde, 6294e7ea adendo 4 + Boom Flutter)
- Adendo 4: os 10 itens e os 5 pequenos em código, cada um com interruptor em platform_settings (ask_*, cart_*,
  feature_*; os de IA desligados até teste com sessão de parceiro/admin); 6 migrações aplicadas; 101 testes novos;
  as 3 ligações (BarraPedidoAtivoHost no main.dart, cards no painel do parceiro, nota a negrito) feitas por mim.
  Item 9 só em parte (124 de 179 tamanhos de letra < 16 px nos ecrãs antigos; contraste do branco sobre verde 3,3:1).
- Relatório semanal dos reels no livro (cron segundas 09:00 Lisboa; só gostos/comentários — faltam permissões
  instagram_manage_insights e read_insights no token). Biblioteca de Anúncios: bloqueado (sem ads_read; e2e 5224).
- Nada a correr. Só os registrants gerados (linux/macos/windows) ficam por commitar, de propósito.

## Bloco 7 feito (19:00 UTC; e2e 5249-5260; 67 capturas em .claude/.ai/provas/final-app-2026-10-29/, fora do repo)
- Delivery cliente demo e estafeta demo de ponta a ponta a dinheiro (7,17 = 7,17; ledger 3 linhas; tokens certos).
  Parceiro demo online/offline; admin sem sessão nega; Favores/Limpeza/Reservas até ao confirmar; Motorista sem regressão.
- Consertado (commit a seguir): ETA ignora posição do estafeta > 60 km; atalho "Restaurantes" das reservas abre mesas;
  "acesso negado" do painel em PT-BR.
- Só reportado (dinheiro/despacho ou sem conta): folha "Ver compras" do estafeta mostra "cliente paga na entrega" sem a
  taxa de pedido pequeno (driver_map_screen ~3730; a faixa está certa); canal driver-offer reabre de 3 em 3 s
  (driver_store _attachOfferChannel/_scheduleReconnect, hipótese); gatilho demo atribui por drivers.id (conhecido);
  legal_terms_pending ordena do mais novo para o mais velho (termos novos não cobrem os antigos); "Faltam X €" duas
  vezes no carrinho; cartão "Pausa a loja" com a loja offline; Maps/Waze abre sozinho depois de "Confirmar compra".
- Por ver (precisa de conta/chave/pessoa): oferta+aceitar pelo despacho normal; pedido novo no painel do parceiro;
  painel admin com dados (sem conta de admin em ficheiros); Favor a partir da morada (GOOGLE_MAPS_API_KEY no
  .dart_defines do emulador); Limpeza confirmada (iria a profissional real).

## Missão publica-2026-10-29 (29/10 noite; relatório `.claude/.ai/reports/FABLE-2026-10-29-publica.md`)
Feito: Bloco A (push, junção em produção ×2, web no ar; A.6 /pedir/boom; A.7 robô da Boom ao vivo; A.9 post da Boom
preparado; A.10 plano de 14 dias conferido), Bloco B inteiro (a-k; o c ficou de propósito, ver e2e 5291), Bloco C
(itens 6, 5, 4, 7 em código, interruptores desligados; migrações C6 e C7 aplicadas; C5 e C4 no repo por aplicar),
Bloco D bloqueado (sem token do CLI; passos na página `reembolsos-dashboard-passos`).

## Retoma do adendo 7 (21:30–22:15, Opus 5.5) — feito
- Android: publicação 2 = versionCode 697 (21:10), publicação 3 = 698 (21:56, faixas interna, alfa e produção).
- iPhone: autoteste no simulador OK; envio parado pela Apple "PLA Update available" (contrato por aceitar pelo
  Danilo em developer.apple.com, página aberta no Chrome Bora). Depois: rerun-failed-jobs do run 40951317148.
- Reembolsos: 7 funções publicadas pela CLI (login com o código do Danilo) e lidas de volta iguais; SQL dos tokens
  aplicado (20261029215542) e provado em rollback (pontos 2 a 6). Nada de ontem para trás (0 reembolsos pendentes,
  0 pedidos por fechar). e2e 5324, 5325.
- C4 partes 2 e 3 aplicadas (20261029214954, 20261029215028); C5 aplicada pela Claude.ai às 21:15.
- Robô da Boom: causa da mensagem das 19:41 = sessões Signal estragadas (Bad MAC) do Danilo e do Emanuel depois da
  queda das 19:36; registo de erros ligado (baileys-erros.log), sessões postas de lado em auth-bkp-20261029, ponte
  reiniciada 21:48. Falta a mensagem de teste real do Danilo. e2e 5322.
- 17 fotos da Boom no Storage (e2e 5319); página boom-robo-conhecimento corrigida; política tmp dos cartazes apagada;
  NIF opcional confirmado (e2e 5323).

## ADENDO 9 — check-in: calendário de 30 dias + escada de prémios (Danilo 29/10 22:20) — POR FAZER, sessão nova
Página do livro `adendo-9-checkin-escada-premios-2026-10-29` (ler inteira por SQL). Resumo:
1. Cartão do check-in na home: faixa de 7 dias da semana corrente da sequência (no dia 12 mostra 8-14) e seta
   "ver o mês" que expande no próprio cartão o calendário dos 30 dias (feitos, hoje, marcos 7/10/15/30 com ícone).
2. Escada de prémios (regra nova: "se escolher algum prémio volta do zero, senão vou falir"): os tokens diários
   (5,5,10,10,15,15,40) continuam a acumular; os prémios de produto/serviço (10 salgados, 15 açaí, 30
   limpeza/lavagem) passam a ser UM por sequência. No marco: festa (confetti, som curto, vibração) e duas escolhas
   "Levantar agora (a sequência volta ao dia 1)" ou "Continuar (no dia 15/30 trocas por …)"; no 30 só levanta. Vale
   pendente único, TROCADO (nunca somado) ao continuar; levantar cria o vale (validade checkin_marco_validade_dias)
   e reinicia a sequência no momento; falhar um dia guarda o patamar já garantido. Tecto mensal e pedido pago
   continuam. Quem já tem mais de um vale fica com eles (hoje 1 cliente nessa situação, SELECT 29/10 22:25).
   Interruptor novo `checkin_escada_ativa` (nasce ligado). Painel admin: sequência, marco, vale pendente,
   levantados, textos editáveis, custo por mês.
3. Provas: emulador Android (cartão fechado/aberto, festa no 10, levantar vs continuar, vale trocado no 15,
   reinício), testes das funções do servidor (máx. 1 vale pendente; levantar reinicia; falhar guarda o patamar),
   e2e_log fluxo publica-2026-10-29 passo G-checkin-escada, publicação nas 3 lojas, /ctx doctor e /ctx stats.
Onde vive hoje: lib/services/checkin_service.dart, checkin_premios_service.dart, lib/screens/client_home_screen.dart
(cartão), lib/screens/client/checkin_premios_screen.dart e checkin_premio_servico_screen.dart,
lib/screens/admin/admin_checkin_screen.dart e admin_checkin_premios_screen.dart; servidor client_daily_checkin,
_checkin_sequencia, _checkin_marcos_apos_checkin, _checkin_vale_emitir, client_checkin_premios,
client_checkin_premio_escolher; migrações supabase/migrations/20261021*_d_checkin_marcos_*.sql; testes
test/checkin_premios_test.dart e checkin_premios_ecras_test.dart. Atenção: o check-in mexe em bora_tokens
(dinheiro) — os tokens diários NÃO mudam; o iPhone continua parado no contrato da Apple por aceitar.

## Falta (por ordem)
1. Danilo: aceitar o contrato da Apple → relançar o iPhone; mandar a mensagem de teste ao robô da Boom.
   Claude.ai: copiar para `supabase/migrations/` pelo GitHub a S1 e a dos tokens (a tranca recusa no PC). A do NIF
   de 28/10 (20261028114641) não pode ir para o repo público tal como está: tem o NIF da empresa.
2. Revisor independente das propostas de despacho (`docs/propostas/missao-geral-2026-10-28/C5_agendar/01_*` e
   `C6_modo_ocupado/01_*`) e do create_order com loja fechada (`C5_agendar/04_*`); só depois `scheduled_orders_revisor_ok`
   e os interruptores.
3. Danilo: regra de dinheiro das promoções (`C4_promocoes/00_LEIA-ME.md`) → depois `C4_promocoes/01_servidor_precos_proposta.sql`.
4. Item 8, pedido em grupo: desenho na página `adendo-5-final-app-2026-10-29`; não começado.
5. Robô da Boom: baixar o timeout de 45 s do `motores.py` (VPS) para ~20 s numa janela sem conversa; a 1.ª mensagem
   do dia pode ir ao Gemini (quota 20/dia) — ver página `motores-rotacao-2026-10-29`. Hermes/OmniRoute/motor-bora
   ainda têm go/zen mortos nas cadeias (reinício pode parar o Telegram).
6. Pequenos reportados pelos agentes: `send_package_form_screen` aceita morada sem coordenadas; `GanhoDeHojeCard`
   mostra 0,00 em vez de "—" quando o papel falha; serviços (booking_flow) ainda dizem "pedidos" numa loja Em breve;
   `store_products_screen`/pesquisa global/carrinho não mostram o preço promocional (o servidor cobra o certo).
7. Prova no emulador do canal de ofertas (deve aparecer "ignorado (fecho pedido por mim)", nenhum reconnect de 3 em 3 s).
