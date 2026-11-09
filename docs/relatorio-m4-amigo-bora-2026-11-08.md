# Relatório — Amigo Bora v1 e adendo do suporte (08/11/2026)

Missão `m4-amigo-bora-v1-2026-11-08` e adendo `m4-adendo1-suporte-conversa-2026-11-08`. Sessão do PC
(Claude Code, Opus 5.5), worktree `C:/BoraLocal/wt-m4-2026-11-08`, ramo de ensaio `ai/2026-11-08-m4-amigo-bora`.

## Fiz isto

Primeiro medi o assistente que já existia. Nos últimos 30 dias houve 26 conversas (13 de clientes de
verdade, 13 de testes e do Danilo), 7 clientes, 37 mensagens de clientes, 67 carrinhos propostos, 9
abertos e 2 que viraram pedido. O custo foi de 0,58 dólares: 58 chamadas ao Sonnet a 0,00995 dólares
cada, em média. A memória por cliente estava vazia (0 linhas). A função que está no ar é igual à do
repositório.

O Amigo Bora ficou pronto no ramo. Na home há agora uma entrada só: um botão redondo "Ajuda-me a
escolher" por baixo da barra de pesquisa, com um avatar novo (uma bolha de conversa verde com três
pontos laranja e uma faísca, sem rosto). Na primeira vez aparece um cartão de duas linhas, "Sou o Amigo
Bora. Sei o que há na Guarda e o que costumas pedir. Pergunta-me o que quiseres.", com "Agora não", que
esconde o cartão e deixa o botão. O botão flutuante verde do assistente saiu dos cinco ecrãs onde
estava; fica só o botão laranja do suporte. A faixa fixa "Novidade: Bora Assistente" sai da home quando
a migração for aplicada (fica uma cópia). Há uma definição nova no painel para ligar e desligar a
personalidade sem desligar o assistente.

Cada cliente passa a ter uma memória curta: as lojas favoritas, o que pede muitas vezes, os hábitos
("sexta à noite: Jyosmi"), o ticket médio, as categorias que usa (restaurantes, mercado, Favores,
limpeza), as restrições que disse e o nome como gosta de ser tratado. A parte dos pedidos é calculada no
banco, sem custo; a parte da conversa só usa o modelo barato quando o cliente escreveu pelo menos três
mensagens novas. Uma rotina de hora a hora refresca quem teve pedido entregue ou conversa nova, e os
outros uma vez por dia. Nunca guarda dados de pagamento, telefones, emails ou moradas. No Perfil, o
cartão passa a "O que o Amigo Bora sabe de mim", com o resumo em frases, um interruptor para o Amigo não
se lembrar e "Esquecer tudo" (junta-se à memória que já existia, não duplica).

Os três truques estão feitos. Repetir o habitual: ao abrir na sexta ao fim da tarde, se o cliente
costuma pedir ao Jyosmi às sextas, o Amigo diz "Hoje é sexta. Queres o do costume do Jyosmi? Tenho o teu
último pedido pronto para repetir." e o botão "Sim, repete" enche o carrinho e vai para o pagamento
normal; esta saudação não gasta modelo nem a quota do cliente. Conversa vira carrinho: quando o cliente
quer comprar ou marcar alguma coisa, a resposta acaba sempre numa ação (carrinho, Favor já preenchido
ou a marcação de limpeza); se o modelo se esquecer, o servidor obriga-o a mais uma volta. Comparar com a
Glovo e a Uber: com o print (agora lido com o preço de cada linha) ou com os preços escritos pelo
cliente, a conta é feita em código, linha a linha, nos dois sentidos ("só esse artigo, na Glovo fica 0,40
€ mais barato; com os 3 artigos, no Bora poupas 2,10 €, já com a entrega"); sem print nem preços pede o
print e nunca inventa preço da outra app. Cada comparação fica guardada para o painel.

A deixa: no fim de uma conversa livre (nunca em compras, comparações, fotos ou ajuda) aparece uma linha
tocável com uma coisa útil: tokens a expirar nos próximos 7 dias, check-in por fazer, um parceiro novo dos
últimos 14 dias ou uma promoção da home. É escolhida e escrita pelo servidor, uma por resposta, e a mesma
não se repete em 24 horas. Cada deixa mostrada e clicada fica contada.

A personalidade é de um amigo da Guarda, em português de Portugal, com frases curtas, no máximo um emoji,
humor leve, sem política, religião ou saúde, sem prometer prazos nem preços fora das ferramentas, e com
"Isso não sei, mas posso perguntar à equipa" quando não sabe. A conversa livre vai para o modelo pequeno
(Haiku); o cesto e as fotos ficam no modelo de sempre. A voz de entrada já existia; a app não tem leitura
em voz alta, por isso a resposta fica em texto, como a missão mandava (sem inventar infraestrutura nova).

No painel `/admin/assistente` há um separador novo "Amigo Bora": conversas, percentagem que virou
carrinho, comparações e quem ganhou, deixas mostradas e clicadas, custo por conversa e por robô, perfis
só em contagens, e "ver perfil de um cliente" com email e motivo obrigatório (fica na auditoria). Os três
interruptores e o texto de boas-vindas editam-se ali.

Aproveitei para tirar o Bora Motorista das instruções do assistente (fechou a 04/11 e ainda lá estava).

## Adendo do suporte (o caso do S.)

A causa do aviso que não mostrava nada: o aviso "cliente escreveu ao suporte" apontava sempre para a
página das escaladas, e a conversa do S. não estava escalada. Agora o aviso e o push do telemóvel do
admin abrem a própria conversa (`/admin/support/sessions/<id>`), e os avisos antigos são corrigidos para o
link novo, com cópia antes. Há uma lista nova "Conversas do suporte" com todas as conversas, as novas
primeiro e a marca de não lida, e o ecrã da conversa mostra as mensagens por ordem (as de ferramenta
recolhidas), nome, telefone com ligar e WhatsApp, email, os últimos pedidos e atualiza ao vivo. O admin
responde numa caixa como "Equipa Bora" (nunca com o nome dele); a mensagem chega ao chat da app ao vivo e
ao sininho do cliente, e o robô fica calado nessa conversa até "Devolver ao robô". Quando o cliente pede
uma pessoa ("falar com assistente" conta, porque no chat do suporte o robô já é o assistente), o robô
responde com o WhatsApp da Bora 937 501 673 e o link https://wa.me/351937501673, sem passar pelo modelo,
marca a conversa como escalada e a equipa é avisada.

Erros que encontrei pelo caminho e corrigi no mesmo ficheiro: o chat do suporte mostrava as linhas de
ferramenta do robô como se fossem mensagens, e ao reabrir uma conversa escalada a app deitava-a fora,
por isso a resposta de uma pessoa nunca chegaria ao cliente. Agora a conversa escalada continua a abrir
durante 48 horas.

## Provas

Banco, num Postgres local (PGlite, sem tocar em produção): as duas migrações correram duas vezes seguidas
e passaram 50 de 50 verificações, entre elas o hábito "sexta à noite: Jyosmi" com 3 pedidos, o esquecer
tudo, o não lembrar, o painel só para admin e com motivo, o aviso antigo corrigido, o novo a abrir a
conversa, responder como Equipa Bora e devolver ao robô. Na primeira volta apanhou uma guarda de admin
que deixava passar quando a função de admin devolvia nulo; ficou endurecida nas duas migrações.

Funções do servidor: as três (client-assistant, assistant-profile-refresh e support-chatbot) passam a
verificação de tipos do Deno, e os 19 testes Deno da lógica nova estão verdes. App: os 26 ficheiros de
teste que tocam no assistente, no suporte, no painel, no perfil, na home e no inglês correram todos: 379
testes, zero falhas (incluindo os 2 ficheiros novos, com 21 testes). A análise do projeto inteiro deu 0
erros; os 6 avisos e as 267 notas estão todos em ficheiros que esta missão não tocou (o PC tem o Flutter
3.47, o CI usa o 3.41.2). O anti-trapaça do Juiz deu limpo: 44 ficheiros, mais 26 casos de teste.

## Custos medidos

Hoje cada chamada do assistente custa em média 0,00995 dólares no Sonnet (2 314 tokens de entrada, 135
de saída, 5 060 lidos da cache). O mesmo volume no Haiku, que passa a responder à conversa livre, custa
0,0005 dólares, cerca de 20 vezes menos. O contexto do Amigo (perfil até ~600 tokens e 5 pedidos) junta
uns 700 tokens a cada pedido: mais 0,0014 dólares no Sonnet e 0,00007 no Haiku. O resumo do perfil é
grátis quando só usa os pedidos e custa menos de uma décima de cêntimo quando lê conversa. A saudação ao
abrir não custa nada. O custo real por conversa passa a aparecer no painel e em `ia_gastos` nos robôs
`edge-amigo` e `edge-amigo-perfil`.

## Falta isto (e porquê)

Nada disto está no ar. A trava do modo automático (ligada a 05/11) só deixa esta sessão enviar o ramo de
ensaio, e recusa migrações e deploy em produção: publica o Claude.ai, pela ordem que está em
`docs/propostas/PROPOSTA_20261108_m4_amigo_bora_e_suporte.md` (duas migrações, três funções, depois a app
nas três lojas). O envio para o ramo de produção pedido no adendo não foi feito por isso: foi o ramo
`ai/2026-11-08-m4-amigo-bora` com pedido de revisão.

As provas de ponta a ponta no emulador e nos telemóveis não foram feitas: o PC tinha entre 500 e 1 000 MB
livres (o emulador precisa de 3 GB) e, sem as migrações aplicadas, a app não tem com quem falar. Para a
prova da sexta, a conta demo do cliente só tem um pedido entregue (uma quinta, no Auchan); são precisos três
pedidos de teste em sextas, e esta sessão não escreve em pedidos: fica para a skill `seed-demo-data` depois
de publicar. A imagem de teste do carrinho (sem marca) está em
`.claude/.ai/provas/m4-amigo-bora-2026-11-08/carrinho_outra_app_teste.png`. A marcação de limpeza abre o
ecrã de marcar e mostra o dia que o cliente disse, mas não vem com a data já posta: isso pede um campo novo
no ecrã da limpeza, fora da área desta missão. A resposta da equipa chega ao sininho do cliente, mas não
há push no telemóvel do cliente para o suporte (só o do admin).

## Erros que encontrei

A tranca do repositório recusou escrever a função do perfil porque leu a linha que guardava a chave do
servidor lida do ambiente como se fosse uma chave escrita no ficheiro (falso alarme, registado em
`docs/TRANCAS.md`); a função foi escrita sem essa variável, e nenhum segredo vai em ficheiro. A tranca
também recusou adicionar tudo de uma vez ao envio (é regra: adicionar por caminho), e assim se fez. O
`flutter pub get` e outra rotina do PC mexeram em ficheiros de plugins e no `analysis_options.yaml` do
worktree: não são desta missão e ficaram fora do envio.

## Próximo passo

O Claude.ai aplica as duas migrações, publica as três funções e as apps, e faz as provas da secção "Provas
a fazer depois de publicar" da proposta, começando pelo aviso do suporte, que é o que o Danilo precisa já.
