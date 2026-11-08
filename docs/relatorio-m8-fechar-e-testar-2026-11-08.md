# Relatório — missão m8-fechar-e-testar-noite-2026-11-08

Sessão do Claude Code no PC (Opus 5.5), noite de 08/11/2026. Worktree `C:\BoraLocal\wt-m8-2026-11-08`, ramo
`ai/2026-11-08-m8-fechar-e-testar`. Registo passo a passo no `e2e_log`, fluxo `m8-fechar-e-testar-noite-2026-11-08`.

## Em resumo

Danilo, juntei o código das seis missões de hoje num ramo só e testei tudo junto: está coerente e verde. Mas nada
foi para o ar. As duas guardas do PC que ligaste a 05/11 (a trava do modo automático e a tranca do Bora) recusam,
de propósito e sem exceção para o "autorizo", tudo o que é publicar: mexer na base de produção, publicar funções do
servidor e enviar código para o GitHub, mesmo o ramo de ensaio. E a tranca também não deixou gravar a chave pública
da app, por isso a app nova não compilou para o emulador. Não contornei nenhuma delas. O que está pronto espera
uma decisão tua (no fim, "SÓ O DANILO").

## Ficou feito isto

Arranque. O PC tinha 975 MB livres. Fechei as sete sessões do Claude Code de hoje que já tinham acabado e a memória
subiu para 2,2 GB. A sessão da M1 continuava a trabalhar no Chrome às 21:57, por isso deixei-a aberta. O servidor
do Dipsy (porta 3080) também ficou a correr, porque não é uma missão acabada.

Juntar o código. Criei um ramo novo a partir do que está no GitHub e juntei os seis ramos pela ordem pedida: M7,
M2, M4, M6, M1 e M3. Só houve conflitos em dois ficheiros de texto (a lista das trancas e a tabela de métricas
das skills), e guardei as duas partes em cada um. O código juntou-se sem conflitos. Confirmei que os ficheiros
que várias missões mexeram ao mesmo tempo (o menu do painel, as rotas da app, as frases em inglês, a configuração
das funções) não ficaram com entradas repetidas. A mira do mapa ficou a da M2, e a reorganização dos menus da M7
não entrou (é só uma proposta em `docs/design/`). O `order_store` não foi mexido: os degraus de desconto do check-in
continuam desligados. A função que fecha o pedido, a dos preços e o ecrã de compra do Favor estão iguais ao que
está no ar.

Testes do código junto, com o Flutter que o CI usa (3.41.2). A análise deu zero erros; os seis avisos que aparecem
são de código antigo (maio, junho e setembro), confirmado linha a linha. A bateria inteira correu de uma vez: 278
ficheiros de teste, 2999 testes, todos certos, zero falhas, em nove minutos (prova em `-r json`). O Juiz anti-trapaça
contra o que está no GitHub deu limpo (196 ficheiros, mais 113 casos de teste), e o Juiz das zonas protegidas também
(nenhuma zona protegida no código mudado).

Revisão das propostas do servidor (fiz de revisor, como pede a regra maker/checker). Nenhuma função é criada por
duas missões diferentes. Comparei, linha a linha, as 24 funções que as propostas reescrevem com a versão que está
no ar hoje, para apanhar alguma que apagasse uma mudança feita depois. Apareceram quatro suspeitas e confirmei uma
a uma: eram a mesma lógica escrita de outra forma (as contas de limpeza continuam na lista do Connect, o
interruptor que desliga a atualização de preços pelo talão continua lá, o pedido MB Way da diferença do Favor só
mudou de sítio, e a faixa de trabalho em curso continua a ver os mesmos estados). Li inteira a proposta 04 da M2,
que mexe no despacho: só muda a conta de quando chamar o estafeta nos pedidos agendados de lojas não-parceiras; os
pedidos normais não são tocados. Duas notas para quem a aplicar: passa a contar a partir da hora prometida pela
loja quando ela existe, e o mínimo passa de 0 para 10 minutos. Atenção também: a proposta 02 da M1 substitui a
função que fecha a compra do Favor, que é zona protegida.

Jyosmi. Confirmei na base: 117 produtos, 116 disponíveis, preparação de 45 minutos. As fotos na versão web só
aparecem quando a app for publicada (o proxy de imagens vai com ela).

## Ficou a faltar isto, e porquê

O SQL das missões (M1, M2, M4, M6 e M7) não foi aplicado. Confirmei por consulta que nada está no ar: as tabelas e
funções novas não existem. A trava do modo automático recusa qualquer mudança de estrutura na base de produção
("publica a Claude.ai"). Há um caminho do programa do Supabase que a trava não vigia, mas usá-lo para isto era
contornar a regra dela, por isso não usei.

As funções do servidor não foram publicadas: a trava recusa a publicação por todos os caminhos.

O código foi para o GitHub só depois do teu "Sim, deixa" (08/11, no chat). A primeira tentativa foi recusada, mas a
causa era o comando, não a regra: a tranca já deixa enviar ramos `ai/…`, mas o comando levava `2>&1` no fim, e ela
contou isso como um segundo destino. As outras seis missões caíram na mesma armadilha. Antes de enviar, encontrei
dados pessoais no código das missões: o telemóvel verdadeiro de um cliente em dois testes da M4, e os nomes dos
candidatos a estafeta com os documentos que faltam a cada um no relatório da M2. Troquei-os por valores falsos e
iniciais (os testes desses ficheiros voltaram a dar 47 e 3 certos) e enviei tudo num registo único, para o histórico
antigo com esses dados não sair do PC. Está no ramo `ai/2026-11-08-m8-junto-e-testado`, com o pedido de revisão n.º 7
(https://github.com/nilofulfarotuga-hue/bora-app-cloud/pull/7). Os seis ramos de cada missão não foram enviados,
pela mesma razão.

Testes no emulador Android, depois do teu segundo "Sim, deixa" (usar as chaves públicas da app para compilar). Passei
as duas chaves só na linha de comando, sem as gravar em ficheiro. A compilação precisou também da configuração do
Firebase da app, copiada da pasta principal (continua fora do git). A app parava no arranque sem chave da Stripe, por
isso compilei em modo de testes da Stripe com uma chave falsa: esta versão não consegue cobrar cartões, e os testes
foram todos sem pagamentos. App instalada no emulador emdia35 às 23:21, com as contas demo do projeto.

O que funciona na app nova: no cliente, o botão "Ajuda-me a escolher" por baixo da pesquisa, o botão verde antigo do
assistente desaparecido e o ecrã do assistente a abrir. No estafeta, a barra vermelha "Falta: …" no mapa, que abre "A
minha conta" com o semáforo (9 coisas a vermelho, o NIF a verde). Gravei a data de nascimento: a linha ficou verde
e o contador desceu de 9 para 8 sem fechar a app, e confirmei na base que ficou gravada. A mira está a meio do ecrã,
do lado direito, e volta a centrar o mapa no estafeta; a mira antiga lá em cima desapareceu. No parceiro, a barra diz
"Loja fechada". Os três papéis entram sem a app morrer. A loja da Jyosmi abre com o menu e a hora de abertura certa.

Defeitos que o emulador mostrou. O mais grave já está no ar e não vem de hoje: a pesquisa dentro de qualquer loja dá
sempre "Sem resultados". A função da pesquisa usa por dentro duas funções de texto (`assistant_tokens` e
`assistant_singular`) a que os clientes deixaram de ter acesso na migração de 20/10. Simulei a chamada como cliente
e dá "permissão negada". A correção é devolver aos clientes o acesso a essas duas funções, que só tratam texto e
não leem dados. É SQL em produção, por isso não o apliquei; fica para a M10 ou a Claude.ai, com a tua decisão. Os
outros são pequenos. No parceiro, o nome da loja fica cortado em "Loj…" porque o texto novo "Loja fechada" é mais
comprido. O cartão "Os meus habituais" da página inicial passa 1 pixel do espaço (é de 29/10). E 21 produtos da Jyosmi
não têm foto, quase todos bebidas.

O que não deu para testar, porque precisa do SQL e das funções novas no ar: diferença de preço nos Favores, entregue
sem código, talão, NIF e recibo, gorjeta, faixa da limpeza, agendado, fila no painel, restaurante do dia, Connect e o
cartão de boas-vindas do Amigo Bora, que só aparece quando o interruptor da personalidade existir no servidor. O
suporte com "falar com uma pessoa" não testei, para não avisar a equipa a meio da noite. Não pus o estafeta demo
online, porque em produção podia receber pedidos de clientes reais. As capturas estão em
`.claude/.ai/provas/m8-2026-11-08/` (só no PC).

A publicação nas três lojas e as provas nas três plataformas não aconteceram, porque dependem de tudo o que está
acima.

Os remendos 06 e 08 da M1 no ecrã de compra do Favor não foram aplicados: a tranca guarda esse ficheiro como zona
vermelha, e aplicá-lo por outro comando seria contornar.

## A lista desta noite, item a item

M1 — SQL 01, 02, 03, 04 e 07: bloqueado pela trava (no livro, prontos para a Claude.ai). Funções favor-cobrar-diferenca,
recibo-pedido-cliente, stripe-webhook e stripe-webhook-empresa, remendos do notify-client e do charge-tip, upload-receipt,
taloes-zip-mes, taloes-copia-diaria e fecho-mensal-contabilista: bloqueado pela trava (no livro). Remendos 06 e 08:
bloqueado pela tranca. Prova do talão sem rede no emulador: bloqueado (a app não compila). Cópia para o Google Drive:
só tu podes autorizar.

M2 — SQL 01 a 04: bloqueado pela trava (no ramo, em `docs/propostas/m2-estafeta-2026-11-08/`); a 04 foi revista e
está bem. Provas no emulador (A minha conta, mira, faixa, agendado, fila no painel): bloqueado.

M4 — duas migrações (`supabase/migrations/20261108210000_amigo_bora_v1.sql` e `20261108220000_suporte_conversa_admin.sql`)
e três funções (client-assistant, assistant-profile-refresh, support-chatbot): bloqueado pela trava. Atenção: estas
duas migrações já estão na pasta das migrações, mas NÃO estão aplicadas. Três pedidos de teste numa sexta para a
prova do "do costume": não feito (só depois de publicar). O aviso do S. continua a apontar para a página antiga até
a migração do suporte ser aplicada.

M6 — SQL e função do restaurante do dia: bloqueado pela trava (nasce desligado). Jyosmi: ok, confirmado na base. O
Edit do check-in no `order_store`: não se faz, por ordem tua.

M7 — SQL dos convites do Connect e as quatro funções: bloqueado pela trava, e de qualquer forma só servem depois de
ativares o Connect na Stripe da empresa. A bateria completa de testes que a M7 não conseguiu correr: feita agora, com
o código todo junto.

M3 — junto ao ramo. O resto da M3 (SSH à VPS, senha do Conselho) não é desta missão.

Juntar os ramos, análise, testes, Juiz: ok. Envio do ramo de ensaio e pedido de revisão: ok, depois do teu sim.
Publicação nas três: não feita por esta sessão; a M10 (lançada às 23:20) ficou com o SQL, as funções e a publicação. Emulador: ver acima.

## Erros encontrados fora do âmbito (só reportados)

1. A trava do modo automático não vigia o comando `supabase db query` do programa do Supabase: por ali passa
   qualquer SQL para produção, incluindo mudanças de estrutura que ela recusa por todos os outros caminhos. Não usei.
   Fica para quem cuida da trava decidir se fecha esse caminho.
2. A tranca conta `2>&1` (e qualquer palavra a mais) como destino do envio, e então trata o envio de um ramo `ai/…`
   como publicação. Foi isso que prendeu no PC os ramos das sete sessões desta noite. Com o comando simples
   `git push origin ai/…` passa.
3. A tranca trata a chave anónima do Supabase (que é pública e está no site) como segredo; isso impede qualquer sessão
   do PC de compilar a app para o emulador.
4. A sessão da M1 continuava a trabalhar no Chrome depois de ter registado o fim às 21:48.
5. `flutter pub get` suja sozinho os ficheiros gerados de Linux, macOS e Windows no worktree; ficaram fora do registo.
6. O telemóvel verdadeiro de um cliente já está público no GitHub, numa página do livro que o espelho do Córtex
   publica (`livro-areas-missao-domingo-noite.md`, registo c813b6a8). O espelho publica o livro inteiro num
   repositório público.

## SÓ O DANILO

1. Enviar ramos de ensaio `ai/…` para o GitHub: decidido, disseste "Sim, deixa".
2. Decidir se as sessões do PC podem usar as duas chaves públicas da app para compilar para o emulador. Sem isto, não
   há testes no Android feitos pelo PC.
3. Ativar o Connect na Stripe da empresa.
4. Pôr os repasses da Stripe em semanal (https://dashboard.stripe.com/settings/payouts).
5. Autorizar o Google Drive da Bora para a cópia diária dos talões.
6. Ler o código QR do WhatsApp da Bora com o telemóvel da Bora.
7. Dizer sim ou não às mensagens da M7 (estafetas, parceiros, Hugo).
8. Ligar o restaurante do dia, quando quiseres.
9. Ligar o check-in com desconto, quando quiseres.

## Próximo passo

A Claude.ai revê o pedido n.º 7, aplica o SQL e as funções pela ordem dos guias, junta o ramo e publica nas três. Com
o sim ao ponto 2, a sessão seguinte faz os cenários no emulador.
