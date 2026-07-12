# Lição: diálogos de permissão do Android travam o arranque da suite E2E

**Data:** 2026-07-11 · **Zona:** 🟢 verde (infra de teste) · **Estado:** atual

## O que aconteceu

O teste E2E arrancou com sucesso (o Danilo viu o telemóvel a mexer sozinho, o app
abriu na home com todas as categorias). A **parede final** era uma **permissão do
Android** (armazenamento) que o app pedia num diálogo e que ninguém tinha aceite —
o runner ficou **preso à espera de um toque humano**. O Danilo aceitou à mão e o
teste destravou.

## Causa raiz

Permissões de runtime (*dangerous permissions*) do Android — armazenamento,
localização, câmara, notificações — só são concedidas quando o utilizador toca
**"Permitir"** num diálogo. Num loop **headless/autónomo** não há ninguém para tocar,
então o Maestro fica bloqueado no primeiro diálogo e o fluxo nunca avança.

## Regra permanente

**Antes de correr a suite E2E, o runner concede automaticamente TODAS as permissões
do app via adb**, para nunca depender de um toque humano:

```
adb -s <serial> shell pm grant pt.boraapp.bora <permission>
```

Permissões concedidas (best-effort, uma a uma, tolerando erro):
`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`,
`CAMERA`, `POST_NOTIFICATIONS`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`,
`READ_MEDIA_IMAGES`, `RECORD_AUDIO`.

Permissões especiais (não são `pm grant` — usam `appops`):
```
adb -s <serial> shell appops set pt.boraapp.bora SYSTEM_ALERT_WINDOW allow
adb -s <serial> shell appops set pt.boraapp.bora REQUEST_IGNORE_BATTERY_OPTIMIZATIONS allow
```

## Onde está implementado

- **`.claude/testes-e2e/runner.py`** — `garante_permissoes(serial)`; chamado em `main()`
  logo após detetar o serial (single-device e multi-device), antes de correr os fluxos.
- **`.claude/testes-e2e/loop-noturno.py`** — `concede_permissoes(eventos)`; chamado em
  `garante_device()` assim que o device está presente (cobre o arranque via `run-tudo.cmd`).

## Notas operacionais

- Cada `pm grant` é **individual e idempotente** e **tolera erro** (permissão não
  declarada no manifesto, não-grantável, ou versão de Android que não a conhece) —
  o run **nunca aborta** por causa de uma permissão.
- Pacote do app: `pt.boraapp.bora` (override via env `E2E_APP_PACKAGE`).
- Provado a 2026-07-11: `dumpsys package pt.boraapp.bora` → `granted=true` para
  storage/media/camera/location/notifications após os grants.
- Em devices com **multi-utilizador** (perfil de trabalho), `pm list packages` pode dar
  `SecurityException: Shell does not have permission to access user <N>` — o `pm grant`
  no utilizador ativo continua a funcionar; ignora esse ruído.
