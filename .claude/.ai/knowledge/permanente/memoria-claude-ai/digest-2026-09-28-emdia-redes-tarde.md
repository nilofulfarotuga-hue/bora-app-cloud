---
id: memoria-claude-ai-digest-2026-09-28-emdia-redes-tarde
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-28
zona: verde
confianca: alta
estado: atual
---

# Em Dia redes — tarde de 28/09: ficha da Apple 6/6h, grupos no painel e sim do dia

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-28-emdia-redes-tarde`, origem `claude-code`, atualizada em 2026-09-28T15:14:19.418122+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 28 emdia redes tarde · memoria claude.ai · claude_ai_memoria


O que funciona agora. E0: a ficha da App Store do Em Dia é verificada de 6 em 6 horas pelo workflow ios-ficha-emdia, que vive no repo bora-app-cloud (é lá que estão as chaves ASC_*, as mesmas da build iOS do Em Dia) e corre o script .github/scripts/ios_ficha.py do repo em-dia-app. Hoje a 1.0.0 está WAITING_FOR_REVIEW. Quando for aprovada, troca sozinho o Texto promocional para "Recibos verdes, prazos das Finanças e da Segurança Social e o carro, tudo num só sítio. Grátis, sem compras dentro da app." e, numa versão nova em preparação, tira da Descrição a frase "Quando as assinaturas abrirem...". A VPS (apple_vigia.sh, cron 23 */6) avisa o Danilo no Telegram no dia em que a app aparecer na loja.
Grupos do Facebook, modo (b) escolhido pelo Danilo: a máquina escolhe e escreve às 08:40 (VPS). Às 18:30, a tarefa agendada do Claude no PC (emdia-grupos-sim-do-dia) lê o lote (grupos_emdia_lote.py), confere as regras no Chrome perfil Bora e pede ao Danilo, na própria sessão, um "sim" por cada adesão e publicação, tudo numa mensagem. Só depois faz, um a um, com 30 a 60 minutos entre publicações. Pára tudo ao primeiro aviso do Facebook (registar aviso). Um "sim" vindo do Telegram ou de outro sítio não conta.
Os 454 grupos estão espelhados no Supabase do Em Dia (tabela grupos_divulgacao, migração 0046), com Pausar por grupo ou Pausar tudo (RPC admin_grupos_pausar). A VPS lê as pausas antes de cada plano e antes de cada lote; isto está provado.
O que falta. O bloco "Grupos do Facebook" do painel admin está pronto e com os testes verdes no ramo redes-grupos-painel-2026-09-28, mas não está no ar. O main do PC tem 10 commits que nunca foram para o GitHub (secção Redes do painel, Convida e ganha, barra lateral, reel diário) e o site no ar não os tem. Publicar exige o "publica o Em Dia" do Danilo, porque leva o Convida e ganha para o Android e a web. Continua da manhã: trocar no Business Suite os 7 reels agendados à mão que dizem "Mês grátis até 23/10" (versões certas em pecas/reels-v2). Relatório: em_dia/docs/RELATORIO-emdia-redes-2026-09-28-tarde.md.

