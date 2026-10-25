# Dois commits que ficaram só no PC — documentos de todos os papéis (25/10/2026)

Pedido pela sessão do vídeo do angariador (e2e_log 4629). Sessão de revisão, sem push.

## Fiz isto

Descobri de onde vêm os dois commits. São da missão "documentos-todos-papeis-22-10",
que arrancou a 22/10 às 20:43, logo a seguir à do cadastro do estafeta, com a tua ordem
dessa noite: "São todas as categorias. Motorista, lavador de carro, limpeza. Tudo tem que
ter os documentos. Não deixa faltando nada." A missão escreveu o plano no e2e_log (id 4415),
fez os dois commits às 21:00 e às 21:10, e parou ali. Não há mais nenhum passo no e2e_log,
não há digest no livro, não há relatório e não houve push. O trabalho ficou só no ramo do PC.

Confirmei que nada disto chegou ao servidor por outro caminho. Os commits mexem em 15 ficheiros:
os 10 que já existiam estão no servidor exatamente como estavam antes da missão, e os 5 novos
não existem lá. Os commits não trazem
migrações nem funções novas: só código da app e do painel. Tudo o que esse código chama já
existe em produção, verificado no Supabase: as três funções (conformidade dos motoristas TVDE,
enviar notificação, decidir comprovativo de atividade), as sete tabelas e os quatro baldes
privados de fotos (estafeta, limpeza, lavagem e comprovativo de atividade).

Pus os dois commits por cima do servidor, num ramo à parte chamado `revisao-docs-papeis-25-10`.
Entraram sem conflito, e os 15 ficheiros ficaram iguais, byte a byte, aos do PC.

## O que os commits mudam

No painel, cada papel passa a mostrar todos os documentos, com "Falta" a vermelho no que não
existe e um botão "Pedir documentos em falta" (aviso na app, notificação e registo). No motorista
TVDE aparece o certificado, a carta, o operador e o contrato, o dístico, a inspeção, o seguro e o
carro. Os quatro motoristas aprovados não mostravam nada, e agora mostram. Na limpeza, o cartão
deixa de rebentar. Na lavagem, o painel não mostrava nenhum documento, e agora mostra a ficha
completa. Aprovar passa a pedir confirmação; antes bastava um toque, mesmo a partir de recusado.
As fotos guardadas sem o nome do balde, que abriam partidas, passam a abrir.

Do lado de quem se candidata (limpeza, lavagem, TVDE e "candidatar-me a outro papel"), as fotos
passam a sair com o tipo certo. A foto do iPhone em HEIC é convertida para JPEG. Se a sessão tiver
caído, a pessoa recebe "sessão expirou", em vez de a candidatura se gravar sem o documento.

## Passaram no Juiz?

Sim, em tudo. O juiz anti-trapaça, comparado com o servidor, deu limpo: 15 ficheiros e mais
5 casos de teste, sem batota. O das zonas protegidas também deu limpo: nada de dispatch, preços,
Stripe, tokens nem RLS de dinheiro.

O `flutter analyze`, com o Flutter 3.41.2, deu zero erros. Os 7 avisos estão todos em ficheiros
que os commits não tocam. Nos ficheiros dos commits há 3 notas de estilo, e as mesmas 3 já lá
estavam no servidor: os commits não acrescentam nenhuma.

O `flutter test` correu os 163 ficheiros e passou os 1602 casos, sem nenhum saltado. O teste
novo dos commits correu os seus 5 casos. Provei isto com a saída JSON, que regista cada caso.

Uma armadilha que encontrei pelo caminho: a saída normal do `flutter test`, a que se lê no ecrã,
parecia mostrar só 70 dos 163 ficheiros. É defeito de apresentação, não falta de testes: quando
corre em paralelo, cada linha mostra o teste que ainda está a correr e não o que acabou. Quem
quiser provar que um ficheiro correu deve usar `-r json`, e não contar nomes nessa saída.

Os dados de teste não trazem nada pessoal. O NIF do teste novo é o de uma conta de teste de
22/10 que já foi encerrada, e o IBAN é o exemplo público que se usa para Portugal.

## O que viajaria num push

O servidor tem agora 26 commits que o PC não tinha: 21 espelhos do Córtex, 2 subidas do
versionCode e 3 de trabalho (o cartão OmniRoute e a paridade de preços com a Glovo). Esses já
estão publicados: o último push, a 23/10 às 22:42, publicou Android, iOS e web, tudo verde.
Por isso, um push agora levaria só estes dois commits e este relatório. Esse push dispara as
3 plataformas: Android no teste interno, no fechado e em produção, com o versionCode a subir
para 691 pelo CI; a web; e o iOS, com envio e submissão à Apple.

## Erros que encontrei

O ramo do PC (`autonomous-night-2026-04-29` em `C:\BoraLocal\projetosflutter\bora_app`) continua
separado do servidor. Depois do push, a próxima sessão que puxar ali deve usar `git pull --rebase`:
os dois commits saltam sozinhos, porque já lá estão. Essa pasta tem também muitas alterações por
gravar de outras sessões (espelhos, fotos dos goldens, a mudança do AGENTS.md). Não lhes toquei.

O plano da missão também queria que o prestador pudesse reenviar os documentos no ecrã de
"pendente" e que tudo fosse publicado. Isso não aparece nestes commits: fica por fazer.

## Recomendação

Publicar. É trabalho que tu pediste e que estava pronto, e passou em todas as provas que dá para
fazer sem publicar. Não toca em dinheiro nem em zonas protegidas, e o banco já tem tudo o que ele
usa. Enquanto não for publicado, o painel continua sem mostrar os documentos dos motoristas TVDE
e dos lavadores, e as fotos HEIC do iPhone continuam a ser recusadas no envio ou a não abrir no painel.

O que não consegui provar daqui: o ecrã a funcionar no ar com uma conta de admin. Isso só se vê
depois do push, na web.

## Publicado (25/10, depois do teu "vai")

Antes do push, o servidor tinha andado mais um espelho do Córtex (0148e700), que só mexe em
`.claude/.ai/knowledge`. Pus os commits por cima outra vez, e o código ficou igual ao que foi
testado. O push foi `0148e700..f2184563`.

- Fotos dos ecrãs (golden): verde.
- Web: verde. O `versao.json` em app.boraguarda.com e em bora-app-web.pages.dev diz
  `f2184563`, e o bundle no ar tem frases que só estes commits trazem ("Ver ficha completa" e o
  novo texto do menu "Documentos TVDE (ficheiros)").
- Android: o autoteste dos 3 perfis passou, o versionCode subiu para 691 (67bb44ae), e a Play
  aceitou o envio nas pistas internal, alpha e produção.
- iOS: o simulador passou, o IPA foi enviado sem erros, e a versão 1.0.29 foi criada com o
  build 208 e lançamento automático depois da aprovação. A Apple leu de volta "à espera de
  revisão" (WAITING_FOR_REVIEW), às 15:45 UTC. Quando a Apple aprovar, sai sozinha.

Uma coisa que encontrei e não corrigi: o texto "O que há de novo" da App Store sai sempre de
`ios/notas_de_versao.json`, que não muda desde 17/10. A 1.0.29 diz "Cancelamento de corrida:
agora vês o valor real antes de cancelar", o que não tem nada a ver com esta mudança. Não está
errado, mas está velho. Se quiseres outro texto, basta mudar esse ficheiro antes do próximo push.

Falta ver o ecrã novo a funcionar no ar com uma conta de admin, com os documentos de um
motorista, de um lavador e de uma pessoa da limpeza.

## Comando de push (já usado a 25/10)

Corre na pasta de revisão. Se o servidor tiver andado entretanto (os espelhos entram de hora a
hora), o rebase põe os commits por cima outra vez, sem conflito, porque os espelhos só mexem
em `.claude/.ai/knowledge`.

```bash
cd /c/BoraLocal/projetosflutter/bora_app/bora_app/.claude/worktrees/lucid-hypatia-a6b9fc
git fetch origin autonomous-night-2026-04-29
git rebase origin/autonomous-night-2026-04-29
git push origin HEAD:autonomous-night-2026-04-29
```

Se esta pasta já não existir, o ramo `revisao-docs-papeis-25-10` continua no repositório.
Basta abrir uma worktree nova a partir dele e correr os mesmos três comandos.
