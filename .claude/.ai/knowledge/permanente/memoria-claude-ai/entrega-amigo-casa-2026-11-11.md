---
id: memoria-claude-ai-entrega-amigo-casa-2026-11-11
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Entrega para a Claude.ai: publicar o Amigo com a Casa e Manutenção (11/11)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `entrega-amigo-casa-2026-11-11`, origem `claude-code`, atualizada em 2026-11-11T17:07:00.218786+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: entrega amigo casa 2026 11 11 · memoria claude.ai · claude_ai_memoria

Missão amigo-casa-2026-11-11 (Danilo 11/11 12:39: "Conserta o amigo"). Feito no PC pelo Claude Code; falta só PUBLICAR, que a trava reservou à Claude.ai.

ONDE ESTÁ O CÓDIGO: página entrega-amigo-casa-2026-11-11-patch (git diff, md5 do conteúdo aa6ddea34a702031a301eda498ebc0b1, 25944 caracteres). Aplica-se por cima de origin/autonomous-night-2026-04-29 no commit b8af9bc9 (client-assistant v24 no ar é igual a esse commit, 8 ficheiros conferidos). Toca só supabase/functions/client-assistant: amigo.ts, index.ts, casa.ts (novo) e casa_test.ts (novo). No PC está também o commit c3fd3033 no ramo local ai/2026-11-11-amigo-casa (worktree C:\BoraLocal\wt-amigo-casa), com docs/relatorio-amigo-casa-2026-11-11.md e a linha em docs/TRANCAS.md; não subiu ao GitHub porque o git desta sessão não tem credencial.

PUBLICAR: deploy da Edge client-assistant com 9 ficheiros (client-assistant/index.ts, amigo.ts, estilo.ts, sugestao.ts, casa.ts; _shared/claude.ts, keys.ts, chaves.ts, embeddings.ts), entrypoint client-assistant/index.ts, verify_jwt TRUE (como a v24). Não é preciso versão nova da app: a ligação "Abrir a Casa e Manutenção para marcar" vai como deixa abrir_faixa {tipo_destino: categoria, destino: casa}, que as apps publicadas já abrem (tocarDeixa -> abrirDestino -> CasaCategoriaScreen). Nada de dinheiro: só lê casa_config (preços da casa_servicos) e grava uma linha em assistant_deixas.

PROVAS DEPOIS DE PUBLICAR (conta de teste demo@bora.app, sem dinheiro): "preciso de montar um roupeiro" -> 80,00 € por móvel + material é do cliente + ligação abre a Casa, sem "quantas pessoas" nem botão de Favor; "quanto custa pendurar uma televisão?" -> 45,00 €; "tenho a torneira a pingar" -> Trocar torneira 40,00 € (ou autoclismo/sifão 20,00 €/h); "quero pintar a sala" -> PINTURA ESTÁ DESLIGADA em produção (ofício fase 2, IMPIC), o Amigo diz que ainda não está disponível (não dá orçamento de pintura); "quero açaí" -> Goola como antes, sem ligação da Casa. Na web e no Android.

JÁ PROVADO NO PC: deno test 55/55 (8 novos da Casa), deno check index.ts limpo, anti_trapaca limpo, casa_config real de produção passada pelo casa.ts dá roupeiro 80,00 € por móvel, televisão 45,00 €, torneira 40,00 €, autoclismo 20,00 € por hora, orçamento com fotos; desligados: Jardinagem, Mudanças, Eletricidade, Gás, Pladur, Pintura.

PARA O DANILO: os anúncios de hoje falam de pintura? Em produção a Pintura (e Eletricidade, Gás, Pladur, Jardinagem, Mudanças) está desligada; ligar é decisão dele no painel (Casa > ofícios), e exige profissional com certificado.
