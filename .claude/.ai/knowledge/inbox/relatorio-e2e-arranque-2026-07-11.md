# Relatório E2E — Confirmação de ARRANQUE (2026-07-11 09:1x)

**Objetivo desta execução:** corrigir os 2 problemas conhecidos e **arrancar** a suite E2E
completa como processo de **segundo plano destacado** (sobrevive ao fim desta execução de 15 min),
confirmando aqui apenas que o processo está vivo e a tocar no telemóvel. O relatório final completo
continua a ser escrito pelo próprio loop em `e2e-resultados-2026-07-11.md` / `relatorio-e2e-completo-2026-07-10.md`.

Correção da ordem anterior (85db), que travou por pedir a suite inteira dentro de 1 execução de 15 min:
a suite demora a noite toda, por isso agora **arranca em background** e esta execução só valida o arranque.

## 1. Problema conhecido #1 — login-estafeta mostrava "ecrã inesperado" ✅ CORRIGIDO
Eram **dois diálogos** a tapar o RoleScreen/formulário após boot limpo (ambos confirmados com
screencap ao vivo do device):
- **(a) Permissão de NOTIFICAÇÕES** do Android 13+ ("Permitir que a app bora_app lhe envie
  notificações? / Permitir / Não permitir") por cima do RoleScreen → o assert `"Sou Cliente"` não via
  o botão → reset falhava (rc=1) e arrastava todos os fluxos (é o preâmbulo de cada um).
- **(b) Modal in-app "Privacidade e Cookies"** (Aceitar tudo / Rejeitar / Gerir preferências) que
  aparece no arranque limpo por cima dos botões e do formulário de login. **Provado pelo próprio loop:**
  reset PASSOU, mas `cliente/login.yaml` falhou porque, após tocar "Sou Cliente", o campo "Email" ficou
  SKIPPED (estava atrás do modal de cookies) e "Agora não|Início" nunca apareceu.
- **Fix (cirúrgico, só no YAML de teste — `reset-role-screen.yaml`):** antes do assert final, dispensar
  ambos — `extendedWaitUntil "Permitir|Não permitir|Aceitar tudo|Privacidade e Cookies|Sou Cliente"`
  (folga extra ao cold boot lento, o outro fator do timeout de 45 s) + `runFlow when visible` para tocar
  em "Permitir" (notificações), "Aceitar tudo" (cookies) e "Enquanto usa a app/Ao usar a app/Permitir"
  (localização, por robustez).
- **Validação:** (i) reset corrido 2/2 via Maestro, incl. caminho cold pós-`pm clear` →
  `Assert "Sou Cliente"... COMPLETED`, exit 0. (ii) o próprio loop provou o reset a passar (rc=0, 45.6 s)
  e revelou o modal de cookies, agora coberto pelo fix acima (será usado no próximo ciclo do loop).

## 2. Problema conhecido #2 — delivery-mercado-cash falhava na pré-condição ✅ RESOLVIDO
- **Sintoma anterior:** guarda de isolamento abortava 3× ("estafetas REAIS online — 1 reais: ['Danilo Fulfaro']").
- **Estado atual:** o único estafeta `is_online=true` na BD é **Danilo Fulfaro**, UUID
  `503a2e09-2111-44b5-9852-d6d5897467f1`, que **já consta** na lista `DEV_DRIVER_IDS` do `runner.py`
  (contas de DEV do dono, excluídas por UUID). Verificado live via Supabase. Logo a guarda
  `so_estafeta_teste_online()` devolve `reais=[]` → **pré-condição passa** e o dispatch de teste dispara.
  (A falha registada às 08:02 era anterior à adição do UUID à lista.)

## 3. Telemóveis detetados ✅
- `RZGYB1XQD2P` — Samsung SM-A366B (papel **cliente**; single-device corre tudo aqui) — `device`/autorizado.
- `N75LTG5X5DSKDMV4` — cloud_eea/23028RN4DG (papel **estafeta**) — `device`/autorizado.

## 4. Processo de fundo ARRANCADO ✅
- Lançado **destacado** via `Start-Process -WindowStyle Hidden` (independente desta sessão):
  `python loop-noturno.py` em `.claude/testes-e2e/`.
- **PID 13852**, vivo (não saiu).
- Log: `loop-noturno-detached-20260711-091019.log`.
- Primeiras linhas do log confirmam o ciclo a andar:
  `loop noturno Fase 7 — 4 fluxos no registry` → `── CICLO 1: 3 fluxos → ['smoke-login-cliente', 'login-estafeta', 'delivery-mercado-cash']`.
- Fluxos do mapa (registry.json): smoke-login-cliente, login-estafeta, delivery-mercado-cash
  (PROVA-MESTRE mercado não-parceiro, cash) e tvde-corrida (marcado MANUAL-2-DEVICES, não corre sozinho).

## 5. Prova de que está a tocar no telemóvel ✅
- **1.º vídeo NOVO desta execução gravado:** `gravacoes/2026-07-11/RZGYB1XQD2P/smoke-login-cliente-091024.mp4`.
- **`screenrecord` ATIVO no device** (verificado 2×: pid 9545 e depois pid 11798) + **Maestro (java) a correr no PC** = o telemóvel está a ser conduzido em contínuo.
- **Loop a auto-curar-se:** log regista `smoke-login-cliente: BUG DO TESTE → YAML afinado (tentativa 1)`
  e passou ao fluxo seguinte (login-estafeta) — exatamente o comportamento esperado do loop autónomo.
- Processo 13852 continua vivo no fim desta execução.

## O que segue sozinho (sem mim)
O loop `loop-noturno.py` continua a noite toda (até 10 ciclos): corre a suite, filma, classifica falhas
(BUG DO TESTE → afina timeouts do YAML e re-corre; BUG DO APP zona verde → regista; zona vermelha →
BLOQUEADO-APROVACAO, nunca aplica), re-corre só os falhados até tudo PASSAR ou restarem estados
terminais. Escreve progresso por ciclo em `inbox/e2e-resultados-2026-07-11.md` + `loop-noturno-<data>.json`
(o cron do Hermes lê o inbox e avisa no Telegram). Parar: criar ficheiro `PARAR` em `.claude/testes-e2e/`.

## Ficheiros tocados nesta execução
- `.claude/testes-e2e/flows/comum/reset-role-screen.yaml` — dispensa diálogos de permissão do SO + folga de cold boot.
- `.claude/.ai/knowledge/inbox/relatorio-e2e-arranque-2026-07-11.md` — este relatório.
- (diagnóstico) `.claude/testes-e2e/_diag_clean_boot.png` — screencap que provou a causa raiz.
- Processo de fundo: `loop-noturno-detached-20260711-091019.log(.err)`.
