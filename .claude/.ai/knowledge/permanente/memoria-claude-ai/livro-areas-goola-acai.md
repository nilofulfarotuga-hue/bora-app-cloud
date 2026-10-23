---
id: memoria-claude-ai-livro-areas-goola-acai
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Goola Açaí (quiosque no La Vie Guarda) — parceiro fechado do Bora App; modelo de preço acordado, loja montada e categoria nova "Sobremesas"

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-goola-acai`, origem `claude-ai`, atualizada em 2026-10-23T05:39:25.793428+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas goola acai · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/goola-acai.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: goola-acai
description: Goola Açaí (quiosque no La Vie Guarda) — parceiro fechado do Bora App; modelo de preço acordado, loja montada e categoria nova "Sobremesas"
sources: [chat]
aliases: [Goola, Goola Açaí, quiosque de açaí do La Vie, açaí do shopping]
---

- [stated] 2026-08-27: o dono do quiosque Goola Açaí, no shopping La Vie da Guarda, procurou o Danilo para entrar no [[bora-app]] e passar a fazer entregas. Danilo confirmou que é essa loja e perguntou se dava para ficar pronto no próprio dia.
- [stated] A loja dele ainda NÃO está na Uber nem na Glovo; vai entrar na Uber e no Bora. Correção do Danilo: a Guarda JÁ tem Uber e Glovo a operar (não é praça sem concorrência).
- [stated] Mesmo esquema das outras lojas ([[mister-kebab]], [[ouro-e-prata]], [[sabores-de-casa]]): montar a loja no app + site especial de presente. Desta vez Danilo quer TUDO numa ordem só, aproveitando o que já funciona.
- [stated] Por ser franquia, Danilo autoriza puxar tudo da internet — fotos, textos e material da marca — sem pedir nada à mão ao dono.
- [stated] Ainda em falta do dono: fotos, lista completa de toppings e os preços praticados no quiosque. Danilo mandou fazer só a pesquisa primeiro, sem disparar prompt.

Dados enviados pelo dono (2026-08-27, por WhatsApp)
- [stated] Preços: Goola Bowl (3 acompanhamentos) 8,90 · Big Bowl (4 acompanhamentos) 10,90. Horário do quiosque 10:00-22:00.
- [stated] Toppings grátis: banana, morango, kiwi, manga, chips de coco, coco ralado, granola tradicional, aveia em flocos, leite Nido, mix de nuts, iogurte grego, muesli, manteiga de amendoim, amendoim, mel, creme de avelã, leite condensado.
- [stated] Toppings extra a 1,00 €: Oreo, paçoca, whey protein.
- [stated] RESOLVIDO (27/08): o dono respondeu que 8,90/10,90 já levam 1,00 € posto por ele — o preço de BALCÃO é 7,90 (Goola Bowl) e 9,90 (Big Bowl). Nota: 8,90/10,90 é também a tabela nacional da Goola no Uber Eats (Lisboa, Porto, Montijo).
- [stated] MODELO FECHADO com o dono (27/08): prefere vender ao preço de balcão, 7,90 e 9,90, faturando só isso, como uma venda normal de loja. Razão dele: se o euro extra passasse pela faturação, pagava imposto e royalty à franquia sobre dinheiro que não é lucro dele. A parte do Bora vai por cima, cobrada ao cliente, fora da fatura da loja. Extras ficam a 1,00 € para ele. O dono disse que assim compensa e mandou dar seguimento.
- [stated] POR DECIDIR (Danilo): gravar o preço que faz o acerto cair nos 7,90/9,90 exatos, ou ficar colado ao preço do Uber e receber menos.
- [stated] REGRA DESTA LOJA (Danilo, corrigindo-me): quem decide se a comissão vai por cima do preço é O PARCEIRO, não o Danilo — é a margem dele. Ou manda o valor já com a comissão incluída (e o Danilo grava tal como veio, sem somar nada), ou deixa o preço de balcão e a comissão sai da margem dele. Diferente do [[mister-kebab]], onde foi o Danilo quem impôs o balcão+15%.
- [stated] Dúvida fiscal levantada pelo dono (tem de faturar à franquia e às Finanças): resposta acordada — a venda continua dele, ele fatura o produto ao cliente e declara o seu valor; o Bora não compra nem revende; comissão e entrega são faturadas à parte pelo Danilo, com acerto semanal e extrato. Alinhado com [[faturacao-fiscal]], que continua à espera da resposta da contabilista.

Loja montada e ordem disparada (2026-08-27)
- [stated] DECISÃO DE PREÇO FECHADA: gravar o valor que faz o acerto cair nos 7,90/9,90 exatos, em vez de ficar colado ao Uber. Preço no app 9,22 (Goola Bowl) e 11,55 (Big Bowl); extras a 1,17. Fórmula desta loja: preço gravado = balcão ÷ 0,90 × 1,05, com o balcão guardado em `products.partner_shelf_price` como fonte de verdade para recálculos. Verificado por SQL: o parceiro recebe 7,90 e 9,90 certinhos, e 1,00 nos extras.
- [stated] Loja criada por MCP: `restaurants.id='goola-acai-guarda'`, parceiro, approved, `coming_soon=true` até o dono confirmar, horário 10-22h todos os dias, morada do quiosque no piso 3 do La Vie, redes nacionais da marca ligadas. 2 produtos, 4 grupos de opções, 40 itens.
- [stated] Continua em falta do dono: NIF, IBAN, telefone da loja, e-mail, fotos próprias do quiosque, e confirmar se vende o pote de 1 litro.
- [stated] Prompt único entregue no chat como ficheiro (motor OPUS, Claude Code no PC): loja no app + taxa de pedido pequeno + painel admin + mini-site de presente. A proposta que tinha ido parar à Central do Córtex fica sem efeito, este prompt substitui-a.

Categoria nova "Sobremesas" (2026-08-27)
- [stated] Danilo mandou criar uma CATEGORIA NOVA no [[bora-app]] para a Goola, e pediu-me para escolher o nome (hesitava entre sobremesa e gelataria). Escolhido e aceite: nome ao cliente "Sobremesas" (PT-PT, é o termo do Uber Eats em Portugal e cabe lá gelados, bolos e crepes depois), slug técnico `sobremesa`.
- [stated] A Goola fica visível em DUAS categorias ao mesmo tempo — Sobremesas e Restaurantes — pelo mesmo esquema do [[sabores-de-casa]] (coluna `extra_categories`), e NÃO no esquema exclusivo da categoria Festas em [[encomendas-festa]]. Já aplicado por MCP: `extra_categories={sobremesa}` com `category='restaurant'` como principal. Falta só a categoria existir na app (hoje só há Restaurantes, Mercados, Lojas, Farmácias e Festas).
- [stated] O fluxo de compra dentro de Sobremesas é o normal de delivery — pedido imediato, sem calendário nem aceitar-com-tempo; a categoria é só mais um filtro visual.
- [stated] Adendo entregue como texto para colar na sessão do Claude Code já aberta (o prompt principal já tinha sido enviado por ele).

Loja ABERTA (2026-08-28)
- [stated] Danilo mandou tirar o "Em breve" e foi EXECUTADO por MCP: `coming_soon=false`, `is_online=true`, `is_active_admin=true`, `approval_status='approved'`. A Goola Açaí está a receber pedidos reais, todos os dias das 10h às 22h. Site de presente no ar em `goola.boraguarda.com`, com vídeo e com o texto corrigido a pedido do dono (3 e 4 acompanhamentos à escolha de 17, em vez de "os que quiseres"). Conta de parceiro `goola@bora.app` criada e ligada à loja.
- [stated] Continua em falta do dono: NIF, IBAN, telefone da loja, e-mail e fotos próprias do quiosque. Confirmado por ele que NÃO vende o pote de 1 litro.

Autocolantes (2026-09-03)
- [stated] O dono do Goola pediu autocolantes. Danilo quer o mesmo esquema dos QR do Gilberto/Mr Kebab (2 QR: web + Play Store) em autocolantes de vários tamanhos e formatos (redondos etc.) com "aqui pedes pelo Bora App", mais uma versão genérica só do Bora para qualquer loja. CORREÇÃO dele no mesmo dia: quer DUAS coisas — (1) um CARTAZ do Goola para plastificar, no mesmo estilo cinema dos cartazes do Mr Kebab e do Gilberto (gerado por Gemini/ChatGPT, QR reais colados por cima), e (2) autocolantes redondos só do Bora em vários tamanhos. PROMPT REGISTADO (versão corrigida, mesmo nome): `PROMPT_autocolantes_bora_2026-09-03.md`, MOTOR OPUS, janela Pro, sessão `cartaz-e-autocolantes-goola`. Estado: CORREU 03/09 — material em `C:\Users\danil\Desktop\Bora\goola-material\` (cartaz A3 300 dpi + versão WhatsApp; autocolantes Ø5/Ø8/Ø12/Ø12 co-branded Goola+Bora/10×15 em PDF de gráfica + 2 folhas A4 à escala real), QR todos provados por `verificar_cartaz.py`; ecrãs reais capturados do web app com preços verdadeiros. MAS o cartaz saiu por script, plano, NÃO no estilo cinema pedido (executor não usou o Gemini web porque a ferramenta de clique pediu para escolher entre os 2 Chromes) — continuação entregue como texto: escolher o Chrome do perfil boraappbora e gerar o fundo em gemini.google.com/chatgpt.com, remontar por cima. Segunda volta 03/09: o executor refez o cartaz "em estilo cinema" mas por script, com a foto real do quiosque — o Danilo REPROVOU ("horrível"): o cartaz TEM de ser gerado por IA (Gemini/ChatGPT pelo clique), nunca montado à mão. No Chrome do perfil boraappbora o Gemini pedia aceitação de termos e o ChatGPT estava sem sessão; ele sentou-se ao PC para confirmar o que aparecesse. Os 4 cartazes de referência (Mr Kebab, Gilberto e 2 com o logo do Bora) foram descarregados por ele para `C:\Users\danil\Downloads` a 03/09 — já existem no disco. Quantidades sugeridas para a gráfica (por confirmar com ele e com o dono do Goola sobre o co-branded na porta): 20×Ø5, 5×Ø8, 3×Ø12 Bora, 2×Ø12 Goola+Bora

Dados do dono e troca de login (2026-09-06)
- [stated] O dono entregou finalmente os dados que faltavam: email goolaguarda2443@gmail.com e telemóvel/MB Way 911519501, mais os dados fiscais e de pagamento (guardados na ficha da loja no Supabase, não aqui). Danilo mandou trocar o email da conta de parceiro e guardar tudo.
- [stated] FEITO por MCP (Claude.ai, sem executor): a ficha `restaurants.goola-acai-guarda` ficou completa — contactos, dados fiscais e de pagamento, todos validados. O login do parceiro passou de goola@bora.app para goolaguarda2443@gmail.com em auth.users + auth.identities + users, com senha nova temporária `[REMOVIDO]` para o Danilo passar ao dono e o dono trocar depois.
- [stated] LIMITE DO SUPABASE a lembrar: só existe UM email de login por conta — não dá para deixar o antigo e o novo a funcionar ao mesmo tempo. A troca por SQL não derruba a sessão que o dono já tem aberta na app, por isso ninguém fica de fora.
- [stated] O dono ainda não faturou nada porque ficou na dúvida entre faturar o preço normal dele ou o preço que aparece no app; Danilo pediu a explicação por escrito para lhe passar. Vale o modelo já fechado em 27/08: ele fatura só o balcão (7,90 / 9,90 / 1,00 nos extras), a parte da Bora vai por cima e nunca entra na caixa dele.

