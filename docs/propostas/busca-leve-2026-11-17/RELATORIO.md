# Relatório — servidor-busca-leve-2026-11-17

17/11/2026, Claude Code no PC (Opus 5.5). Registo passo a passo: `e2e_log`, fluxo `servidor-busca-leve-2026-11-17`.

**O que NÃO ficou feito, primeiro.** O teste com 100 pessoas não correu, porque com 10 a lupa
dentro das lojas, para quem não tem login, ainda custa uns 600 ms de servidor por pesquisa; com 100
o servidor ficava a trabalhar ao dobro do que aguenta. A causa está achada e explicada abaixo, mas o
conserto não foi feito: mexe na maneira como a pesquisa respeita as regras de quem vê o quê, e isso
merece uma missão própria com prova. Também ficam por aplicar no servidor duas peças pequenas que
preparei: tirar o índice repetido e o aviso do vigia em português de gente. A app nova (a lupa que
espera) está no pedido de revisão #33, com o CI a correr; publicar nas três lojas é da Claude.ai,
porque a trava não me deixa juntar nem publicar.

**Fiz isto.** Medi tudo antes de mexer. Achei onde o tempo ia: refazer o nome de cada produto com
doze contas em cada pesquisa, e voltar a planear a pesquisa inteira em cada chamada. Preparei o
servidor novo: os nomes já arrumados ficam guardados numa tabela à parte, com uma verificação que
calcula na hora se o nome mudou (por isso o resultado nunca muda), e as secções vêm de uma lista
pequena em vez de olhar para 51 mil produtos. Provei com 444 pesquisas, antes de aplicar, que dão
exatamente os mesmos produtos pela mesma ordem, até com metade das linhas estragadas de propósito.
A Claude.ai aplicou às 08:22-08:26 e eu voltei a provar já no ar: 60 de 60 iguais, e 20 de 20 iguais
para quem não tem login. Cada pesquisa ficou cerca de duas vezes mais rápida: em todas as lojas
"frango" de 401 para 217 ms, "car" de 318 para 139, "leite" de 91 para 38; no Continente "leite" de 56
para 24 ms. Com 2 letras ("pa", "co") passou de 35 ms para menos de 7.

Achei e preparei também a lupa da página inicial: ela não usava a pesquisa das lojas, chamava outra
função que ainda procurava produtos com 2 letras, a parte mais pesada de todas (3,7 s por "pa"). A
Claude.ai já a aplicou: agora com 2 letras só aparecem lojas.

Na app, as três lupas (página inicial, dentro da loja e menu do restaurante) só perguntam ao servidor
quando a pessoa pára de escrever 400 ms, uma resposta atrasada já não tapa a mais nova, a mesma
pesquisa nos últimos 5 minutos vem do telemóvel, e dois toques no "pesquisar" fazem um pedido só. O
menu do restaurante deixou de dizer "não encontrei" com 2 letras. Há 28 testes novos e o Juiz deu limpo.

O teste de carga com 10 pessoas sem login, já com o servidor novo, correu os 3 minutos sem um único
erro: 347 pedidos, metade abaixo de 189 ms. A lupa da página inicial ficou ótima (metade abaixo de
128 ms). A lupa dentro das lojas ficou lenta para quem não tem login (metade perto de 1 s).

**Erros que encontrei.** O principal: para quem pesquisa sem login (os robôs da Google e qualquer
cliente antes de entrar), as regras de leitura dos produtos impedem o Postgres de usar o índice da
pesquisa, e ele lê os 63 mil produtos um a um. Medido: "leite" no Continente 24 ms como dono e 207 ms
sem login. Já era assim antes de hoje e é a razão principal dos 730 ms dos robôs. Os outros: a
migração de 15/11 (checkup_b24) foi aplicada a partir de uma resposta da internet e não tinha ficheiro
no repo; o Juiz, sem dizer a base, compara com o ramo main e rejeita por ficheiros de outros; a lupa
do menu dizia "não encontrei" com 2 letras desde as 06:51. Durante o meu teste a Claude.ai fazia a
comparação dela pelo navegador deste PC, por isso o vigia das 08:32 marcou 97,7% (sem alarme).

**Próximo passo.** Uma missão curta para a pesquisa correr como dono do servidor com as mesmas regras
de quem vê o quê aplicadas à mão (como a lupa da página inicial já faz), provada igual para quem não
tem login, cliente, admin e robôs. Pelas medidas, a lupa da loja sem login cai de ~600 para ~100 ms,
e aí sim corre-se o teste das 100 pessoas (o script já está pronto). Depois: aplicar o índice e o
vigia, juntar o #33 com o CI verde e publicar nas três. Não mexi no plano do Supabase.
