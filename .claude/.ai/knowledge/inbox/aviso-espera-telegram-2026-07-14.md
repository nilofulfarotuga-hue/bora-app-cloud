---
data: 2026-07-14
agente: executor-loop-autonomo (SONNET)
tipo: feature-notificacao (comunicacao, sem mudar regra de negocio)
---

# Aviso de ordens em espera manual — Telegram + desbloqueio "vai [id]"

## Pedido
Ordens que caem na fila de espera manual (zona vermelha — tocam dinheiro/pagamento e
por isso exigem confirmação humana antes de correr) ficavam "presas sem aviso": o
Danilo não sabia facilmente que havia algo à espera. Pedido era só melhorar a
**comunicação**, sem tocar na regra de quem entra em espera:
1. Ao entrar na fila de espera, o Hermes avisa logo no Telegram com resumo curto +
   motivo.
2. O Danilo responde `vai [id]` no Telegram e a ordem volta sozinha para a fila normal.
3. Não remover nem enfraquecer a verificação — só tornar o aviso "num toque".

## O que encontrei ao começar
Uma iteração anterior deste mesmo loop autónomo já tinha preparado a implementação
completa no working tree, **não commitada**:
- `carteiro.sh`: nova função `resumo_tarefa()` (tira os prefixos de máquina
  `[MODELO:.../[PROPOSE-ONLY:...]` e corta a 160 chars) + a chamada `notify(...)` no
  ramo `zona_vermelha` passou a incluir o resumo da tarefa e o comando exato
  `vai <id>` para desbloquear.
- `skill-desbloqueio-vai/SKILL.md` (pasta nova, ainda não versionada): skill do
  Hermes que reage a `vai <id>` no Telegram — só se a ordem estiver
  `estado: zona_vermelha`, muda para `estado: aberta` e limpa `nota:`; noutros
  estados (`travada`, já `aberta/executando/...`) só informa, não mexe. Zero
  heurística — só reage à confirmação explícita.
- `DEPLOY.md`: já documentava os dois pontos acima e como levar a skill para o
  container Hermes (`/opt/data/skills/hermes-agent/desbloqueio-zona-vermelha/`, mesmo
  padrão de descoberta automática por pasta usado por outras skills do Hermes).

Revi linha a linha — está correto e completo para o pedido. Não reescrevi nada disto.

## O que fiz nesta sessão
1. **Validação da lógica existente:** corri `carteiro.sh --selftest` — os 3 testes
   novos de `resumo_tarefa()` (tira `[MODELO:...]`, tira os dois prefixos, corta a
   160 chars) passam. Há 1 falha pré-existente e **não relacionada**
   (`reset 9:05am minutos`, dentro de `rl_resume_epoch`) — confirmei com
   `git stash` que já falha na versão commitada em `HEAD` também; é um efeito do
   `date -d` no git-bash do Windows (o script corre de verdade só no VPS Linux), não
   toquei nisso — fora do escopo deste pedido.
2. **Teste sintético ponta-a-ponta** (era o pedido explícito de "testar"): criei
   `.claude/.ai/hermes/orquestrador-carteiro/deploy/_teste_aviso_espera.sh` — segue o
   mesmo padrão do `_zona_fn_test.sh` já existente (faz `sourcing` das funções reais
   de `carteiro.sh`, zero lógica duplicada, não é deployado, só teste). Simula sem
   Docker/VPS:
   - uma ordem sintética com tarefa que mexe em `platform_settings commission_rate`
     entra em `zona_vermelha` → gera o aviso Telegram com o resumo certo e o comando
     `vai <id>`;
   - responder `vai <id>` (lógica igual à da skill) devolve a ordem a
     `estado: aberta` e limpa a `nota`;
   - repetir `vai <id>` numa ordem já desbloqueada não faz nada (idempotência — não
     reabre/duplica).

   Resultado: **`TESTE-AVISO-ESPERA: TODOS OK`** (7/7 verificações).

   ```
   OK   ordem sintética entrou em zona_vermelha
   OK   aviso Telegram gerado
   OK   aviso leva o resumo da tarefa (sem prefixo [MODELO:...])
   OK   aviso leva o comando exato de desbloqueio (vai ordem-teste-avisoespera-0001)
   OK   'vai ordem-teste-avisoespera-0001' devolveu a ordem a estado: aberta
   OK   'vai ordem-teste-avisoespera-0001' limpou a nota
   OK   'vai ordem-teste-avisoespera-0001' repetido não mexe (ordem já não está em zona_vermelha)
   ```
3. Atualizei `DEPLOY.md` para referenciar o novo teste (`_teste_aviso_espera.sh`) ao
   lado do `--selftest`.
4. Confirmei que `grep -c 'notify "' carteiro.sh` continua em **7** (a guarda que o
   próprio `DEPLOY.md` pede para não perder nenhum aviso ao editar o ficheiro).

## O que NÃO mudei (de propósito)
- O classificador `zona_vermelha()` (quem entra em espera) — zero alteração, exatamente
  como o pedido pediu.
- Nenhum ficheiro nuclear/protegido (Stripe, `pricing_service`, `dispatch_engine`,
  `finalizePurchase`, `bora_tokens`, RLS de orders/wallets/ledger).

## Commit
Fiz `git commit` (local) só dos ficheiros deste pedido:
`carteiro.sh`, `DEPLOY.md`, `skill-desbloqueio-vai/SKILL.md`, `_teste_aviso_espera.sh`
e este relatório. Não toquei nos outros ficheiros modificados/untracked no working
tree (são de outras tarefas/outras iterações do loop — `main.dart`,
`AndroidManifest.xml`, `Info.plist`, `testes-e2e/*`, `heartbeat-*`, etc.).

## ⚠️ Sem `git push` — dispara build de produção
O branch `autonomous-night-2026-04-29` tem `on: push:` no
`.github/workflows/build_android.yml` → qualquer `git push` aqui dispara
automaticamente **build de produção + upload ao Google Play** (Lista Vermelha:
"builds de produção"). Isto é o mesmo padrão já registado em
`login-parceiro-reinicia-wizard-2026-07-14.md` para outros commits pendentes nesta
branch. Além disso, a memória confirma que o executor headless normalmente nem
consegue fazer `git push` direto (credenciais interativas) — só o loop
concorrente/ponte empurra.

⚠️ ISTO PODE DISPARAR BUILD DE PRODUÇÃO (push do branch → CI → Google Play). Está
tudo pronto e testado — confirma que eu aplico (`git push`), ou deixa para o próximo
push já planeado (há outros commits nesta branch também à espera do mesmo "vai").

## Deploy à parte (VPS + container Hermes) — pendente, fora do alcance deste ambiente
Este ambiente (PC Windows, headless) não tem acesso Docker/SSH ativo à VPS dentro
desta sessão. Conforme o próprio `DEPLOY.md`, o deploy real é um passo manual
separado, com o git como fonte da verdade:
- copiar `carteiro.sh` para `/root/orquestracao/carteiro.sh` no host da VPS
  (conferir com `sha256sum`);
- copiar a pasta `skill-desbloqueio-vai/` para
  `/opt/data/skills/hermes-agent/desbloqueio-zona-vermelha/` no container Hermes.

Uma linha final: AVISO de espera via Telegram + resposta 'vai' desbloqueia - funcionando.
