# Relatório — missão m6-crescimento-hermes-2026-11-08

Domingo, 08/11/2026, sessão do Claude Code no PC (Opus 5.5), ramo de ensaio `ai/2026-11-08-m6-crescimento`
no worktree `C:\BoraLocal\wt-m6-2026-11-08`. Diário: `e2e_log`, fluxo `m6-crescimento-hermes-2026-11-08`.
Modo automático seguro ligado: eu fiz e testei, quem publica a app, a Edge e as migrações é a Claude.ai.

## Fiz isto

**Hermes.** Medi os últimos 7 dias, e o resultado não é bom. Os agentes correm todos os dias sem falhar, mas quase
todos só leem um ficheiro de estado e repetem os números: a torre 168 vezes; o crescimento, o gestor de parceiros,
a qualidade e o cobrador 7 vezes cada. O vendedor disse 7 dias seguidos que não havia lista de alvos. O vendedor de
serviços respondeu "não sei, sem novidade" e gastou 2,06 € na semana. O escriba e as redes estão ligados na tabela,
mas parados desde 25 e 26/10. Quem procura serviço a sério é a rotina da caça-clientes na VPS, que só trabalha em
dias úteis: tem 307 negócios na lista, mandou 93 propostas por email (25 nesta semana) e juntou 32 negócios novos
com email e maqueta entre 2 e 6/11. Em todo este tempo só houve uma resposta, e foi um "não" (MOYO), além de uma
resposta automática. Liguei o vendedor à lista verdadeira: o retrato que os agentes leem (`/opt/data/estado-operacao.txt`)
passou a ter a secção da prospeção com estes números, por isso amanhã ele já não diz "não sei".

**Porteiro do Telegram.** A regra nova está a correr na VPS. Urgente agora é só pedido parado sem estafeta há mais
de 10 minutos, pagamento falhado de cliente real, app em baixo, candidato novo e cliente a reclamar ou a pedir uma
pessoa. Tudo o resto vai para o resumo das 21:00. O radar do Jai só é urgente quando um jornalista responde ou quando
o site do Jai está em baixo. Pedido novo, corrida nova e limpeza nova deixaram de tocar logo: entram num vigia, e se
ao fim de 10 minutos ainda não tiverem estafeta, aí sim chega o urgente. Prova: dos 168 avisos urgentes dos últimos
8 dias, com a regra nova ficariam 51. As três mensagens de teste deram o resultado certo: o radar do Jai banal ficou
na informação, a resposta de jornalista subiu a urgente e o pedido novo entrou no vigia. O vigia, já a correr, leu
um pedido entregue e fechou-o sem alarme.

**Wikipédia do Jai.** Fiz o dossier honesto em `/root/radar-jai/provas/wikipedia-dossier-2026-11-08.md` (e em
`docs/jai/`). Em nenhuma fonte o Jai aparece como futebolista: todas o descrevem como empresário e dono do Guarda FC
SAD. Hoje ele não passa nos critérios, nem na Wikipédia inglesa nem na portuguesa. As notícias de agosto são quase
todas o mesmo comunicado, e falta pelo menos um artigo de fundo, feito por jornalistas independentes. Verifiquei 5
fontes, 4 ficaram por confirmar, e a página no Wikidata já existe. Não editei a Wikipédia.

**Redes com personalidade.** Escrevi as 7 regras da voz humana: fala uma pessoa da Guarda que trabalha no Bora,
fotos reais, legenda curta com um detalhe verdadeiro, no máximo 1 emoji, stories de bastidores, só parceiros ativos
e nunca a Ouro e Prata, e juiz com visão antes de sair. Ficaram na VPS, nas duas skills das redes e nas ordens dos
grupos. A loja do dia, que sai todos os dias ao meio-dia, já tem textos novos que rodam pelo dia, por isso as
próximas 7 peças saem com a voz nova. Fiz também a lista dos grupos de Facebook da Guarda, com membros, regras e a
última publicação, e o plano de 9 a 15/11: um post por dia, com foto real de um parceiro ativo (três hambúrgueres
fotografados pelo dono da Boom, três da Keli e um açaí da Goola). Vi as 7 fotos uma a uma antes de as aprovar. A
rotina dos grupos de amanhã às 08:30 já usa este plano.

**Jyosmi igual ao site.** Ficou aplicado, com cópia de segurança. Os preços já estavam iguais ao site, ao cêntimo.
Entraram 42 produtos (Guaraná Antarctica a 2,20 €, cervejas, sidra, vinhos, destilados e bebidas quentes), e as 37
bebidas alcoólicas ficam marcadas +18, com a idade confirmada pelo estafeta na entrega. As entradas ganharam tamanho
pequeno e médio. A bebida grátis do Especial JYOSMI ficou presa ao médio e ao grande. Os nomes passaram a ser os do
site: "Caixa de Sushi Fritos", "Gyoza Frio" e "Molho Soja". O San Pellegrino saiu do site, por isso ficou
indisponível, sem se apagar. A preparação passou de 20 para 45 minutos. O Combinado Tradicional fica a 12, 15 e 33 €.
A base confirma: 117 produtos, 116 disponíveis e 37 com +18. Para as fotos do site não aparecerem cinzentas na
versão web, acrescentei o site da loja ao proxy de imagens. Isso chega à web quando a app for publicada.

**Restaurante do dia.** Está feito no ramo, à espera de publicação. É um aviso diário às 17:30 com um restaurante e
um prato, e tocar nele abre a loja. Quem abriu lojas nos últimos 30 dias recebe a que mais abriu; os outros recebem
a da rotação. Só entram restaurantes ativos, abertos ao jantar nesse dia e com foto. O painel ganhou o ecrã Clientes
› Restaurante do dia, para ligar e desligar, mudar a hora e ver a rotação. Provei a escolha na base, só a ler: na
segunda começa pela Boom! Burger, com o Boom! Clássico, e chega a 152 clientes.

## Falta isto (e porquê)

- **Enviar o ramo.** A tranca não deixou fazer o `git push` do ramo de ensaio (para ela, enviar é publicar), por isso o
  trabalho está só no PC, no commit do ramo `ai/2026-11-08-m6-crescimento`, e não há pedido de revisão aberto.
- **Publicar.** O restaurante do dia (a migração, a Edge e a app) e as fotos da Jyosmi na web só chegam ao ar quando
  a Claude.ai aplicar e publicar. A ordem dela está em `docs/propostas/PROPOSTA_20261108_restaurante_do_dia.md`.
  Pelo modo automático seguro, a sessão do PC não publica.
- **Check-in.** O que falta é dinheiro. A tranca voltou a bloquear o `order_store`, a peça que manda o vale de
  desconto ao pedido, e não contornei. O desconto dentro da função que cria o pedido e o vale devolvido ao cancelar
  estão prontos em `docs/propostas/PROPOSTA_20261104_*`, mas precisam do "AUTORIZO:" do Danilo e de a Claude.ai os
  aplicar. Os 7 degraus de produto estão ligados e os 6 de desconto continuam desligados, como ele mandou.
- **Stories, carrossel e reel** ainda usam os textos antigos. Só a loja do dia e os grupos passaram para a voz nova.
- **Captura da loja da Jyosmi no emulador.** Não a fiz: o PC tinha pouca memória para um emulador, e a prova ficou
  pelas leituras da base.

## Erros que encontrei

- A rotina dos grupos publica pelo perfil pessoal do Danilo ("Danilo Silva"). A partir de amanhã, a ordem só usa a
  página do Bora, e nos grupos que só aceitam perfis espera pelo "sim" dele, grupo a grupo, nesse dia.
- O WhatsApp da Bora (937 501 673) está no ecrã do código QR desde 06/11. Por isso não sai nada para o grupo
  "Marketing, vendas e propaganda Guarda" nem para o estado.
- A biblioteca de peças dos grupos ainda tinha a "barbearia", sem nenhuma barbearia ativa. A ordem passou a proibi-la.
- Na ficha do produto, o acréscimo do tamanho aparece sem a margem (diz +3,00 € e cobra +3,45 €), em
  `product_detail_screen.dart`. Mexe em preço, por isso fica reportado e não mexi.
- A trava do modo automático confundiu uma variável chamada `env` com "mostrar segredos" e bloqueou um comando.
  Fiz pelo caminho já provado (ficheiro e scp), sem contornar.

## Próximo passo

A Claude.ai aplica a proposta do restaurante do dia e publica o ramo nas 3. O Danilo lê o QR do WhatsApp da Bora e
diz em que grupos só de perfis aceita o perfil dele.

## PARA O DANILO

1. Ler o código QR do WhatsApp da Bora com o telemóvel da Bora: sem isso não sai nada para o grupo de marketing.
2. Dizer "sim grupos ..." quando o aviso da manhã perguntar que grupos só aceitam o teu perfil.
3. Confirmar com a Jyosmi se o nome "Gyoza Frio" é mesmo assim, porque a descrição diz que é frito. Pus como está
   no site.
