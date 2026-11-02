---
id: memoria-claude-ai-digest-2026-11-02-zerar
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-02
zona: verde
confianca: alta
estado: atual
---

# Claude Code 02/11 — zerar: chave nova no servidor, série de limpeza devolve, peso no cartão pronto (desligado), arrumações; app não publicada

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-02-zerar`, origem `claude-code`, atualizada em 2026-11-02T16:56:06.192736+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 02 zerar · memoria claude.ai · claude_ai_memoria

Missão zerar-2026-11-02 (Claude Code no PC, Opus, prompt-zerar-2026-11-02, autorização do Danilo 02/11 14:46 itens 2, 3 e 4). e2e_log fluxo zerar-2026-11-02 (6247 em diante). Relatório .claude/.ai/reports/zerar-2026-11-02.md (só no PC).
B1 CHAVES: o servidor já manda a chave nova. Uma alavanca só: vault.service_role_key passou a ter a sb_secret às 15:02 (cópia da legada em vault.service_role_key_legada_bkp_20261102; voltar = vault.update_secret). As 85 rotinas e os 9 crons que chamam Edge Functions leem esse nome; nenhuma chama rest/auth/storage; o Bloco 3 de 16/10 ficou desnecessário e não se aplica. Provas: vigia 50/50 ok, 17 funções fora do vigia sondadas, tráfego 15:02-16:21 226x200 e 0 recusas. backend/.env do PC trocado. FALTA: .env da VPS (whatsapp-bora, assistente-negocio; o classificador recusou a escrita remota; scripts em docs/propostas/zerar-2026-11-02) e o segredo GitHub SUPABASE_SERVICE_ROLE_KEY. A App Store PT passou a vender a 1.0.34 às 16:14: app_min_supported_version_code_ios 0->222 e app_latest_version_code_ios 224->222. Android mínimo fica 0 até se confirmar o versionCode vivo na Play. Desligar as legadas: PUT api-keys/legacy?enabled=false (hoje enabled=true), só depois disto tudo.
B2 SÉRIE DE LIMPEZA: cancelar uma limpeza NÃO usa carteira; devolve pela Stripe ao cartão/MB Way (cleaning-checkout reverse). "Parar a série" passou a chamar cancel_cleaning_booking por limpeza (20261102153510) e a app pede o mesmo reverse; cleaning_series_preview diz quanto volta. Prova em rollback ok. Nunca houve limpezas pagas canceladas pela série.
B3 PESO NO CARTÃO: a cobrança já existia (cobrar-diferenca-peso v6, duas contas, desligada). Aviso corrigido (20261102154930: MB Way nunca é cobrado), recibo e painel por estado. weight_adjust_card_charge_enabled continua false: o servidor não tem chaves de teste da Stripe, a prova com cartão de teste é impossível.
B4: update-products v29 publicada (sem market 400; volta Continente 200, 0 falhas). robot_apply_suggestion: hide_store passa pelo admin_suspender_prestador com motivo (20261102161305). Painel: suspensão temporária para estafetas. Melões/meloas do Continente com €/kg do site x peso médio §59 (backup bkp_products_meloes_20261102); Melancia Riscada não existe no site, ficou indisponível. Página apagar-conta escrita no bora-site (commit local 0bd9522), publicação recusada pelo classificador; Play Console não tocada. O alarme do filme é do PC (BoraStudio tique_v5.py, tarefas BoraStudioRelogio/Condutor), não da VPS; desligar foi recusado pelo classificador. Assinatura VPS: a data 09/10 era uma estimativa; a data real só está no hPanel (sem sessão).
APP NÃO PUBLICADA: analyze 0 erros, 2871 testes verdes (Flutter 3.41.2), Juiz limpo; commits ecf73229 + 75b11dc8 só no PC (worktree bridge-cse_01HPEpVAGPaiWDPnrbGwZxmL, ramo zerar-2026-11-02). O classificador recusou o push para autonomous-night e o guardrail só deixa esse ramo. Publicar = git push origin zerar-2026-11-02:autonomous-night-2026-04-29.
ARMADILHAS: a tranca recusa um ficheiro de migração com a palavra Stripe nos comentários; o classificador recusa escrita remota na VPS, publicar o site, desligar tarefas agendadas e o push de produção; ler o ar (net._http_response) prova a troca de chave melhor do que pings.
