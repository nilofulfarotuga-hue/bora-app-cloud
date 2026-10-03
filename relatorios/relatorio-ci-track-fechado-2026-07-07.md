# CI → track de TESTE FECHADO (alpha) — 2026-07-07

Branch: `autonomous-night-2026-04-29`. Objetivo: o CI passar a publicar **automaticamente no track
fechado** (onde estão os 12 testadores do 12×14 dias), em vez de só no interno.

## Track usado: `alpha` (teste fechado)

Confirmado **via Play Developer API** (não chutado), com a service account
`boraapp-d2bea-8abf3cc13bb0.json` sobre o package `pt.boraapp.bora`:

| Track | Release atual | versionCode | Estado |
|---|---|---|---|
| production | — | — | vazio |
| beta | — | — | vazio |
| **alpha** | `370 (1.0.1)` | **370** | completed ← **fechado, parado na 370** |
| internal | `1.0.1` | 382 | completed ← alvo antigo do CI |

O `alpha` é o track fechado ligado ao grupo `bora-app-testers@googlegroups.com` e estava **parado na
build 370** (promovida à mão) — por isso os testadores não recebiam os fixes (o CI só alimentava o
`internal`, já na 382). Já tem release ativa, portanto **não precisa de ação inicial no Play Console
UI**.

## Alteração no workflow (`.github/workflows/build_android.yml`)

Só o **step de publish** (step 11) + os nomes de display:
- `track: internal` → `track: alpha`
- `status: completed` mantido — **rollout 100%** (obrigatório; senão os testadores não recebem).
- Nome do job e do step: "Internal Testing" → "Closed Testing — alpha" (só rótulo, para o log não
  mentir).
- **Decisão (simples):** publicar **SÓ no fechado**. O `internal` deixa de ser alimentado — o Danilo
  também é tester do fechado, portanto não se perde cobertura. (A action `r0adkll/upload-google-play`
  é single-track; manter os dois exigiria um segundo upload do mesmo AAB — desnecessário.)

**NÃO tocado:** versionCode auto-increment (step 7/8), keystore, `key.properties`, dart-defines,
google-services, Flutter pin 3.41.2, caches. Zonas protegidas intactas.

## Prova do publish verde ✅

- Commit que disparou o CI: **`4519eac`** → run GitHub Actions **`28902669935`** —
  **conclusion = success** (run inteiro verde).
- Step de publish **"Upload to Google Play (Closed Testing — alpha)" → success**.
- **Confirmação independente via Play Developer API** (a prova mais forte — o artefacto aterrou mesmo
  no track fechado):

  | Track | Antes | Depois |
  |---|---|---|
  | **alpha** (fechado) | 370 | **383 — completed** ✅ |
  | internal | 382 | 382 (deixou de ser alimentado) |

  O track fechado saltou de 370 → **383**, rollout 100%. Os 12 testadores recebem agora a build 383
  automaticamente; daqui para a frente cada push nesta branch publica direto no fechado.

## Nota — o requisito 12×14 dias NÃO reinicia a cada update

Publicar uma **nova build no mesmo track fechado** (`alpha`) **não reseta os 14 dias**. O contador do
Google é sobre o **tempo de opt-in contínuo dos testadores** no programa de teste fechado, não por
release. Os 12 testadores continuam inscritos e a usar a app; cada nova build é só uma atualização
que eles recebem — o período de 14 dias segue a correr sem interrupção. (Só reiniciaria se se
removesse/religasse o track ou se saíssem/reentrassem os testadores.)
