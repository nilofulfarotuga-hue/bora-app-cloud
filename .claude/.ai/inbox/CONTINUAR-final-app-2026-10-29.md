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

## A correr (agentes; se esta sessão cair, ver o que ficou em disco/e2e_log e relançar NOVOS com a lista)
1.b Boom N1-N5 nos ecrãs · 2 robô WhatsApp da Boom · 5 lembretes + plano 14 dias · 8 livro comum ·
6.c auditoria + S1 · Boom-Emanuel pontos 2-7 · adendo 3 robô de documentos (R1-R10; R1/R2 já aplicados:
20261029144139, 20261029144631, 20261029144737).

## Falta (por ordem)
1. Rever/commitar por caminho o que os agentes deixarem; aplicar S1 (dinheiro autorizado) com backup e prova.
2. Bloco 7 (depois do delivery): ADENDO 4 (10 itens, interruptor no admin); 5 pequenos da paridade; C2 Receita
   do dia; C4 takeaway por telefone (só registar); C5 Stripe Connect (só preparar + roll secret); adendo 1 E
   (vigia de queda de pedidos/erros no Hermes; relatório semanal dos reels; biblioteca de anúncios).
   Auditoria total por prioridade (cliente delivery → estafeta → parceiro → painel → Favores → Limpeza →
   Reservas → Bora Motorista só regressões), com Maestro no emulador (RAM ≥ 3 GB).
3. Bloco 10: Juiz (anti_trapaca, analyze, bateria), fiscal de segurança, relatório
   `.claude/.ai/reports/FABLE-2026-10-29-final-app.md` + cópia em Desktop\Bora\prompts, digest
   `digest-2026-10-29-final-app`, Telegram, e2e `fecho`, /ctx doctor + /ctx stats.
