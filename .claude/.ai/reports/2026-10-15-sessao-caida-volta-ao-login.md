# Relatório — missão `sessao-caida-volta-ao-login-2026-10-15`

> Para o Danilo, em texto corrido. O registo detalhado está no e2e_log
> (`run_id = sessao-caida-volta-ao-login-2026-10-15`, linhas 3679 a 3686 e seguintes) e as
> provas em `.claude/.ai/provas/sessao-caida-2026-10-15/`.
> Acessos usados: conta de teste `demo-parceiro@bora.app` (loja demo invisível). Nenhuma conta
> real foi tocada; a saída de todas as sessões só foi feita nessa conta de teste.

## O que NÃO ficou feito (primeiro, como manda a regra)

Duas das três migrações de hoje não ficaram guardadas no repositório. A tranca de segurança
recusou gravar a segunda (fala de ledger e reembolso) e a terceira é da mesma natureza; não se
tentou outro caminho. O código delas está guardado no próprio Supabase, no registo de migrações,
e confirmei a impressão digital de cada uma. A primeira ficou no repositório, igual à do servidor.

A página dos bugs resolvidos no Córtex não foi escrita diretamente: o Córtex recusou porque fala
de dinheiro e mandou fazer proposta. Ficou a proposta prop-67e6ccd3 na fila de aprovação; a cópia
da mesma página no repositório já diz RESOLVIDO.

Não testei no telemóvel à mão. Android e iPhone ficaram cobertos pelo CI, e passaram (ver
"Publicado nas três"). No iPhone, a versão nova ainda tem de passar pelo processamento da Apple
antes de aparecer no TestFlight; isso não fica nas minhas mãos.

## Fiz isto

Sessão caída volta à página de entrar. Quando o Supabase avisa que a sessão acabou de verdade
(o servidor recusou renovar, ou alguém saiu noutro separador), a app limpa a conta como o "Sair"
normal, fecha os ecrãs abertos por cima, abre a entrada do papel certo (cliente, estafeta ou
parceiro) e mostra "A tua sessão terminou. Entra outra vez.". Não apaga a biometria nem o papel
escolhido. Espera dois segundos antes de expulsar, para que um login noutro separador não tire
ninguém. Confirmei na versão 2.18.3 do Supabase que uma queda de rede nunca chega como fim de
sessão — vem por outro canal e a app não faz nada. Não mexi na recuperação de palavra-passe, na
biometria nem na sessão de convidado, e não há ciclo, porque a saída que a própria app faz é
ignorada.

Nos ecrãs do parceiro que gravam (criar e editar produto, marcar esgotado, apagar), se a gravação
falhar por falta de sessão ou erro 401, aparece a mesma mensagem e a app manda entrar, em vez do
erro das percentagens. Num 401 com a sessão ainda no aparelho, a app tenta primeiro renovar,
para não expulsar quem tem o relógio do telemóvel atrasado.

Provas. Um teste novo com o Supabase verdadeiro e um servidor falso, com cinco casos: sessão
recusada pelo servidor, queda de rede, "Sair" normal, sessão que volta em menos de dois segundos,
e 401 com renovação aceite e recusada. Sem a correção, o primeiro caso chumba. Correram 64 testes
na cópia limpa (o novo, o das traduções e os sete que usam o AuthStore), todos verdes, e o chão anti-trapaça do Juiz ficou limpo. Um verificador
independente tentou derrubar o trabalho e aprovou; corrigi três reparos dele antes de enviar.

Prova na web pública, com a conta de teste. Antes da correção: cortei a sessão no servidor e
adiantei o relógio do navegador uma hora; o servidor recusou a renovação e o ecrã de produtos
ficou aberto como se estivesse ligado — o mesmo que aconteceu ao Sabores de Casa. Depois da
correção, a mesma coisa: a app fechou os produtos, voltou à entrada do parceiro com o email
preenchido e mostrou o aviso. As fotografias estão na pasta das provas.

Registo do "parceiro chama estafeta". A primeira migração de hoje ficou no repositório; as regras
de negócio, ponto 2.4.1, dizem agora "acerto implementado e ligado a 15/10/2026"; o bug 25 está
como resolvido; o comentário do ecrã "Chamar estafeta" diz que está ligado. Confirmei por leitura
que o interruptor está ligado desde as 13:42 de Lisboa.

Envio. Trabalhei numa cópia limpa feita a partir do servidor, porque a pasta principal tinha 351
alterações de outras sessões por gravar; só viajaram os meus 18 ficheiros, em dois commits.
Envio 38b4690b para 7f36106e. A pasta principal ficou exatamente como a encontrei. O prompt ficou
registado no Obsidian, em prompts.

## Publicado nas três

Android: corrida 526 verde, com o autoteste dos três perfis no emulador a passar. O CI criou a
versão 673 e gravou 673 no aviso de atualização, o que só acontece depois do envio à Play Store.

iPhone: corrida 193 verde. O registo do simulador mostra os cinco casos do teste novo a passar,
e a app assinada foi enviada ao App Store Connect. O aviso de atualização do iPhone ficou em 193.

Web: corrida 219 verde. O endereço público app.boraguarda.com serve o ficheiro novo, com a frase
nova lá dentro, com e sem quebra-cache. A prova "depois" foi feita aí.

## Falta isto

Gravar no repositório as duas migrações que a tranca recusou, quando decidires como a tranca deve
tratar cópias de migrações já aplicadas. Aprovar no Córtex a proposta prop-67e6ccd3 (bug 25
resolvido). Esperar o processamento da Apple para a versão aparecer no TestFlight.

## Erros que encontrei pelo caminho (reportados, não corrigidos)

A sessão de convidado continua partida na web: guest@bora.com não entra (já conhecido desde 08/09).

Ao arrancar a app com uma sessão guardada já morta, há uma corrida de tempo: às vezes a app volta
a entrar sozinha com a palavra-passe guardada, outras vezes manda para a entrada. Antes ficava no
limbo, por isso está melhor, mas perde-se a reentrada silenciosa.

Se a reentrada no arranque falhar (palavra-passe mudada), o parceiro pode ficar em memória com a
sessão de convidado. Como aí existe sessão, o aviso novo não dispara. É um defeito antigo.

Com um link de recuperação de palavra-passe já usado, num caso raro, aparece "sessão terminou"
em vez de "ligação expirada".

Se noutro separador alguém entrar com OUTRA conta, este separador fica a mostrar a conta antiga
com a sessão da nova. É um defeito antigo, não desta mudança.

A versão do Supabase não está fixa: o CI instala a mais recente da série 2. O teste novo é que
avisa se o SDK mudar a forma de dizer que a sessão acabou.

O agente "juiz-revisor" não existe nesta sessão do Claude Code; a verificação foi feita por um
agente geral com as ordens do Juiz.

A tranca de segurança não deixa guardar no repositório cópias de migrações de dinheiro já
aplicadas. Isso deixa o repositório atrás do servidor nessas funções. Mexer na tranca é contigo.

## Próximo passo

Quando o dono do Sabores de Casa atualizar a app ou recarregar o site, se a sessão voltar a
cair ele vai parar à página de entrar com o aviso, em vez de ficar num ecrã que não grava.
Vale a pena, numa missão própria, tratar o arranque com sessão guardada morta e a sessão de
convidado partida, que são os dois buracos parecidos que ficaram reportados.
