---
id: memoria-claude-ai-digest-2026-10-05-v62-favor-push
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: alta
estado: atual
---

# v62 do despacho no ar, Favor por função própria, envio feito

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-05-v62-favor-push`, origem `claude-code`, atualizada em 2026-10-05T08:13:10.774304+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 05 v62 favor push · memoria claude.ai · claude_ai_memoria

05/10/2026, Claude Code, ordem do Danilo "vai: v62, função do Favor e push". O motor de despacho está agora na versão 62 no ar (verify_jwt=false): só a chave de serviço, admin, estafeta aprovado, dono do pedido ou dono da loja o acordam; sem token, chave pública ou service_role forjado recebem 403, e a chave do cofre do banco entra (200). Os candidatos vêm de dispatch_candidatos_entrega (GPS e batimento frescos, uma oferta de cada vez, favor sozinho, 20 km). O repo tem o mesmo ficheiro (commit 8108952c). Não se fez o teste do pedido demo porque o Valdemir real estava online e ia receber a oferta falsa; a prova do matching fica no primeiro pedido real (registos "[dispatch] N candidatos" e "SUCCESS"). Voltar atrás: publicar o ficheiro do commit 30855c27. O dinheiro da paragem em casa do Favor passa pela RPC estafeta_registar_dinheiro_paragem(p_order_id, p_cents), provada em transacção desfeita; a app do estafeta usa-a a partir deste build. A escrita directa em orders.errand_home_stop_cash_cents continua aberta até todas as apps estarem atualizadas: fechar depois. Envio 25e98847..8108952c dispara build Android e web. e2e_log 2881 e 2882. Relatório: .claude/.ai/reports/2026-10-05-v62-favor-push.md.
