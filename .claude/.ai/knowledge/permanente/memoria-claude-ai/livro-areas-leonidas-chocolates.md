---
id: memoria-claude-ai-livro-areas-leonidas-chocolates
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Loja de chocolates Leonidas (Guarda), indicada pelo Cauê do Goola — aberta no Bora a 01/10 como loja não-parceira (balcão + 15%); histórico da abordagem

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-leonidas-chocolates`, origem `claude-ai`, atualizada em 2026-10-23T05:37:40.595626+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas leonidas chocolates · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/leonidas-chocolates.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: leonidas-chocolates
description: Loja de chocolates Leonidas (Guarda), indicada pelo Cauê do Goola — aberta no Bora a 01/10 como loja não-parceira (balcão + 15%); histórico da abordagem
sources: [chat]
aliases: [Leonidas, loja de chocolate, chocolates Leonidas]
---

- [stated] 2026-09-13: o Cauê, do [[goola-acai]], indicou ao Danilo uma loja de chocolates (Leonidas) na Guarda — disse que têm interesse em entrar no [[bora-app]] para fazer entregas. Quem responde do lado da loja é uma mulher.
- [stated] Abordagem que ele escolheu: a primeira mensagem só puxa conversa pela indicação do Cauê, sem proposta nenhuma; a oferta (ele monta a loja no app, painel do parceiro, usar o Bora só para chamar estafeta, mini-site de presente — mesmo esquema do [[mister-kebab]] / [[goola-acai]]) fica para depois de ela responder. Vai escrever pelo WhatsApp da loja do Bora (+351 937 501 673).
- [stated] 2026-09-14: a loja RESPONDEU que quer sim. Danilo decidiu tratar TUDO por WhatsApp — não quer passar na loja nem falar ao telefone. MODELO QUE ELE MANDOU DIZER-LHE: ela recebe o preço de balcão dela e não paga nada por estar na app; a app acrescenta 10% por cima desse preço e é o CLIENTE que paga essa parte, mais a entrega. Os 5% de taxa de serviço NÃO se mencionam à loja ("ela não precisa saber do resto"). Diferente do [[mister-kebab]] (balcão + 15%), por decisão dele. Na mesma mensagem pediu-lhe a lista de produtos com preços de balcão, o horário e a morada certa; as fotos vai buscá-las ao Instagram da loja. Próximo passo: quando ela mandar a lista, montar a loja no [[bora-app]].
- [stated] 2026-09-14, decisões dele antes de montar: a loja entra em DUAS categorias — Restaurantes (principal) + Sobremesas — igual à [[goola-acai]]; mandou verificar primeiro se a loja tem site próprio (não tem, só ficha no site nacional da marca) e quer um site de presente melhor do que todos os anteriores, com as imagens geradas pelo ChatGPT/Gemini. Adiantar o trabalho sem esperar por ela: ela visualizou a mensagem e não respondeu, e ele decidiu esperar em vez de insistir.
- [stated] PROMPT REGISTADO: `PROMPT_leonidas_guarda_loja_e_site_2026-09-14.md`, entregue 14/09 como ficheiro, MOTOR OPUS, porta Claude Code, SESSÃO NOVA na pasta `bora-app-cloud`, missão `leonidas-guarda-loja-e-site` (OPUS porque o plano Go/OpenCode ainda não estava pago). Scope: pesquisa complementar + loja no app com `coming_soon=true` até ela confirmar (preços do site nacional como rascunho em `partner_shelf_price`, cliente paga balcão+10% e a loja tem de receber o balcão exato) + conta de parceiro com o email real da loja + painel admin e categoria Sobremesas + site de presente em `leonidas-guarda.pages.dev` (subdomínio do boraguarda.com só depois de ela confirmar). Estado: CORREU e fechou no mesmo dia — loja `leonidas-guarda` montada (93 produtos com foto, Restaurantes + Sobremesas, `coming_soon=true`), conta de parceiro criada, painel admin passou a deixar editar `extra_categories`, e site de presente no ar em https://leonidas-guarda.pages.dev
- [stated] CORREÇÕES DE DADOS (14/09): o Instagram certo é `@leonidasguarda` (o `@leonidaschocolatesguarda` que eu tinha dado não existe); a ficha da loja no site nacional da marca é de 2023 e traz outra morada, outro telefone, outro email e domingo aberto — tudo por confirmar com a dona.
- [stated] ACHADO QUE VALE PARA TODOS OS PARCEIROS (14/09): a função de repasse `partner_store_share` paga SEMPRE 85,71% do preço do app (subtotal × 0,90 ÷ 1,05) e a coluna `partner_commission_billing` é só um rótulo do painel admin — nenhuma função de dinheiro a lê. Consequência: com o preço a balcão+10% a Leonidas receberia ~94% do balcão (menos 0,85 € num ballotin de 14,95 €); a [[goola-acai]] só recebe o balcão exato porque foi gravada a +16,67%. REGRA FIXADA POR ELE (14/09, corrigiu-me: "é dez por cento a mais que vai aparecer pro cliente, simples"): o preço que o cliente vê é o balcão + a percentagem do app dessa loja, e o parceiro RECEBE O PREÇO DE BALCÃO EXATO — produto de 10 € ao balcão aparece a 11 € e a loja recebe 10 €. Mandou que valha PARA TODOS OS PARCEIROS, não só para a Leonidas, e recusou a trava que eu tinha recomendado. CONSERTADO por MCP nesse dia (migration `repasse_parceiro_preco_de_balcao_por_loja_2026_09_14`): coluna nova `restaurants.app_markup_pct` (0.10 Leonidas, 0.15 [[mister-kebab]]), `partner_store_share` passou a receber o restaurant_id e devolve subtotal ÷ (1+pct); lojas sem percentagem preenchida ficam na fórmula antiga. Prova: 93/93 e 47/47 produtos batem ao cêntimo; [[goola-acai]] não mudou nada; backup em `bkp_repasse_funcoes_20260914`.
- [stated] 01/10: decidiu passar a Leonidas a loja NÃO-PARCEIRA "por enquanto" (o estafeta compra ao balcão) e abri-la nesse dia; preço ao cliente = balcão + 15% (ex.: 1 € ao balcão → 1,15 € no app), substituindo o modelo de parceiro a balcão + 10%

