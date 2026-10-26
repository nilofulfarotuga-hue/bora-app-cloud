---
id: memoria-claude-ai-digest-2026-10-26-paridade-rea
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-26
zona: verde
confianca: alta
estado: atual
---

# Digest 26/10 — paridade REA

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-26-paridade-rea`, origem `claude-code`, atualizada em 2026-10-26T06:40:07.513245+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 26 paridade rea · memoria claude.ai · claude_ai_memoria

Missão paridade-rea-2026-10-26, a pedido do Danilo às 05:26: usar o método do vídeo do REA para ver o que falta ao Bora, sem clonar o iFood. O REA 6.8.0 ficou instalado no PC a partir da fonte oficial. Usei Node 24.22.1 portátil, porque o REA pede essa versão, e registei-o para o Claude Code. A Glovo e a Uber Eats da Guarda foram vistas num Chrome à parte, com perfil novo e sem conta, até ao ecrã de login: ao todo há 66 prints no Desktop\Bora. O iFood mostrou a verificação Cloudflare logo à entrada e parei, como a regra manda. O Bora foi visto da mesma maneira em app.boraguarda.com, no commit 99a23ad2. Ao mesmo tempo, três sub-agentes só de leitura analisaram o código do cliente, do parceiro e do painel admin. O plano tem 15 itens: os 11 primeiros não mexem em dinheiro, e o último junta o que mexe (cupão, assinatura, promoções e agendar) e precisa do autorizo do Danilo. Está nas páginas paridade-rea-2026-10-26-plano e paridade-rea-2026-10-26 e espera a revisão da Claude.ai. Foram reportados 12 erros sem os corrigir. O mais grave: a sessão de convidado continua partida desde 08/09, e por isso "Finalizar pedido" não faz nada para quem não tem conta. Outros: a loja fechada aparece como aberta; o interruptor das gorjetas no painel não grava; o create_order procura a loja pelo nome e não verifica se o produto está esgotado. A tranca recusou apagar o perfil temporário do Chrome, que ficou em C:\Users\danil\_rea_perfil_paridade. Armadilhas: a emulação de telemóvel feita por CDP acaba quando a sessão do script fecha, por isso tem de ser reaplicada em cada passo. No Flutter web, o botão só responde ao rato a sério ou a um click() do JS feito sobre a árvore de acessibilidade. O observe-web-session do REA não regista cliques que não mudam de página.
