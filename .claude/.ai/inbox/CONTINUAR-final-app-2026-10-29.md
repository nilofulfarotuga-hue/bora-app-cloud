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

## Falta (por ordem)
1. Consertos pequenos da auditoria que ficaram só reportados (acima), fora de dinheiro/despacho.
2. Bloco 11 (adendo 5, só depois dos Blocos 1-8): itens 4, 5, 6, 7, 8 da página plano-melhor-que-uber-glovo,
   desenho em adendo-5-final-app-2026-10-29; 5 e 6 mexem no despacho (revisor independente + interruptor
   desligado); 7 pelo caminho de reembolso do Bloco 2; 4 confirma no relatório "comissão sobre o preço
   promocional"; 8 por último.
3. Bloco 10: Juiz (anti_trapaca, analyze, bateria), fiscal de segurança, relatório
   `.claude/.ai/reports/FABLE-2026-10-29-final-app.md` + cópia em Desktop\Bora\prompts, digest
   `digest-2026-10-29-final-app`, Telegram, e2e `fecho`, /ctx doctor + /ctx stats.
