# Mapa do que publica sozinho + plano de isolamento para o C4

> 2026-07-20 · Levantado com prova (schtasks, logs, reflog, API do GitHub).
> **Nada aplicado. Aguarda aprovação do Danilo.**

## 1. BoraGitPushBridge — o que é, e o estado real

| Campo | Valor (medido) |
|---|---|
| Executa | `powershell.exe -File .claude\.ai\hermes\push-bridge\push-loop.ps1` |
| Corre como | `danil`, logon **Interactive** (precisa da sessão aberta p/ a credencial GCM) |
| Frequência | **15 em 15 minutos**, desde 2026-07-16 12:40, sem fim definido |
| Última corrida | 2026-07-20 22:55:55 · `LastTaskResult=0` ← **enganador** |
| O que empurra | `$branch = git rev-parse --abbrev-ref HEAD` → `git push origin $branch` |
| Filtros | **Nenhum.** Sem whitelist de branch, sem confirmação, sem dry-run |

### Está PARTIDA (e isso muda tudo)

`push-bridge.log`, corrida das 22:55:03:
```
[2026-07-20 22:55:03] branch=autonomous-night-2026-04-29 exitcode=128
git@github.com: Permission denied (publickey).
```
O `origin` é **SSH** (`git@github.com:...`) e nesta máquina só a via **HTTPS + GCM** autentica.
Logo a bridge falha em **todas** as corridas. O `LastTaskResult=0` da schtask só diz que o
PowerShell terminou — não que o `git push` funcionou.

**Perigo latente (o mais importante desta secção):** ela empurra *a branch que estiver
em checkout*, seja qual for. No dia em que alguém reparar o `origin` (ou juntar uma chave),
passa a publicar de 15 em 15 minutos o que quer que esteja no diretório principal — sem
ninguém pedir. Hoje é inofensiva por avaria, não por desenho.

## 2. O que dispara build / deploy / Play

| Workflow | Gatilho | Ignora | Efeito |
|---|---|---|---|
| `build_android.yml` | push → `autonomous-night-2026-04-29` | `**.md`, `.claude/**` | AAB → **Google Play, Teste Fechado (alpha)** + commit de bump do versionCode |
| `build_web_deploy.yml` | push → `autonomous-night-2026-04-29` | `**.md`, `.claude/**`, `docs/**` | Deploy do site |
| `dart.yml` | push → `main` | — | Só lint/build |
| `e2e-web.yml` | `workflow_dispatch` | — | Só manual |

### A subtileza que me enganou hoje

O `paths-ignore` é avaliado sobre **todos os commits do push**, não sobre o commit do topo.
Prova: a corrida `29781755368` tem `head_sha=280e581` — o meu commit, que só toca `.claude/**`
— e mesmo assim o build Android correu, porque no mesmo push seguiam commits de código.

**Regra prática:** um commit `.claude/`-only nunca dispara nada *sozinho*, mas serve de
**boleia** para o código pendente que viajar com ele. Foi exatamente isso que aconteceu.

## 3. Quem publicou às 21:51 — NÃO SEI, e não vou fingir que sei

O que está provado:
- **GitHub:** `actor` e `triggering_actor` = `nilofulfarotuga-hue` (a conta do Danilo),
  `event=push`, `21:51:01Z`. Mesmo actor da corrida das 13:34.
- **reflog local:** às 22:50:47-48 (local) houve `rebase (start): checkout FETCH_HEAD` seguido
  do pick de 3 commits, incluindo o meu → `280e581`. É a assinatura de
  `pull --rebase --autostash` + `push`. O mesmo padrão às 14:33:51, aí com o URL **HTTPS** no log.
- **Não foi a bridge:** falha com publickey a cada corrida.
- **Não foram os hooks:** `post-commit` é o indexador graphify; `pre-push` só dispara o sync do
  Córtex no VPS por SSH; `post-checkout` idem. Nenhum faz `git push`.
- Nenhum script no repo contém `pull --rebase --autostash` (só um documento o menciona).

**Conclusão honesta:** é um processo a correr como `danil` com a credencial GCM, que ainda não
identifiquei. Eu já atribuí isto à bridge uma vez e estava errado — não repito o palpite.

## 4. Plano de isolamento (aguarda aprovação)

**Princípio:** não preciso de descobrir o publicador para me proteger dele. Todos os
publicadores observados agem sobre **`autonomous-night-2026-04-29` no diretório principal**.
Basta o trabalho do motor nunca lá aterrar.

- **P1 — Branch + worktree dedicados.** O trabalho do C4 acontece num worktree separado, na
  branch `motor-conhecimento-2026-07-20` (já publicada, 1 commit limpo). O diretório principal
  fica em `autonomous-night`, e o que eu commitar nunca entra na branch auto-publicada.
  Consequência: nenhum publicador — conhecido ou não — pode levar o meu trabalho ao ar.
- **P2 — Testar o C4 sem git.** O `carteiro.sh` vive na VPS e é lá que corre; o deploy é por
  `scp`/`ssh`, não por push. Dá para editar, deployar e provar o C4 **sem um único push**.
  (A confirmar antes de começar: qual o comando de deploy canónico em `DEPLOY.md`.)
- **P3 — Nunca mais ser boleia.** Antes de qualquer commit no diretório principal, correr
  `git log --oneline origin/<branch>..HEAD` e ver o que viaja junto. Se houver código pendente
  de terceiros, não commitar ali — vai para o worktree.
- **P4 — Guardrail durável na bridge (opcional, precisa de decisão).** Hoje ela está avariada;
  quando for reparada volta o risco. Duas hipóteses:
  (a) **Reformar:** whitelist de branch (só empurra se `HEAD` for a branch autorizada) +
      respeitar um ficheiro `.pausa-push`, à imagem do `.pausa-total` do carteiro.
  (b) **Reformar-para-a-reforma:** desativar a schtask enquanto não for precisa, já que
      não funciona há dias e ninguém deu por isso.
  Não mexo em nenhuma sem o teu "vai" — é infraestrutura de publicação.

### O que peço para avançar
1. Aprovas **P1+P2+P3** (isolamento sem tocar em infraestrutura)?
2. Queres **P4**? Se sim, (a) reformar ou (b) desativar?
3. Queres que eu investigue até identificar o publicador das 21:51, ou aceitas que o P1
   torna a pergunta irrelevante para o C4?
