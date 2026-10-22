---
id: memoria-claude-ai-digest-2026-10-22-geral-noite
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-22
zona: verde
confianca: alta
estado: atual
---

# Noite 21→22/10 — geral-noite (fila, encomendas, segurança, e-mail dos agentes)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-22-geral-noite`, origem `claude-code`, atualizada em 2026-10-22T05:12:48.917302+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 22 geral noite · memoria claude.ai · claude_ai_memoria

Missão geral-noite-21-10 (sessões local_6914492a orquestradora e local_b16c6598, que retomou o registo às 06:00 porque a orquestradora parou às 05:08). Relatório completo: .claude/.ai/missoes/fechar-pendencias-2026-10-20/RELATORIO-NOITE-21-10.md (ramo n3b-22-10). NO AR: (1) Fila inteligente do Bora Motorista ligada desde 21/10 20:21 (tvde_fila_inteligente_enabled=true); 0 corridas até 22/10 05:52; vigia de 15 em 15 min até 12:00 desliga se uma corrida passar 60 s sem oferta. A2 nas 3 (Android 682/683, web, iPhone build 201; 1.0.24 em revisão Apple). (2) Encomendas: avisos e palavras próprias no servidor (notify-tvde-driver v23, notify-tvde-client v8, tvde-recibo-viagem v6), mesmo acesso do Bora Motorista; enviado 4e6030c1, web provada; Android/iPhone ainda a compilar às 05:58; tvde_encomendas_enabled=false. (3) Segurança N4 (Android 684): push só servidor/admin em 3 Edges, avatars só na própria pasta, 12 funções internas só service_role. (4) 3b aplicado 05:25: gatilhos a00_pedido_loja_estafeta_guarda_upd/_ins (cliente não escreve loja/estafeta/oferta/tried no próprio pedido nem cria com eles) e a00_lavagem_escrita_direta_guarda (lavagem só photos_client pelo próprio cliente); migrações 20261022042522/042551; reversão n3b/reversao_N3b.sql. (5) E-mail dos 7 agentes @boraguarda.com: Cloudflare Email Routing -> Worker -> Edge agentes-email-receber -> tabela agentes_email; o Emerson usa hermes-email no contentor; ponte da VPS corrigida (utilizador agentes-ponte sem privilégios, sandbox systemd, O_NOFOLLOW) e religada 05:05; revisor da 2.ª ronda SIM às 06:15 (7 armadilhas recusadas, e2e 4355/4356); ramo agentes-email-21-10 por enviar. FALTA / À ESPERA DO DANILO: autorizo para as 3 Edges de pagamento com a chave nova (refund, finalize-order-from-intent, charge-extra) + PAT novo do Supabase; prémio da loja no acerto e taxa de serviço do prémio; fechar leitura de platform_settings; fechar INSERT cru de orders pelo cliente; leitura do dinheiro das lavagens (precisa mudar a app); YouTube conta 1 (página de entrada aberta no Chrome pessoal); permissões das sessões (N8) na app. REGRAS NOVAS DA NOITE: ficheiros .sql em supabase/migrations e supabase/functions disparam build Android + deploy web (paths-ignore só cobre md/.claude/docs); sessão orquestradora pode parar sem aviso — combinar sempre quem retoma após 40 min calada; nunca religar uma correção de segurança antes do revisor.
