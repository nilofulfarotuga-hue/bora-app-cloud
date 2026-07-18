---
id: fix-juiz-verdade-2026-07-18
data: 2026-07-18
tipo: relatorio-fix
agente: juiz-mecanico (CEO-AI / MODO PROTECCAO TOTAL)
ficheiro: .claude/.ai/hermes/orquestrador-carteiro/deploy/juiz-mecanico.ps1
---

# Fix: juiz-mecanico dava 5 falsos "TRAVOU" hoje (2026-07-18) com trabalho real provado no git

## Contexto

5 ordens do dia foram travadas pelo juiz mecânico com trabalho real e provado
publicamente no GitHub (branch `autonomous-night-2026-04-29`). Duas causas-raiz
distintas, ambas no chão determinístico `juiz-mecanico.ps1` (não em
`anti_trapaca.py` nem `zonas_diff.py`, que continuam corretos e intocados).

## Causa-raiz A — hash de texto tratado como prova (caso b439)

**Linhas exatas (antes do fix), bloco b1 de commit-check:**

```powershell
foreach ($h in $claimed) {
  $t = (git cat-file -t $h 2>&1); $rc = $LASTEXITCODE
  Proof "git cat-file -t $h (rc=$rc)" "$t"
  if ($rc -ne 0) { Reprova "a saida alega o commit $h mas ele NAO existe no repo (trabalho inventado)" }
  ...
}
```

O juiz extraía QUALQUER sequência hex (`\b[0-9a-f]{7,40}\b`) de qualquer linha
da SAÍDA do executor que contivesse a palavra "commit", e rejeitava
**imediatamente** se essa sequência não existisse no repo — mesmo que o
commit real e novo estivesse lá. Na ordem b439 o executor escreveu, por erro
de transcrição, "commit 29636612139" no relatório; o commit real era
`458326c`. O juiz nunca chegava a olhar o `git log` real (bloco b2) porque já
tinha saído com `Reprova` no b1. **O texto do executor era tratado como
prova — exatamente o que o próprio cabeçalho do script diz para nunca fazer**
("Regra: prova = git + disco. NUNCA o texto do executor.").

## Causa-raiz B — caminho literal da ordem ≠ caminho real do executor (casos 7ab2/02ec/ebcc)

**Linhas exatas (antes do fix), bloco (c) de ficheiro-check:**

```powershell
foreach ($p in $paths) {
  $pp = $p -replace '/', '\'
  $ex = Test-Path (Join-Path $Proj $pp)
  Proof "Test-Path $pp" "$ex"
  if (-not $ex) { Reprova "a ordem pedia criar/alterar o ficheiro $p e ele NAO existe em disco" }
}
```

O juiz extrai o caminho tal como aparece no TEXTO da ordem (regex genérica de
"algo/algo.ext") e testa esse caminho literal a partir da raiz do repo. Como
as ordens muitas vezes referem o relatório em forma curta
(`inbox/relatorio-....md`), mas o executor grava sempre no espelho do córtex
(`.claude/.ai/knowledge/inbox/...`), o `Test-Path` literal falha — apesar do
ficheiro existir e estar commitado. Confirmado em disco antes do fix:

```
relatorio-qty-linha-compra-estafeta-2026-07-18.md  (existe em .claude/.ai/knowledge/inbox/)
relatorio-qty-linha-v2-2026-07-18.md               (existe em .claude/.ai/knowledge/inbox/)
```

E os commits que tocam o fix + os relatórios são reais (`git cat-file -t`
confirmou `commit` para todos):

| hash citado no pedido | existe? |
|---|---|
| `458326c` (fix real, ordem b439) | sim — `commit` |
| `6b84d360` (`lib/screens/driver_map_screen.dart`) | sim — `commit` |
| `ee2476ab` (relatório) | sim — `commit` |
| `37787b49` (relatório) | sim — `commit` |

## O que mudou

Em `juiz-mecanico.ps1`:

1. **Commit-check (bloco b, "manda commit")** — o hash citado no texto da
   SAÍDA passou a ser **apenas auditoria** (linha `Proof`), nunca motivo de
   `Reprova` sozinho. A decisão real passa a ser **sempre** o `git log`
   (`git log --all --oneline --since=@inicio_epoch`, ou hash citado
   verificado por `git cat-file`/`git show --format=%ct`) — nunca o texto.
   Só reprova se **nem o git log mostrar commit novo, nem nenhum hash citado
   bater no repo**.
2. **Ficheiro-check (bloco c, "cria/escreve")** — antes de reprovar, o juiz
   agora tenta, por ordem: (i) o caminho literal da ordem (como já fazia);
   (ii) o mesmo caminho sob o espelho do córtex
   `.claude\.ai\knowledge\<caminho da ordem>`; (iii) na ausência de qualquer
   caminho em disco, um commit real desde o arranque da ordem
   (`git log $base..HEAD --name-only -- "*<nome do ficheiro>"`) que toque um
   ficheiro com o mesmo nome. Só reprova se as três falharem.
3. Quando a divergência de caminho é a única coisa que não bate, o juiz
   **aprova** (segue para o juiz textual) e regista a divergência numa linha
   `PROVA-JUIZ` — em vez de bloquear.
4. `anti_trapaca.py` e `zonas_diff.py` não foram alterados — a investigação
   confirmou que o defeito estava só no `juiz-mecanico.ps1`.

## Simulação dos 3 casos (após o fix) — todos APROVADA

**b439** (hash de texto errado, commit real `458326c` novo):
```
PROVA-JUIZ: [git cat-file -t 29636612139 (rc=128)] -> fatal: Not a valid object name 29636612139
PROVA-JUIZ: [hash alegado diverge do git] -> 29636612139 nao bate no repo - pode ser erro de digitacao/transcricao do executor; nao reprova sozinho, decide o git log real na b2
PROVA-JUIZ: [git log --all --oneline --since=@1784361000] -> 37787b4 docs(cortex): 6a reconfirmacao... | ...
PROVA-JUIZ: chao mecanico OK - segue para o juiz textual
EXIT CODE: 0
```

**7ab2** (caminho curto na ordem, ficheiro real no espelho do córtex):
```
PROVA-JUIZ: [Test-Path inbox\relatorio-qty-linha-compra-estafeta-2026-07-18.md] -> False
PROVA-JUIZ: [Test-Path .claude\.ai\knowledge\inbox\relatorio-qty-linha-compra-estafeta-2026-07-18.md (espelho cortex)] -> True
PROVA-JUIZ: [ficheiro-check] -> ... nao esta no caminho literal mas existe no espelho do cortex ... - divergencia de caminho, nao trabalho em falta
PROVA-JUIZ: chao mecanico OK - segue para o juiz textual
EXIT CODE: 0
```

**ebcc** (fix commitado + relatório v2 em caminho curto):
```
PROVA-JUIZ: [git log --all --oneline --since=@1784369500] -> 37787b4 docs(cortex)... | 1438a82 ... | 4808958 ...
PROVA-JUIZ: [Test-Path inbox\relatorio-qty-linha-v2-2026-07-18.md] -> False
PROVA-JUIZ: [Test-Path .claude\.ai\knowledge\inbox\relatorio-qty-linha-v2-2026-07-18.md (espelho cortex)] -> True
PROVA-JUIZ: [ficheiro-check] -> ... existe no espelho do cortex ... - divergencia de caminho, nao trabalho em falta
PROVA-JUIZ: chao mecanico OK - segue para o juiz textual
EXIT CODE: 0
```

**Controlo negativo** (para confirmar que o gate NÃO foi enfraquecido — ordem
pede commit, nenhum commit novo existe desde um `inicio_epoch` no futuro,
hash citado é inventado):
```
PROVA-JUIZ: [git cat-file -t abc1234 (rc=128)] -> fatal: Not a valid object name abc1234
PROVA-JUIZ: [git log --all --oneline --since=@9999999999] -> (vazio)
VEREDITO: CORRIGIR: a ordem pedia commit/push e NAO ha nenhum commit novo desde o arranque da ordem (prova = git log real, nunca o texto do executor)
EXIT CODE: 2
```
Confirma que o juiz continua a rejeitar batota real — só deixou de rejeitar
divergência de texto/caminho quando o trabalho existe de facto no git/disco.

Validação adicional: sintaxe do `.ps1` verificada com
`[System.Management.Automation.Language.Parser]::ParseFile(...)` → `PARSE OK`
sem erros.

## Commit real do fix

```
hash_completo=<preenchido após o commit — ver abaixo>
```

(output de `git log -1` colado após o commit desta correção, conforme pedido)
