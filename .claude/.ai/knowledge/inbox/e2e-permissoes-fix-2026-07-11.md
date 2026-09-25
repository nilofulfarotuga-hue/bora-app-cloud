---
id: e2e-permissoes-fix-2026-07-11
tipo: relatorio
origem: [executor loop autónomo — fix permissões E2E]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# E2E — concessão automática de permissões Android (fix da parede final)

## Contexto

O teste E2E arrancou com sucesso (telemóvel a mexer sozinho, app na home com todas
as categorias). A parede final era um **diálogo de permissão do Android (armazenamento)**
que travava o arranque à espera de toque humano. O Danilo aceitou à mão e destravou.

## O que foi feito

1. **Auto-grant de permissões via adb** — o runner concede todas as permissões de
   runtime do app **antes** de correr os fluxos, para nunca depender de um toque:
   - `runner.py` → `garante_permissoes(serial)`, chamado em `main()` após detetar o
     serial (single-device **e** multi-device).
   - `loop-noturno.py` → `concede_permissoes(eventos)`, chamado em `garante_device()`
     assim que o device está presente (cobre o arranque via `run-tudo.cmd` →
     `loop-noturno.py`, que é a cadeia real; `run-tudo.cmd` só invoca o python).
   - Permissões: FINE/COARSE/BACKGROUND_LOCATION, CAMERA, POST_NOTIFICATIONS,
     READ/WRITE_EXTERNAL_STORAGE, READ_MEDIA_IMAGES, RECORD_AUDIO. Especiais via
     `appops`: SYSTEM_ALERT_WINDOW, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS.
   - Cada grant é **individual, idempotente e tolera erro** → o run nunca aborta.
   - Pacote: `pt.boraapp.bora` (override via env `E2E_APP_PACKAGE`).

2. **Lição permanente** gravada em
   `wiki/licoes/e2e-permissoes-android-bloqueiam-arranque.md`.

## Validação

- `py_compile` limpo em `runner.py` e `loop-noturno.py`.
- Comandos de grant testados no device real `RZGYB1XQD2P`:
  `dumpsys package pt.boraapp.bora` → `granted=true` para storage, media, camera,
  location e notifications. Confirmado que a nova rotina funciona.
- Nota: em device multi-utilizador, `pm list packages` dá `SecurityException` (user 150);
  não afeta os grants no utilizador ativo.

## Estado atual do teste (NÃO foi parado)

- Tarefa agendada do Windows **`\BoraE2E_LoopNoturno`** viva — re-corre de hora a hora
  (próxima execução 14:38). O fix entra em efeito no próximo ciclo agendado.
- 2 devices ligados no adb: `N75LTG5X5DSKDMV4`, `RZGYB1XQD2P`.
- Último ciclo (loop-noturno-2026-07-11.json, fim:True):

| Fluxo | Estado |
|---|---|
| ✅ smoke-login-cliente | PASSOU (2 verdes seguidos, estável) |
| ✅ login-estafeta | PASSOU (2 verdes seguidos, estável) |
| ❌ delivery-mercado-cash | BUG-APP-REGISTADO |
| 📱📱 tvde-corrida-cliente-motorista | MANUAL-2-DEVICES (precisa 2 telemóveis em tempo real) |

- **delivery-mercado-cash** (o fluxo com prova real na tabela `orders`): a app **abriu
  e navegou bem** (Início → Supermercados → Continente → produto). A falha é de
  **selector do Maestro**: após tocar no produto, o passo `Adicionar.*` ficou SKIPPED
  e depois `Tap on .*[Cc]arrinho.*` → *Element not found*. **Não é permissão** — é o
  botão de carrinho/adicionar do YAML que não bateu. Já esgotou as 2 afinações de
  timing e ficou registado para o loop de ordens (o loop noturno não corrige código
  da app). Ainda **sem prova real de pedido em `orders`** por causa deste selector.

## Próximo passo (sozinho, sem parar)

O loop agendado segue vivo. Com as permissões agora concedidas automaticamente, o
próximo arranque não fica preso no diálogo. O bloqueio restante do
`delivery-mercado-cash` é de **selector do carrinho** (YAML), fora do âmbito deste
fix de permissões — fica sinalizado para afinar o passo do carrinho/adicionar.

## Ficheiros tocados

- `.claude/testes-e2e/runner.py` (novo `garante_permissoes` + chamadas em `main()`)
- `.claude/testes-e2e/loop-noturno.py` (novo `concede_permissoes` + chamada em `garante_device`)
- `wiki/licoes/e2e-permissoes-android-bloqueiam-arranque.md` (lição permanente)
- `.claude/.ai/knowledge/inbox/e2e-permissoes-fix-2026-07-11.md` (este relatório)
