---
id: memoria-claude-ai-livro-areas-bora-todo-dia
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Check-in diário e "Bora Todo Dia" do Bora App — tokens por dia, marcos com prémios de parceiros (10/15/30 dias) e a regra de 29/10 de um prémio por sequência; ler antes de mexer no check-in ou nos prémios

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-bora-todo-dia`, origem `claude-ai`, atualizada em 2026-10-30T22:13:47.855192+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas bora todo dia · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/bora-todo-dia.md), copiada a 2026-10-30 22:12 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: bora-todo-dia
description: Check-in diário e "Bora Todo Dia" do Bora App — tokens por dia, marcos com prémios de parceiros (10/15/30 dias) e a regra de 29/10 de um prémio por sequência; ler antes de mexer no check-in ou nos prémios
sources: [chat]
aliases: [Bora Todo Dia, uso diário, jogos com tokens, receitas diárias, hábito diário, retenção]
---
- [stated] 10/10/2026: quer trazer os clientes a mexer mais no app todos os dias, não só quando precisam de pedido — receitas, notificação diária (para elas), jogos simples e fáceis que deixem a pessoa "viciada" e que dêem tokens, e algo que interesse aos homens
- [stated] Pediu primeiro ver o que o mundo faz; depois de ler duas listas de ideias (Check-in/streak, roda da sorte, mascote, receita do dia, palpite de futebol, quiz, Bora Frutinhas, Guarda Hoje, etc.) disse que gostou de todas
- [stated] Quem decide quais fazer sou eu; ele quer ouvir primeiro a minha opinião e a das outras IAs (conselho), além da dele
- [stated] Plano dele: guardar para segunda-feira (12/10) e executar; fazer 4, 5 ou 6 de uma vez, lançando uma novidade por semana para os clientes
- [stated] 10/10/2026: conselho (Gemini, ChatGPT, DeepSeek) consultado a pedido dele; ele deixou a decisão final comigo. Plano guardado para segunda-feira, uma por semana: 1) check-in diário com sequência, 2) Guarda Hoje, 3) receita do dia com ingredientes no carrinho, 4) quiz diário da Guarda/futebol, 5) palpite de futebol só com tokens e sem prémio em dinheiro. Fora por agora: mascote, jogo de frutas, caça ao preço. Regras: tokens validados no servidor, 1 por dia por pessoa, teto mensal; sem roletas nem sorteios (jogos de fortuna em Portugal)
- [stated] 13/10/2026: escolheu o check-in diário como primeira novidade e aprovou a tabela de tokens: Dia1=5, Dia2=5, Dia3=10, Dia4=10, Dia5=15, Dia6=15, Dia7=40 (100 tokens/semana = €0,50); falhou um dia volta ao Dia 1; depois do Dia 7 recomeça; só com telemóvel confirmado; tokens expiram em 60 dias; tudo editável no painel admin. Autorizou lançar no PC
- 13/10/2026 05:00: PROMPT_checkin_diario_2026-10-13.md (motor Opus 5.5) colado por mim no claude.ai/code, ambiente bora-app-cloud · Danilo, sessão session_014d9mMFrNbeAKwpUzscvQt9 "Daily check-in feature for Bora" — arrancou, em modo Manual (pode pedir aprovações)
- [stated] 15/10/2026: check-in está no ar (10 check-ins). ORDEM DELE: a 2.ª novidade é só a RECEITA DO DIA; Guarda Hoje, quiz e palpites entram só depois
- [stated] 15/10: ideia dele de marcos mensais do check-in com prémios de parceiros — completou 1 semana → algo; 10 dias → 2 coxinhas da Keli (Sabores do Brasil); 15 dias → um açaí do Goola; 1 mês → algo maior. Pediu-me ideias para não perder tanto dinheiro com isso; ainda não decidido, não implementar sem ele escolher os prémios
- [stated] 18/10/2026: lembretes do check-in vão a toda a gente com sequência a correr (fez o 1.º e tem de fazer o 2.º, 3.º...), já sem a regra de só quem aceitou promoções; quem esquecer um dia deixa de receber até voltar a fazer sozinho
- [stated] 20/10/2026 DECIDIDO (supera "ainda não decidido" de 15/10): marcos do check-in por dias seguidos — 10 dias = 2 salgados da Keli (coxinha ou esfirra), 15 dias = o açaí mais barato do Goola, 1 mês sem falhar = escolhe 2 h de limpeza ou uma lavagem do carro só por fora; grátis só o produto/serviço, taxas, entrega e pedido mínimo pagos. No ecrã fica a semana normal e uma seta abre a vista do mês. Aprovou também tecto de 10 prémios de 30 dias por mês e exigir 1 pedido pago no mês para o prémio de 30 dias. Vai na missão `PROMPT_fechar_pendencias_2026-10-20.md` (Opus 5.5, Claude Code no PC, fluxo e2e_log fechar-pendencias-20-10), entregue a ele para colar
- [stated] 29/10/2026 22:20 (regra nova dos prémios do check-in, "senão eu vou falir"): o cliente NÃO acumula os prémios dos marcos (10, 15, 30 dias) — em cada sequência leva UM só, o mais alto a que chegar; se escolher levantar um prémio (ex.: os salgados da Keli no dia 10), a sequência volta a zero; se não levantar, continua e no marco seguinte troca pelo prémio maior, até ao prémio máximo. Isto tem de estar explicado ao cliente no ecrã, com uma "festa" (efeito/explosão) ao chegar a cada marco. No cartão da home fica a faixa de 7 dias e uma seta abre o calendário do mês inteiro (sem cobrir o ecrã todo), com os dias feitos marcados. Deixou comigo o desenho final ("como os grandes fazem")
- [stated] 30/10 20:23-21:38 (regras novas, "vai"): cada conta tem direito a UMA escada grande (ideia dele: até 45 dias; primeira semana só tokens; depois prémios das lojas do mais barato para o mais caro, os mais vendidos de cada loja; o prémio grande, limpeza ou carro, só no fim); para avançar o cliente tem de estar elegível (ter comprado algo na app); regras não podem ser difíceis. Depois da grande, escada pequena de 30 dias que repete: aos 15 dias um prémio de pouco valor e aos 30 um pouco maior mas barato, também só com compra. Regras fechadas por mim na página claude_ai_memoria `regras-checkin-v2-2026-10-30`; implementação na missão da semana seguinte

