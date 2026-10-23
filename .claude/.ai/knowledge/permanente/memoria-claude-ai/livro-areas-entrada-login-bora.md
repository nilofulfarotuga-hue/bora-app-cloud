---
id: memoria-claude-ai-livro-areas-entrada-login-bora
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Portas de entrada do [[bora-app]] (cliente, estafeta, parceiro) — regras que o Danilo fixou e prompt de auditoria entregue a 28/08

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-entrada-login-bora`, origem `claude-ai`, atualizada em 2026-10-23T05:42:41.697519+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas entrada login bora · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/entrada-login-bora.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: entrada-login-bora
description: Portas de entrada do [[bora-app]] (cliente, estafeta, parceiro) — regras que o Danilo fixou e prompt de auditoria entregue a 28/08
sources: [chat]
aliases: [login do app, portas de entrada, entrar no app, recuperar palavra-passe, aba do parceiro]
---

- [stated] REGRA (28/08): a aba do PARCEIRO não tem botão de voltar e as outras duas têm — tem de levar botão de voltar em baixo, que devolve ao ecrã inicial de escolha entre cliente, estafeta e parceiro. As três portas têm de ficar iguais neste ponto.
- [stated] REGRA (28/08, ele lembrou que já a tinha pedido): o MESMO email tem de servir para entrar como cliente e como estafeta — a pessoa sai e volta a entrar escolhendo o outro perfil, sem criar conta nova.
- [stated] PROMPT ENTREGUE 28/08: `PROMPT_auditoria_entrada_bora_2026-08-28.md` (motor OPUS, Claude Code no PC) — auditoria às portas de entrada depois de um cliente real ficar sem entrar: email transacional a não sair para ninguém, recuperação de palavra-passe partida, entrada web a abrir no login de parceiro, botão de voltar em falta, falhas de credenciais, erro ao listar utilizadores no painel admin e mensagens de erro em português; inclui procurar mais casos do mesmo tipo. Substitui o prompt anterior só sobre recuperação de senha. Estado: entregue, aguarda ele correr.
- [stated] O flyer fica retido até o executor dizer qual é o URL certo da entrada de cliente — o QR aponta para o endereço que estava a abrir na porta dos parceiros.
- [stated] REGRA ALARGADA (29/08, dita por ele): uma conta, uma pessoa, TODOS os perfis — estafeta pode entrar como cliente, parceiro pode entrar como cliente, parceiro pode ser estafeta, e em todas as combinações ao contrário, sempre com o mesmo email e a mesma palavra-passe. Ninguém tem de criar segunda conta. Substitui/alarga a regra de 28/08 que falava só de cliente+estafeta.
- [stated] PROMPT ENTREGUE 29/08: `PROMPT_multiperfil_uma_conta_2026-08-29.md` (motor OPUS, Claude Code no PC) — app deixa de expulsar quem tem vários papéis, troca de perfil dentro da app sem novo login, pedido pendente de estafeta/parceiro não bloqueia o uso como cliente, botão de voltar na aba do parceiro, portas bem marcadas, fundir a conta remendo com `+cliente` do cliente Junior, e o bloco do ecrã do estafeta preso no carregador quando a pessoa recusa a localização. Estado: entregue, aguarda ele correr.
- [stated] PEDIDO 10/10: quer que o cliente crie a conta no Bora com um clique no Google ("pela conta dele do Google") — mais fácil para ele; mandou fazer igual ao que os outros (Uber, Glovo, iFood) fazem, consultando-os primeiro; autorizou-me a avançar ("eu autorizo")

