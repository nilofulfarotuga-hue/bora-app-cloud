---
id: memoria-claude-ai-digest-2026-10-05-claude-ai-manha
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: alta
estado: atual
---

# Claude.ai 05/10 manhã — dinheiro, despacho v62, segurança, secretário

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-05-claude-ai-manha`, origem `claude-ai`, atualizada em 2026-10-05T08:17:40.018624+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 05 claude ai manha · memoria claude.ai · claude_ai_memoria

O QUE MUDOU EM PRODUÇÃO A 05/10 (Claude.ai, sessão cloud, com autorização do Danilo):
- Reembolso: pedido pago (cartão/MB Way) cancelado PELO SISTEMA fica "por reembolsar" (refund_status='failed' + refund_amount/método + linha em cancellation_requests) → botão "Reprocessar" do ecrã Cancelamentos faz o reembolso (MB Way → saldo da carteira por inteiro; cartão → Stripe). Gatilho trg_reembolso_cancelado_pelo_sistema. Não move dinheiro sozinho.
- REGRA DO DANILO 05/10: o cliente paga o preço que vê na app; o excedente da pré-autorização NUNCA se devolve (se o real sair mais barato, fica com a Bora; se sair mais caro, a Bora assume e o preço corrige-se). Gatilho trg_excedente_preautorizacao criado e DESLIGADO.
- Pagamentos fantasma: cron 2 bora_weekly_auto_payout desligado; 10 linhas 'payout' (173,50 €) anuladas com linha inversa; payouts → failed (bkp_payouts_20261005). A tabela payouts não é fonte de verdade.
- "Marcar pago" (admin_set_settlement_state) aceita a segunda em hora de Lisboa e a data UTC (_semana_bate).
- Despacho: dispatch-engine v62 publicado pela sessão PC do Danilo (matching em dispatch_candidatos_entrega). dispatch_gps_fresh_seconds_entregas = 172800 (48 h) TEMPORÁRIO porque Danilo e Valdemir tinham GPS parado com sinal fresco → 0 candidatos. Voltar a 900 quando tiverem a app nova (verificação marcada 07/10).
- Segurança: 8 funções SECURITY DEFINER sem guarda fechadas a anon (compute_provider_weekly_payout, tvde_reservation_offer_to_next, get_user_tokens, order_driver_reimbursement, compute_all_*_weekly_settlements, 2 crons). e2e_log: anon/authenticated só leem id e created_at (escrever continua).
- Secretário Virtual: prospects_presenca aceita cliente_tipo 'secretario-virtual'; ordem ao PC para voltar a correr o caçador.
- Gmail do caça-clientes: já autorizado desde 03/10 e app OAuth "Em produção" (não caduca).
- Lentidão de 02/10: causa nos registos foram heartbeats duplicados + bloqueios em drivers/orders (não os produtos); 24 h até 05/10: 0 deadlocks, 0 timeouts, 0 erros 5xx.
- Filme: 50 vídeos de animação retagueados para animacao_ia; página caminhos-animacao-filme com 5 caminhos; resumo das 20:52 antecipado.
POR FAZER (prompt entregue ao Danilo para a sessão PC): blocos A (dinheiro das entregas), B (dinheiro do painel) e C (resto da segurança). As migrations de 05/10 aplicadas pela Claude.ai estão no histórico do Supabase; os ficheiros no repo de algumas (080316, 080440, 080554, gps 48h, e2e_log) ainda não foram gravados.
