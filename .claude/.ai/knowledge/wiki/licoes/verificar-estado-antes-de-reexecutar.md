---
id: licao-verificar-estado-antes-de-reexecutar
tipo: licao
origem: [sessão 2026-07-08: Fase 1A já estava feita+commitada por sessão concorrente na branch autonomous-night]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Lição — antes de reexecutar, verificar o **estado real** (verificar > reexecutar)

**Problema.** Ao arrancar a "Fase 1A", o disco já tinha `_importado-velho/` e o vault com 150 .md
(a Fase 0 minutos antes vira 117). Ia-se **reexecutar** e criar imports/commits duplicados.

**Tentativas que teriam falhado.** Assumir o plano e copiar órfãos "de novo" → duplicação, conflitos.

**Porquê.** A branch `autonomous-night-2026-04-29` corre com **sessões autónomas concorrentes**.
Uma delas já tinha executado e **commitado** a Fase 1A (`0b44734`, `ffe08c5`, `f41429e`).

**Solução (regra generalizável).** Antes de agir numa branch autónoma:
`git log --oneline -8` + `git status` + comparar o disco com o relatório. Se o trabalho **já existe**,
**verificar** (é correto? completo? aplicado no VPS?) em vez de **reexecutar**. Confirmar antes de
sobrescrever — se o que se encontra contradiz o descrito, **reportar**, não prosseguir às cegas.
