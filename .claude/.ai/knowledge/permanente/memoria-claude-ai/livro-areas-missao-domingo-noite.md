---
id: memoria-claude-ai-livro-areas-missao-domingo-noite
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# Missão grande de domingo à noite (08/11/2026) para terminar o que falta no Bora — lista de pendências que o Danilo vai ditando; ler antes de montar essa missão

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-missao-domingo-noite`, origem `claude-ai`, atualizada em 2026-11-08T19:14:14.280642+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas missao domingo noite · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/missao-domingo-noite.md), copiada a 08/11/2026 18:14 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: missao-domingo-noite
description: Missão grande de domingo à noite (08/11/2026) para terminar o que falta no Bora — lista de pendências que o Danilo vai ditando; ler antes de montar essa missão
sources: [chat]
aliases: [missão de domingo, lição enorme, terminar o que falta, pendências do domingo]
---
- [stated] 07/11/2026: quer uma missão enorme no domingo à noite (08/11) que termine tudo o que está a faltar; vai ditando as coisas e eu vou gravando aqui
- [stated] Pendência: terminar o check-in diário (diz que não terminou) — ver [[bora-todo-dia]]
- [stated] Ideia: notificação diária com um restaurante por dia (rotativo) ou o restaurante em que o cliente mais clicou — ver [[bora-todo-dia]]
- [stated] Pendência (07/11): no app do estafeta/motorista não há onde atualizar nem ver o que falta na conta (caso [[valdemir]]: confirmação fiscal, documentos, selfie, IBAN); tem de aparecer tudo o que falta, no app e no painel admin. Prompt pronto (PROMPT_estafeta_ve_o_que_falta) — entra na missão de domingo
- [stated] Pendência (07/11): no mapa do estafeta/motorista, o botão de centrar o mapa (a mira) está lá em cima no canto e é difícil de carregar; tem de ficar no meio do ecrã, um pouco mais para baixo, do lado direito. Entra na missão de domingo
- [stated] Pendência (07/11 21:27): Jyosmi Sushi (id jyosmi-sushi-guarda, site https://strangeroasis.com/encomendas/) — o que está no site tem de estar no Bora. Comparação feita: preços iguais ao tamanho pequeno; faltam os tamanhos médio e grande nos combinados e entradas (site: Combinado Tradicional 12/15/33 €, etc.); falta a bebida grátis nas caixas médias e grandes do Especial JYOSMI; falta Fanta Guaraná Antártica 2,20 € e rever a San Pellegrino (no Bora, não vista no site); cerveja, vinho e sangria do site não estão no Bora (ver se entram); nomes: "Caixa de Sushi Fritos" no site = "Caixa Crocante" no Bora, "Gyoza Frio" = "Ravioli Frito (Gyoza)"; tempo: site diz pedidos prontos em 30–45 min e o Bora marca 20 min de preparação — acertar o tempo de entrega. Quando ele falar da missão, puxar tudo isto
- [stated] Pendência (08/11 17:27): pedido AGENDADO de loja não-parceira (caso Jyosmi, abre às 19h, fica pronto às 19:15) — o sistema chama o estafeta 30 min antes da hora marcada (setting dispatch_antecedencia_agendado_minutos=30); ele quer que chame só perto da hora em que fica pronto, ou, se chamar antes, que o estafeta veja "pedido agendado, só fica pronto às X". Não é para arrumar já, entra na missão de domingo
- [stated] Pendência (08/11 18:24, pedido Burger King da Priscila Prates, id 56fa8623-dd4d-4ae6-86b0-96679f20fbf8, estafeta = o Danilo): ele mandou gravar para a missão grande corrigir tudo isto. (1) PREÇO: talão 29,95 € contra 28,98 € pelo catálogo da Bora (menu 13,25 + opções; menu 1 no balcão 14,95 contra 14,24 na app, menu 2 14,95 contra 14,74, saco 0,05); catalog_price_gap_cents=97, margem ficou 3,38 € em vez de 4,35 €. O robot catalog_price_update_from_receipt NÃO criou nenhuma linha em catalog_price_updates para este pedido (última linha do robot: 06/11) e o produto bk-078771af-f4cb-451a-b645-3738400175df continua a 13,25 €. Causa provável: nomes do talão não casam com o catálogo ("Tripwhopper" contra "Triple Whopper Spicy Menu") e extras como "EXTRA BACON 2 FATIAS" 2,50 € contra 0,91 € na app. Rever o casamento de nomes do robot e corrigir o catálogo do Burger King por esta regra (talão mais caro corrige sozinho, só SUBIR). (2) GORJETA: os 2,00 € estão em tips (status succeeded, liquido_prestador_cents 200, provider = o Danilo) e entram no acerto semanal, mas NÃO aparecem no extrato do pedido (ledger_entries só tem earning 5,23 e comissão 0,99) e ele não os viu no app do estafeta ao entregar; a gorjeta tem de aparecer no pedido entregue. (3) STRIPE: a gorjeta ficou com stripe_account='pessoal' enquanto o pedido está 'empresa', com o mesmo payment_intent pi_3UZaIhGWwQxC9wR21IGrtriS (cobrado 36,62 €); verificar em que conta caiu o dinheiro e corrigir. stripe_fee_cents da gorjeta está null. Danilo diz que "a Stripe, a gorjeta, tudo aí está errado": auditar. (4) ENTREGA GRÁTIS no Burger King a partir de 30 € foi decidida a 23/10 (não é erro); neste pedido a Bora ficou com prejuízo de ~1,36 € antes de IVA.

