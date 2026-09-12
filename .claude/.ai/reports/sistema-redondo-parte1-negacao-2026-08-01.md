# Parte 1 — negação cega no classificador de zona + no Juiz — FECHADA

Missão: `orquestracao/missoes/sistema-redondo-2026-08-01.md`

## Prova viva usada como caso de teste
- `ordem-20260801071337-3cb4` → `carteiro.sh:zona_vermelha()` marcou 🔴 vermelha uma ordem cujo
  corpo dizia para **NÃO** mexer em áreas protegidas.
- `ordem-20260801072105-228a` → `juiz-mecanico.ps1` reprovou com "a ordem pedia commit/push e NÃO
  há nenhum commit novo desde o arranque" quando o texto dizia o contrário (proibia commit/push).

## Causa-raiz
1. **`carteiro.sh`** — o `NEG` da lição de 2026-07-11 só apagava a palavra de negação **+ 1
   palavra seguinte** (`'(sem|nao|...) +[a-z...]+'`). PT real raramente cola o verbo logo a seguir
   à negação ("não **DEVE** mexer", "nunca, em circunstância nenhuma, vai **ALTERAR**") — o verbo
   de escrita sobrevivia à limpeza e continuava a bater com `WRITE_INTENT`.
2. **`juiz-mecanico.ps1`** — o bloco `(b)` (defeito A, 2026-07-16) usava uma janela fixa de **24
   caracteres, só para trás** do termo `commit/push`. Negação mais distante, ou **depois** do
   termo, ficava fora da janela.

## Fix
Ambos os classificadores passaram de "apagar 1 palavra" / "janela de 24 chars" para **negação por
CLÁUSULA**: a tarefa é dividida em fronteiras de frase (`. ! ? ; \n`) e em conjunções contrastivas
(`mas/porém/contudo/entretanto`, que reiniciam a polaridade dentro do mesmo período). Dentro de
cada cláusula, o termo protegido (`RED_TERMS`+`WRITE_INTENT` no carteiro; `commit/push` no juiz)
só conta se **não houver negação em nenhum ponto dessa mesma cláusula**, antes ou depois, sem
limite de distância. Uma negação **noutra** cláusula (separada por "mas" ou por ponto) não apaga
um termo genuíno na cláusula seguinte — testado explicitamente para não criar o extremo oposto
(suprimir tudo por haver "não" em qualquer lugar do texto).

`RED_ALWAYS` (comandos destrutivos: `--force`, `reset --hard`, `disable row level`) foi
deliberadamente deixado **incondicional** — é design intencional da lição de 2026-07-11 ("vermelho
SEMPRE, sem depender de verbo"), não faz parte do bug reportado, e enfraquecê-lo reduziria uma
proteção real sem evidência de necessidade.

## Ficheiros tocados
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh` — `zona_vermelha()` reescrita
  (linhas ~56-80).
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/_zona_fn_test.sh` — +3 casos de regressão
  (gap largo negação↔verbo; cláusula "mas" que não deve ser suprimida). 15/15 OK.
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/juiz-mecanico.ps1` — bloco `(b)` extraído para
  a função `Get-CommitIntent` (marcadores `# ---FUNC:Get-CommitIntent-START/END---`), mesma
  lógica de cláusula.
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/_juiz_mecanico_commit_test.ps1` — novo, extrai
  e testa `Get-CommitIntent` isolada. 11/11 OK.

## Prova de execução (correu nesta sessão, output real)

```
$ bash _zona_fn_test.sh
== (a) TESTE/LEITURA/VALIDAÇÃO mencionando termos $ -> VERDE ==
OK   [VERDE] ... (5/5)
== (b) ESCRITA REAL nesses dominios -> VERMELHA ==
OK   [VERMELHA] ... (7/7)
== (c) NEGACAO COM GAP LARGO ate ao verbo (bug real 2026-08-01, ordem 3cb4) -> VERDE ==
OK   [VERDE] Corrige o bug do dashboard, mas nao deves em circunstancia nenhuma mexer no dispatch_engine ou no pricing_service
OK   [VERDE] Nunca, em nenhuma hipotese, deves atualizar o platform_settings de stripe
== (d) negacao NOUTRA clausula nao pode apagar termo genuino na clausula seguinte -> VERMELHA ==
OK   [VERMELHA] Nao mexas no dashboard, mas atualiza o pricing_service com o novo valor
TODOS OK (15/15)
```

```
PS> .\_juiz_mecanico_commit_test.ps1
== mandato explicito (sem negacao) -> Manda=True ==            OK (2/2)
== proibicao colada (negacao imediatamente antes) ==            OK (2/2)
== bug real 2026-08-01 (ordem 228a): gap largo antes do termo == OK (2/2)
== negacao DEPOIS do termo (fora da janela antiga) ==            OK (2/2)
== negacao NOUTRA clausula (mas) nao apaga mandato seguinte ==   OK (1/1)
== sem qualquer mencao a commit/push ==                          OK (2/2)
TODOS OK (11/11)
```

`bash -n carteiro.sh` e o parser `[System.Management.Automation.Language.Parser]::ParseFile` no
`juiz-mecanico.ps1` confirmam sintaxe válida (0 erros) em ambos.

## ⚠️ Limitação honesta — NÃO deployado à VPS/PC
Esta correção está só na **cópia do repo** (`deploy/carteiro.sh` + `deploy/juiz-mecanico.ps1`). O
carteiro e o juiz-mecânico **vivos** correm fora deste repo — no VPS (dentro de um container
Docker) e no PC do Danilo, respetivamente — exatamente a mesma limitação já registada na lição
`classificador-zona-menos-sensivel-a-palavras` (2026-07-11: *"esta lição alterou a cópia no repo
... o carteiro vivo corre no VPS ... sincronizar para lá é passo separado"*) e é o próprio assunto
da **Parte 3** desta missão (hermes-bridge fora de versionamento).

Verificado nesta sessão: não há entrada para a VPS em `~/.ssh/config` (só `github.com`) nem
`docker` no PATH deste ambiente — **não foi possível** confirmar nem aplicar ao vivo a partir
daqui. Fica registado como pendência real, não arredondado: **o Danilo (ou a Parte 3, que trata
do sync automático) precisa de levar estes dois ficheiros para o VPS/PC vivos** para o fix ter
efeito nas próximas ordens reais.

## Veredito
✅ **Causa-raiz identificada e corrigida** nos dois classificadores, com prova de regressão
específica para os dois casos reais citados pelo Danilo (3cb4 e 228a) + prova de que a correção
não introduz o extremo oposto (supressão cega por "mas"/cláusula distante).
⚠️ **Deploy à VPS/PC pendente** — fora do alcance desta sessão (sem SSH/docker); depende da
Parte 3 ou de ação humana.
