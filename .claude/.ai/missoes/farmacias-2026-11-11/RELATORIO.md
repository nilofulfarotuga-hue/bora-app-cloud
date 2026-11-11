# Relatório — farmacias-2026-11-11 (Farmácia da Sé e Farmácia Teixeira)

Acessos: contas do Danilo boraappbora@gmail.com e nilofulfarotuga@gmail.com (as únicas que veem as farmácias).
Criei nesta sessão duas contas de parceiro de demonstração, demo.farmacia.se@bora.app e
demo.farmacia.teixeira@bora.app; as palavras-passe estão só no ficheiro farmacias-logins-demonstracao.txt na
pasta Bora do Ambiente de Trabalho. Pedido de revisão:
https://github.com/nilofulfarotuga-hue/bora-app-cloud/pull/11 (ramo ai/2026-11-11-farmacias).

## O que não ficou feito, logo à cabeça

A trava do modo automático deste PC não me deixa mexer na estrutura do servidor nem publicar: diz "publica a
Claude.ai". Por isso o servidor das farmácias (6 migrações e uma função) e a app estão prontos e testados, mas
ainda não estão no ar. Falta a Claude.ai aplicar as migrações pela ordem do guia e juntar o pedido #11, o que
publica Android, iPhone e web. Pedi-o no livro (página pedido-claude-ai-farmacias-2026-11-11-servidor) e mandei
mensagem ao Danilo no Telegram. Também não consegui lançar os agentes de design e de apps em paralelo: o
classificador do modo automático recusou-os por causa de um gancho do context-mode; fiz esse trabalho nesta sessão.

## Fiz isto

Criei as duas lojas na base, escondidas (ninguém as vê até o servidor novo ser aplicado), com morada, telefone,
horário, coordenadas, logótipo e capa reais, confirmados em várias fontes públicas (Farmácias Portuguesas, Google,
OpenStreetMap, Glovo, Facebook). Não gravei o email verdadeiro das farmácias de propósito: o resumo mensal
automático escreveria para elas.

Escrevi o servidor: lista de permissão por loja (só as contas do Danilo, os donos de demonstração e o admin veem as
farmácias, em todo o lado: categoria, pesquisa, faixas, link direto, Amigo e robôs das redes); modo demonstração
(nestas lojas só entram pedidos de teste em dinheiro, nenhum estafeta real é chamado e nada é cobrado); o pedido
com receita e o pedido especial (a farmácia aceita com o valor, aceita em parte ou recusa com motivo; lembrete à
farmácia aos 15 minutos e expiração aos 30; fotos e códigos num cofre privado e apagados 30 dias depois); o
lembrete mensal que só avisa; e o painel admin. Provei tudo num Postgres local: 65 verificações certas, zero falhas.

Escrevi a app: no topo da farmácia, os botões "Tenho receita", "Não encontra o produto? Peça aqui" e "Repetir todos
os meses"; o envio da receita por foto ou por número e códigos, com a autorização lida e assinada com o dedo; o ecrã
que mostra a resposta da farmácia em segundos, com o valor, a taxa e o total, e a escolha entre cartão, MB Way e
dinheiro; no painel da farmácia, um cartão no topo dos pedidos que toca sem parar enquanto houver receitas por
responder, e o detalhe com os botões grandes "Tenho, aceito" e "Não tenho"; os avisos no telemóvel; e no painel
admin os ecrãs Farmácias e Pedidos de receita. Os testes novos passam (13) e os vizinhos também (38).

A comissão: as duas farmácias ficam com 10 % de comissão extra a contar só a partir da data de abertura mais 3
meses; antes disso zero. A peça que desconta os 10 % no fecho semanal mexe em dinheiro, por isso ficou como
proposta, pronta, para aplicar quando abrirem (não é precisa na sexta, porque os pedidos de demonstração não
entram em fechos).

## Catálogo

Encontrei as duas na Glovo da Guarda (Sé: loja 461279; Teixeira: loja 461596). A Farmácia da Sé tem lá 872
produtos e a Teixeira 515. Entram 867 e 511: os 9 que faltam (5 da Sé e 4 da Teixeira) não têm foto na própria
Glovo, só um quadro "imagem indisponível", e ficaram de fora para não haver produtos sem foto. Todas as fotos estão
no nosso Storage, provadas uma a uma (resposta 200 e os mesmos bytes). Arrumei os produtos em 16 secções de
farmácia (Medicamentos sem receita, Dor e febre, Constipação e alergias, Bebé e mamã, Dermocosmética, Solares...),
marquei 115 medicamentos na Sé e 99 na Teixeira, e limpei 66 nomes que traziam a lista de ingredientes colada.
O preço que o cliente vê é exatamente o da Glovo, marcado como provisório até chegar o preço de balcão. A carga só
entra depois de o servidor novo estar no ar, porque a pesquisa geral mostraria os produtos a toda a gente.

## Erros que encontrei fora da missão (não corrigi)

O painel do parceiro não mostra pedidos de loja (como farmácias e mercados parceiros), só de restaurante: o filtro
está em order_store.dart, que é zona trancada. Antes de abrir as farmácias ao público é preciso esse remendo.
As fotos da Wells estão ligadas ao site da Glovo e não ao nosso Storage. O ramo de produção no PC principal estava
659 envios atrás do servidor; trabalhei numa cópia limpa.

## Decisões que ficaram por defeito, à espera do Danilo

A base dos 10 % é o que a farmácia recebe pelo produto. O pedido especial paga a mesma taxa do serviço que a receita
(6 €). O estafeta ganha 5 € por levantamento de receita, igual ao Favor normal. O pedido real de receita (estafeta e
cobrança) numa farmácia aberta ao público ainda não está ligado: para já responde "levantar na farmácia". Os ecrãs
novos estão só em português. O horário da Sé ficou às 09:00 (o Google diz 08:30, a ANF diz 09:00).

## Próximo passo

A Claude.ai aplica o servidor e junta o pedido #11; eu carrego o catálogo, provo com uma terceira conta que não vê
nada, faço as três contas de preço e as capturas, e deixo o guião da demonstração pronto (GUIAO-DEMONSTRACAO.md).
