# Relatório — painel-aprovacoes-2026-11-18

Missão pedida pela Claude.ai com a autorização do Danilo (18/11/2026 20:29: "arrumar o botão de aceitar
que não tá funcionando… pedir documento em falta, eu clico e não faz nada"). Motor: Opus, Claude Code no PC.
Ramo de ensaio `ai/2026-11-18-painel-aprovacoes`, pedido de revisão #41, caixa 130 para a Claude.ai.

## O que estava partido

Fui ver o que o telemóvel do Danilo pediu ao servidor entre as 20:26 e as 20:37. Ele não estava no ecrã
"Comprovativo de atividade": estava em "Aprovações de Entregadores", na ficha da Shelen como estafeta.
Às 20:25 a Shelen tinha-se inscrito também como estafeta (a limpeza dela já estava aprovada desde as 20:10).

Primeiro problema: a ficha do estafeta não tinha botão para aprovar a pessoa. Só mostrava os documentos.
O botão de aprovar estava num ícone pequeno na lista e, como faltavam dois documentos (o número do documento
e a foto do veículo), abria uma janela "Faltam documentos" com o botão final cinzento até se escrever uma
justificação e marcar uma caixa. Tocar no botão cinzento não fazia nada e não dizia porquê. Nenhum pedido de
aprovação chegou ao servidor.

Segundo problema: o "Pedir documentos em falta" funcionava. Os três pedidos chegaram à app da Shelen (às
20:27, 20:28 e 20:37) e ela leu os dois primeiros. Mas a mensagem "Pedido enviado" aparecia por baixo da ficha,
escondida, e o Danilo achou que não tinha feito nada.

Terceiro: o erro 403 das 20:28:35 não era do painel. Veio de um telemóvel Android de outra pessoa. O telemóvel
do Danilo teve tudo certo nesse minuto. Não era a causa.

Quarto: quando faltava aprovar o comprovativo, a janela de aviso só tinha o botão "Entendi" — um beco sem
saída. E no ecrã "Comprovativo de atividade", o erro também ficava escondido por baixo da folha da pessoa, e
quando dava certo fechava o ecrã inteiro.

## O que se consertou

Todos os botões destes ecrãs mostram agora o resultado numa janela por cima de tudo: "Pedido enviado",
"Comprovativo aprovado", ou o erro em português.

A ficha do estafeta tem agora três botões: "Aprovar entregador", "Rejeitar" e "Aprovar mesmo assim (exceção
do admin)". O botão "Aprovar mesmo assim" já não fica cinzento: se faltar alguma coisa, diz o que falta.

A janela "Falta aprovar o comprovativo" tem agora "Ver comprovativo", "Aprovar comprovativo agora" (aprova e
segue logo para a aprovação da pessoa) e "Aprovar mesmo assim (exceção do admin)". Vale em Limpeza, Lavagem,
Papéis, Serviços e Estafetas. A ficha comum de limpeza, lavagem e Casa também tem o botão da exceção.

A exceção do admin pede o motivo (mínimo 10 letras), aprova e grava quem aprovou e porquê, no registo de
auditoria e no histórico do comprovativo. A regra do comprovativo obrigatório continua ligada para todos os
outros: a trava do servidor só abre para aquela pessoa, só para um admin, e só naquele momento. Assim não volta
a ser preciso aprovar ninguém à mão por SQL, como aconteceu com a Shelen.

Na app da pessoa (em PT-PT), o aviso "Faltam documentos" agora abre a lista do que falta, com um botão para
enviar cada documento — tanto no sino como ao tocar na notificação. Os avisos antigos também abrem.

## Onde se provou

A análise do código deu zero erros. Os testes automáticos passaram todos: 68, dos quais 15 novos desta missão.
A mudança do servidor foi provada numa cópia local da base de dados: 19 provas, nenhuma falhou. Entre elas: a
regra continua a travar quem não tem o comprovativo; quem não é admin não consegue usar a exceção nem pondo a
marca à mão; o motivo curto é recusado; a exceção aprova e grava o registo; logo a seguir, outra pessoa sem
comprovativo continua travada; estafeta, limpeza e prestador de serviços aprovam pela exceção.

Um revisor com olhos novos encontrou dois erros na minha primeira versão, e ambos foram corrigidos. O primeiro
era grave: os prestadores de serviços usam um número de ficha de outro tipo, e a exceção ia falhar para todos
os papéis. A minha primeira prova local não o apanhou, porque copiei mal esse tipo. Conferi o tipo na base real,
corrigi a migração e a prova, e corri a prova nova contra a versão antiga: falha com esse mesmo erro. A versão
nova passa. O segundo: tocar na notificação com a app fechada ou em segundo plano (no iPhone é sempre assim)
levava ao sino e não à lista do que falta. Agora leva diretamente à lista. A exceção também passou a aparecer
só em candidaturas pendentes. Quem está suspenso ou banido volta pelo caminho próprio da suspensão.

## O que ficou por fazer, e porquê

A mudança do servidor não foi aplicada por mim: a tranca do PC diz que aplicar migrações é publicar, e
publicar é da Claude.ai. Está na caixa 130, com o link fixo e a conferência do ficheiro. Sem ela, o painel novo
continua a funcionar: o pedido de documentos usa o caminho antigo, e o botão da exceção diz "ainda não foi
instalada no servidor".

Também não juntei o código no ramo de produção nem publiquei nas três lojas: a tranca não deixa e isso é da
Claude.ai (pedido de revisão #41). Por isso as provas ponta a ponta com cliques no painel publicado e a conta
de teste ficam para depois da publicação; a lista exata dos cliques está na caixa 130.

## Outros erros encontrados pelo caminho

A Shelen tem uma candidatura de estafeta pendente desde as 20:25 (falta o número do documento e a foto do
veículo). Não lhe toquei: é decisão do Danilo.

O ecrã "Estafetas em fila" mostrava erros crus em inglês ao marcar a atividade confirmada; passou a mostrar a
frase em português (mudança de uma linha).

A aprovação do comprovativo da Shelen às 20:10 foi feita por SQL e não deixou o evento no histórico do
comprovativo (só a data e o motivo). Fica reportado; não corrigi.

## Próximo passo

A Claude.ai aplica a migração, junta o pedido #41 (o CI publica Android, web e iPhone) e faz as provas com a
conta de teste pela lista da caixa 130.
