# Estafeta lento + preço de balcão — 14/11/2026

Missão estafeta-lento-14-11 (motor Opus 5.5, Claude Code no PC). Registo passo a passo no e2e_log, fluxo estafeta-lento-14-11.

## Fiz isto

A lentidão veio da própria app, não do servidor. Na ligação entre as peças da app (main.dart), sempre que o GPS do estafeta mudava de posição, ou qualquer outra coisa do estafeta ou da loja mexia, a app ia buscar de novo TODOS os pedidos que consegue ver (64 pedidos, cerca de 330 kB de cada vez). Foi por isso que o teu telemóvel fez 309 desses pedidos em 12 minutos, com picos de 60 por minuto às 18:26 e 56 às 18:28. Agora essa recarga só acontece quando a conta muda (entrar, sair, trocar de conta). As outras recargas que fazem sentido continuam: abrir o ecrã, voltar à app, aviso de pedido atribuído e erro numa ação.

O cartão laranja "TENS DE FAZER A COMPRA" e a lista de compras não contavam o preço das opções. No pedido da Bruna no Jyosmi Sushi mostrava 23,00 € quando o balcão era 46,00 €. Agora há uma conta só, igual em todo o lado: preço base mais o extra de cada opção, vezes a quantidade. O cartão laranja diz 46,00 €. A lista diz 13,00 € e 33,00 € à direita, a linha da opção diz só "Tamanho: Média (18 peças)", e no topo aparece "Total a pagar na caixa: 46,00 €". No ecrã do talão aparece "Valor estimado: 46,00 €" por baixo do campo. A conta do servidor não mudou.

## Falta isto (e porquê)

A tranca não me deixou mexer no ficheiro dos pedidos (order_store.dart, zona vermelha por causa do finalizePurchase). Por isso ficou por fazer o que só se faz lá dentro: o estafeta buscar só os pedidos ativos dele e as ofertas (em vez dos 64), um só pedido em voo de cada vez, e o histórico às páginas de 20. Já não se repete sem parar, mas cada vez que recarrega ainda traz a lista inteira. Para fazer isso é preciso abrir a tranca para esse ficheiro.

A medida no emulador não foi feita: o emulador precisa de 3 GB livres e o PC tinha entre 550 e 730 MB. A medida "depois" faz-se pelos registos do Supabase quando o build novo chegar aos telemóveis.

## Erros que encontrei (só reportados, não corrigidos)

1. Quando o estafeta marca as compras, a app regrava os itens sem o preço das opções (17 linhas nos últimos 60 dias). Depois disso a conta de balcão volta a não ter as opções. Está na zona vermelha e o servidor usa esse campo nos talões, por isso não lhe toquei.
2. Às 18:19 a app saiu de duas contas no mesmo segundo (a demo e a tua de estafeta). Sem conta, inventou o id "driver-351931992662" a partir do telefone (driver_store.dart linha 285) e tentou atualizar o estafeta com ele, o que deu erro até voltares a entrar às 18:19:55.
3. Às 18:30 o Supabase ficou sem ligações livres por momentos. Não tem relação provada com a rajada: no pico das 18:26 não houve erro, e às 18:30 só havia 10 pedidos por minuto.
4. Às 18:02 o catálogo do Continente falhou por demorar demais. A app carrega a loja inteira, mais de 17 mil produtos, às páginas de mil (restaurant_store.dart linha 154).
5. Às 18:19:57 o registo do aviso no telemóvel falhou porque a app manda o papel "handyman" e o servidor não o aceita. Apareceram também "permission denied" em funções chamadas sem conta, e uma consulta a uma coluna "created_at" que não existe.

## Próximo passo

Abrir a tranca para o order_store.dart e fazer a parte que falta, depois medir pelos registos do Supabase com o build novo.
