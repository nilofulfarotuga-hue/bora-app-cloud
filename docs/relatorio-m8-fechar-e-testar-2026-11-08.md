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

O código não foi para o GitHub: a tranca recusou o envio do ramo de ensaio ("é publicar: publica o Claude.ai"). As
outras seis missões bateram na mesma parede. Por isso a Claude.ai também não consegue ver o código: ele só existe
neste PC.

Os testes no emulador Android não foram feitos. Para compilar a app nova são precisas duas chaves públicas (o
endereço do Supabase e a chave anónima, que qualquer pessoa vê no site). A trava não deixa ler o ficheiro das
chaves, e a tranca recusou gravá-las num ficheiro à parte porque viu um "token" e não sabe que esta chave é
pública. E mesmo com a app compilada, sem o SQL e as funções no ar os cenários novos (Favores, talão, recibo,
gorjeta, A minha conta, fila, Amigo Bora, suporte, restaurante do dia, Connect) não tinham com quem falar. Os dois
emuladores estão prontos no PC (emdia e emdia35).

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

Juntar os ramos, análise, testes, Juiz: ok. Envio para o GitHub, CI e publicação nas três: bloqueado.

## Erros encontrados fora do âmbito (só reportados)

1. A trava do modo automático não vigia o comando `supabase db query` do programa do Supabase: por ali passa
   qualquer SQL para produção, incluindo mudanças de estrutura que ela recusa por todos os outros caminhos. Não usei.
   Fica para quem cuida da trava decidir se fecha esse caminho.
2. As duas guardas contradizem a skill do modo automático: a skill manda enviar o ramo `ai/…` e abrir o pedido de
   revisão, e a tranca recusa esse envio desde 06/11. Resultado: há sete ramos desta noite presos no PC.
3. A tranca trata a chave anónima do Supabase (que é pública e está no site) como segredo; isso impede qualquer sessão
   do PC de compilar a app para o emulador.
4. A sessão da M1 continuava a trabalhar no Chrome depois de ter registado o fim às 21:48.
5. `flutter pub get` suja sozinho os ficheiros gerados de Linux, macOS e Windows no worktree; ficaram fora do registo.

## SÓ O DANILO

1. Decidir se as sessões do PC podem enviar ramos de ensaio `ai/…` para o GitHub (sem força). Sem isto, nada do que
   se fez hoje chega à Claude.ai nem às lojas.
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

Com o sim ao ponto 1, uma sessão do PC envia o ramo `ai/2026-11-08-m8-fechar-e-testar` (já tem as seis missões
juntas e testadas) e a Claude.ai aplica o SQL e as funções pela ordem dos guias, junta o ramo e publica nas três. Com
o sim ao ponto 2, a sessão seguinte faz os cenários no emulador.
