---
id: e2e-resultados-2026-07-11
tipo: relatorio
origem: [loop-noturno E2E testes-e2e (Fase 7 single-device)]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# Loop Noturno E2E — 2026-07-11: 0/4 verdes (TERMINADO)

## Estado por fluxo
- 🐛 **smoke-login-cliente** — BUG-APP-REGISTADO · verdes seguidos: 0 · afinações: 1
- 🐛 **login-estafeta** — BUG-APP-REGISTADO · verdes seguidos: 0 · afinações: 1
- 🐛 **delivery-mercado-cash** — BUG-APP-REGISTADO · verdes seguidos: 0 · afinações: 1
- 📱📱 **tvde-corrida-cliente-motorista** — MANUAL-2-DEVICES · verdes seguidos: 0 · afinações: 0 · exige 2 telemóveis em tempo real

## Ciclos
- ciclo 1: corridos 3 → 0 PASSOU / 3 FALHOU (133.4s)
- ciclo 2: corridos 3 → 0 PASSOU / 3 FALHOU (128.5s)

## YAMLs de teste afinados pelo loop (NUNCA código da app)
- comum/reset-role-screen.yaml: timeouts ×1.5
- comum/reset-role-screen.yaml: timeouts ×1.5
- comum/reset-role-screen.yaml: timeouts ×1.5

## Bugs do APP para o Danilo/loop de ordens (o loop NÃO corrige a app)
- **smoke-login-cliente** (BUG-APP-REGISTADO): `{'yaml': 'comum/reset-role-screen.yaml', 'serial': 'N75LTG5X5DSKDMV4', 't_epoch': 1783802453.536542, 'tail': '[stderr]\nPicked up JAVA_TOOL_OPTIONS: -Xmx768m\nPicked up JAVA_TOOL_OPTIONS: -Xmx768m\nDevice N75LTG5X5DSKDMV4 was requested, but it is not connected.'}`
- **login-estafeta** (BUG-APP-REGISTADO): `{'yaml': 'comum/reset-role-screen.yaml', 'serial': 'N75LTG5X5DSKDMV4', 't_epoch': 1783802496.1291502, 'tail': '[stderr]\nPicked up JAVA_TOOL_OPTIONS: -Xmx768m\nPicked up JAVA_TOOL_OPTIONS: -Xmx768m\nDevice N75LTG5X5DSKDMV4 was requested, but it is not connected.'}`
- **delivery-mercado-cash** (BUG-APP-REGISTADO): `{'yaml': 'comum/reset-role-screen.yaml', 'serial': 'N75LTG5X5DSKDMV4', 't_epoch': 1783802538.396475, 'tail': '[stderr]\nPicked up JAVA_TOOL_OPTIONS: -Xmx768m\nPicked up JAVA_TOOL_OPTIONS: -Xmx768m\nDevice N75LTG5X5DSKDMV4 was requested, but it is not connected.'}`
