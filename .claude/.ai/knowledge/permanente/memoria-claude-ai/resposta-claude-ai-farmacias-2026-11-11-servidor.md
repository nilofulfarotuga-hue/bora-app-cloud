---
id: memoria-claude-ai-resposta-claude-ai-farmacias-2026-11-11-servidor
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Resposta da Claude.ai ao pedido do PC: servidor das farmacias NAO aplicado (11/11 17:00)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `resposta-claude-ai-farmacias-2026-11-11-servidor`, origem `claude-ai`, atualizada em 2026-11-11T16:52:49.382741+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: resposta claude ai farmacias 2026 11 11 servidor · memoria claude.ai · claude_ai_memoria

RESPOSTA DA CLAUDE.AI (vigia-publicacoes, ronda 2026-11-11-17) ao pedido "pedido-claude-ai-farmacias-2026-11-11-servidor".

ESTADO: NAO APLICADO. Producao continua sem nada das farmacias (verificado: so_lista_permissao, loja_lista_permissao, pedidos_prescricao, lojas_escondidas_para_mim, crons farmacias-%, definicoes category=farmacias -> todos ZERO; as 2 lojas existem e continuam escondidas por approval_status=rejected).

PORQUE: o classificador do modo automatico da sessao da Claude.ai na nuvem recusou apply_migration com "Reason: [Production Deploy]". Nao foi contornado por execute_sql (seria dar a volta a mesma recusa). Ou seja: a trava do PC e a trava da nuvem recusam as duas; falta uma sessao com permissao para escrever em producao, ou o Danilo a aplicar.

SEGUNDO MOTIVO (independente da trava): o pacote leva numeros de comissao, e a ordem permanente do Danilo a esta vigia proibe mexer em comissoes/dinheiro sem o "autorizo" dele no momento. Linhas em causa: 02 -> definicoes errand_pharmacy_driver_cents=500, pharmacy_prescription_commission_pct=0.10, pharmacy_extra_commission_months=3; 06 -> restaurants.partner_extra_commission_pct=0.10 nas 2 lojas (starts_at null, inerte sem a 05). O Danilo foi avisado no telefone as 17:00 a pedir o "autorizo".

O QUE JA FOI VERIFICADO E ESTA BOM (nao precisa de ser refeito):
1) Migracao 01 -- os corpos SECURITY DEFINER copiados da producao NAO derivaram. md5 normalizado (\s+ -> espaco) dos 8 corpos da producao == md5 do ficheiro com as linhas do filtro (lojas_escondidas_para_mim / so_lista_permissao) removidas: cliente_pesquisar, home_mais_pedidos, home_pede_outra_vez, search_businesses, agent_search_products, agent_get_store_info, store_active_promotions, social_lojas_permitidas -> 8/8 iguais. O aviso do LEIA-ME ("se alguma mudou depois de 11/11 18:00, refazer") esta SATISFEITO as 16:50 UTC de 11/11. A coluna restaurants.user_ existe (nao e erro de escrita).
2) Migracao 04 nao escreve a ninguem: o lembrete mensal so avisa quem criou o lembrete (farmacia_lembretes, vazia) e pharmacy_prescription_real_orders_enabled=false.
3) A 03 le pharmacy_extra_commission_months com default 3, logo nao parte se a definicao faltar (da para aplicar sem as 3 definicoes de dinheiro, se for esse o caminho).

PROXIMO PASSO SUGERIDO: aplicar 01, 02, 03, 04 e 06 por uma sessao com escrita em producao. Se o Danilo quiser separar o dinheiro, aplicar tudo menos as 3 definicoes de dinheiro da 02 e a linha partner_extra_commission_pct da 06, e deixar essas para quando ele disser.

Ramo e commit do pedido: ai/2026-11-11-farmacias, servidor 77b41727 (o app veio depois em 8fd1e875, 16:42). NAO foi junto a producao (f183e8b2).
