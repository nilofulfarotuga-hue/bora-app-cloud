# Sessão 4C — TODOs adiados

**Criado**: 2026-05-04
**Branch**: autonomous-night-2026-04-29

## Pendentes desta sessão

- [ ] **`/ctx-upgrade` falhou** — `npm` não está no PATH do shell que `cli.bundle.mjs` invoca via `spawnSync`. v1.0.89 → v1.0.111 pendente. Fix futuro: adicionar `nodejs/npm` global ao PATH ou usar npx.
- [ ] **MEMORY.md desactualizada** — nomes reais das 7 tabelas suporte (`support_agent_actions/chatbot_*/settings/skills/tickets`) divergem do que prompt 4C assumia. Actualizar em retrospectiva 5A-1.
- [ ] **MarketProduct dead code** (`lib/models/business_view_models.dart:52`) — classe sem id, não usada para criar orders. Candidata a remoção em sessão housekeeping.
- [ ] **CartItem.fromJson fallback `?? name`** (linha 53) — tolerância consciente para legacy data em `orders.items`. Limpeza retroactiva = sessão dedicada.
- [ ] **Sessão 4C-β** — só necessária se Fase B descobrir mais call sites; relatório A indica que NÃO será preciso.

## Sessões futuras conhecidas

- [ ] **4B geo-push** (próxima sessão hoje)
- [ ] **5B agente IA write skills shadow**
- [ ] **5C pgvector RAG**
- [ ] **5A-2-γ smokes UI device** (Danilo configura quando PC OK)
- [ ] **Sessão 7 BUG 39** UUID/TEXT migration (`restaurants.id`, `products.id`, `orders.id`)
- [ ] **LIMPEZA 7 ORDENS ÓRFÃS HISTÓRICAS** (€5-6.50 cada)
  - Decisão necessária: refund automático via Stripe? deixar como está? marcar como cancelled?
  - Encaminhar para sessão dedicada com Danilo decidir
  - Identificadas em sessões anteriores (4 B5 + memória)
