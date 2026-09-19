# Diagnóstico — porque não aparece "Atualizar" no track fechado (alpha) — 2026-07-08

**Só diagnóstico** — não mexi em código, workflow nem publiquei nada. Dados obtidos ao vivo via Play
Developer API (service account `boraapp-d2bea`, package `pt.boraapp.bora`, `edits → tracks.get`).

## Resposta direta

| | Track | versionCode | status | rollout | pendente/draft? |
|---|---|---|---|---|---|
| **Fechado** | `alpha` | **384** | **completed** | **100%** (`userFraction: null`) | não |
| Interno | `internal` | 382 | completed | 100% | não |

- **A build no alpha está SÃ:** versionCode **384**, **completed**, **100%**, sem release em
  `draft`/`halted`/`inProgress`.
- **Não há build mais recente presa:** os bundles carregados vão até **384** (…382, 383, 384) e o
  384 é exatamente o que está no alpha. O #174 publicou o 384 no fechado, sem sobras em draft.
- **Grupos de testadores ligados ao alpha:** `bora-app-testers@googlegroups.com` e
  `khadem-testers-service@googlegroups.com`.
- **O `internal` NÃO tem grupos** (`googleGroups: null`) → o interno é gerido por **lista de emails
  individuais**, não por grupo.

→ Ou seja: **o problema NÃO é a publicação** (o 384 está live no fechado, 100%). O problema é do lado
da **inscrição/entrega ao dispositivo do Danilo**.

## Motivo provável (por ordem de probabilidade)

**(1) — MAIS PROVÁVEL — o telemóvel do Danilo está inscrito no track ERRADO (interno), não no
fechado.** Até hoje o CI alimentava o `internal` (chegou ao 382) e o `alpha` estava parado no 370.
Se o Danilo testava pelo **interno**, o telemóvel dele tem o **382** e aponta para o interno — que
**deixámos de atualizar** (continua no 382 = igual ao instalado → **sem "Atualizar"**). O **384** foi
para o **alpha**, que o telemóvel dele **não recebe** porque não está inscrito no teste fechado.
*(A pista técnica: o interno é lista de emails e o alpha é por grupo — são inscrições diferentes.)*

**(2)** Se ele **já estava no alpha** (tinha o 370): o email pode ter saído do grupo, **ou** é só
**cache/atraso da Play Store** — o update de teste fechado às vezes demora horas a aparecer no
cliente mesmo com rollout completo.

**(3)** Menos provável: já tem o 384 instalado (não é o caso se está no 382); ou release "em
revisão" na Google — improvável, porque 370/383/384 já chegaram todos a `completed` e o 370 já era
instalável (app aprovada para teste fechado, updates seguintes não voltam a rever).

> Nota: a Play Developer API **não** diz em que track está o dispositivo dele, nem lista os **membros**
> do grupo (só diz qual o grupo ligado). Por isso os pontos (1)/(2) confirmam-se no telemóvel + no
> Google Groups, não pela API.

## Ação recomendada (o Danilo decide/faz)

**Passo 1 — entrar no teste FECHADO (alpha) e verificar (2 min, no telemóvel do Danilo):**
1. Play Console → **Testes → Teste fechado → alpha → "Testadores" → "Como participar / Link para participar"** → copiar o **opt-in URL**.
2. No telemóvel, **com a MESMA conta Google** que está no grupo, abrir o link → **"Tornar-me testador / Become a tester"**.
3. Abrir a Play Store → Bora → deve passar a mostrar **Atualizar** para o 384 (pode levar alguns minutos).

**Passo 2 — confirmar o email no grupo:** em `groups.google.com`, confirmar que o email do Danilo é
**membro** de `bora-app-testers@googlegroups.com`. (A API confirma que o grupo está ligado ao alpha;
falta confirmar que o email dele está lá dentro.)

**Passo 3 — se ele JÁ estava no alpha e mesmo assim nada:** Play Store → Definições da app → **Forçar
paragem + Limpar cache** da Play Store, reabrir; ou esperar algumas horas (atraso do lado da Google).

**Atalho de teste:** se quiser confirmar já que é inscrição e não a build, instalar pelo **opt-in URL
do alpha** num dispositivo/conta que esteja no grupo → o 384 aparece. Se aparecer, está provado que a
publicação está correta e o assunto é só a inscrição/entrega.

## Conclusão

Publicação **OK** (alpha = 384, completed, 100%). O "sem Atualizar" é quase de certeza **inscrição no
track** (o Danilo está no interno/desatualizado ou fora do teste fechado), não a build. Sem alterações
a fazer no código/CI.
