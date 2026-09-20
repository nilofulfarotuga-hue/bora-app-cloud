---
id: memoria-claude-ai-digest-2026-09-20-contas-claras
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-20
zona: verde
confianca: alta
estado: atual
---

# Claude Code Opus 20/09 — contas claras: saldo = soma do histórico, extratos e vigia

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-20-contas-claras`, origem `claude-code`, atualizada em 2026-09-20T20:28:14.831386+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 20 contas claras · memoria claude.ai · claude_ai_memoria

O que funciona agora. A carteira tem uma verdade só: gatilhos em wallet_transactions fazem client_wallets.free_balance_cents ser sempre a soma do histórico (sem refund_credit_tokens) no fim de cada transacção, balance_after_cents vem da soma, e o histórico não se reescreve nem apaga (correcção = linha nova de estorno). O talão tem dois caminhos no admin: admin_mark_receipt_paid (credita a carteira, method wallet) e admin_mark_receipt_paid_external(receipt, mbway|cash|transfer, paid_at, ref, notes) sem crédito; o talão b89e66d2 do Valdemir está como pago por MB Way a 19/09. wallet_credit_refund_split idempotente (aplicado pela Claude.ai 20:29, espelho 20260920202900 no repo). Extratos: extrato_prestador(p_semanas, p_user_id) para estafeta/motorista (trabalhos um a um com parcelas, deve/deve-lhe com linhas, dinheiro em mão, acertos+comprovativo, talões pelo nome; bate ao cêntimo com driver_balances e tvde_driver_balances — Valdemir: Bora deve 36,50 = 5,00 acerto + 31,50 TVDE); extrato_parceiro(restaurant_id, dias) (pedido a pedido, parte da Bora sobre X de produtos, transferido/por transferir com datas; Goola 52,50 em 3 arcas iguais, Stripe Connect desligado = pagamentos por MB Way); admin_extrato_dono(de, ate) (entradas por meio, saídas, retido, a quem a Bora deve e quem deve com botão). Vigia: vigia_dinheiro_diario (cron 06:10) compara 8 pares histórico×saldo, escreve em payment_reconciliation_findings e grita no Telegram só em caso novo; Isabel é caso conhecido e calado; primeira corrida gritou 9 casos reais (TVDE do Danilo −14,20; 3 payouts parados; 4 compensações de 1,50 fora do acerto; Sabores do Brasil 10,29 sem acerto). Painel admin: Contas claras (folha do dono), Extratos por pessoa, Vigia do dinheiro, dois botões no talão. Como se usa: apps lêem as RPCs; o Flutter não calcula; valor nulo aparece como traço. O que falta: push (commit d7eb1426 local; exige autoteste dos 3 perfis); até ao deploy web o botão antigo "Marcar pago" ainda credita a carteira — talão pago por MB Way passa pela Claude.ai (RPC external); staged_contas_claras_20260920_b2 (invólucro _prestador_semana_em_curso para o admin) por aplicar; decisões de dinheiro do Danilo: TVDE entrar no acerto (31,50 Valdemir, 79,10 Danilo, 4,00 Erika), compensações 1,50 no acerto, 14,20 do TVDE do Danilo, payouts parados, Sabores 10,29, linha de fecho da Isabel (−3,09). Mapa em docs/MAPA-DO-DINHEIRO.md, referência em docs/REFERENCIA-EXTRATOS.md, relatório RELATORIO-contas-claras-2026-09-20.md (cópia em Desktop/Bora/Projetos), provas em .claude/.ai/provas/contas-claras-20260920/.
