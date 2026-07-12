---
id: skills-metrics
tipo: wiki
origem: [missão noturna 2026-07-09 Fase 3/5 — telemetria universal de skills]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# 📊 Skills — telemetria consolidada

> Cada SKILL.md com frontmatter de telemetria (`versao/execucoes/sucessos/falhas/
> ultima_execucao/criada_por`) regista aqui UMA linha por execução. O evolution-engine
> lê esta tabela (reescrever se falhas/execucoes > 30%; arquivar se 90d sem uso).
> **Cost lite (F2 2026-07-10):** quando estimável, acrescentar ao Resultado o
> `custo_estimado` (~€) pela heurística única em `permanente/semantica/loops.md`
> §Loop Economy (tokens ≈ caracteres/4 × preço do modelo).

| Skill | Data | Contexto | Volume | Resultado |
|---|---|---|---|---|
| diretor-criativo | 2026-07-10 | Campanha "O Bora chegou à Guarda" (prova real Fase 3) | 4 personas × 3 conceitos × 3 formatos = 36 artes (+5 refeitas no gate) + estrategia + copy + calendário | ✅ sucesso — gate anti-slop apanhou 5 violações e corrigiu |
| evolution-engine | 2026-07-10 | 1.ª execução real (prova Fase 5) — análise mecânica de 50 skills + auto-análise da noite | 26 propostas de padrão no inbox + draft v2 do diretor-criativo (restrições pré-geração) aplicado após Juiz (anti-trapaça CLEAN) | ✅ sucesso — ciclo criar→executar→medir→evoluir→julgar→versionar fechado na mesma noite |
| evolution-engine | 2026-07-12 | Fora-do-ciclo — ordem travada `ordem-20260712072627-d784` (mega-tarefa 5 partes, esgotou teto 5/5) | 2 propostas 🟢 curadas (skill `audit-address-autocomplete` + estender `market-data-cleaner` p/ entidades HTML) sobre 26 mecânicas; nota de orquestração (decompor mega-ordens) p/ maestro | ✅ sucesso — só propôs, nada aplicado; drafts esperam Juiz |
| evolution-engine | 2026-07-12 | Fora-do-ciclo — 2.ª ordem travada `ordem-20260712095002-aprv` (fallback aprovador-vermelho, tentativa 5 > teto 3, fila `nova` presa ~20 dias) | 1 proposta 🔴 SÓ-PROPOSTA (skill nova `triage-central-queue` p/ codificar Balde A/B) + achado operacional de higiene de loop (fallback por contagem re-dispara sobre backlog Balde B) encaminhado ao maestro | ✅ sucesso — só propôs, nada aplicado; skill 🔴 espera Danilo+Juiz |
| evolution-engine | 2026-07-12 | Fora-do-ciclo — 3.ª ordem travada `ordem-20260712082402-c287` (hook conclusão por evento; **falso-bloqueio**: deliverables entregues + self-test 7/7, ainda assim `travada` no teto 5/5 por scope-bundling) | 2 propostas 🟡 governança-de-loop (C287-1 decompor "mínimo-primeiro"; C287-2 guarda anti-falso-bloqueio no fecho) → Juiz; nota ao maestro p/ verificar+fechar a ordem | ✅ sucesso — só propôs, nada aplicado; drafts esperam Juiz |
| evolution-engine | 2026-07-12 | Fora-do-ciclo — 2 vigias `cron */10` travadas no mesmo tick (`ordem-...-aprv` + `ordem-...-e2e`, ambas `tentativa 5 > teto 3`); **falso-bloqueio por incompatibilidade executor↔tarefa** (aprv precisa JWT admin; e2e precisa PC local) | 3 propostas 🟡 governança-de-loop (AE2E-1 classe "vigia recorrente"≠deliverable; AE2E-2 hard-stop no teto; AE2E-3 capability-gate antes de retry) → Juiz; nota ao maestro p/ deferir/rotear as 2 ordens | ✅ sucesso — só propôs, nada aplicado; drafts esperam Juiz |
| evolution-engine | 2026-07-12 | Fora-do-ciclo — `ordem-20260712155505-evol`; ao seguir a cadeia: **loop auto-referencial** do `hermes-evolution-trigger.sh` (conta as próprias saídas `-evol` como "travadas novas" → ~30+ `-evol` em cadeia, 1/tick `*/5`, todas `travada`) | 2 propostas 🟡 governança-de-loop (EVOL-1 guarda anti-auto-referência `*-evol\|*-aprv\|*-e2e` no scan + draft patch; EVOL-2 coalescer disparos) → Juiz; nota operacional (deploy VPS + limpar backlog `-evol`) | ✅ sucesso — só propôs, nada aplicado; draft espera Juiz + deploy |
| prompt-blindado-validator | 2026-07-12 | Gate da missão de reengenharia da esteira (MODO PROTECÇÃO TOTAL) | Bloco 1 estrutura OK (MODO/CEO-AI/ctx/push); flag Bloco 2/5 = task C TVDE 🔴-adjacente → tratada PROPOSE-ONLY | ✅ validado — prosseguiu com execução (esteira endurecida + provada ponta-a-ponta) |
