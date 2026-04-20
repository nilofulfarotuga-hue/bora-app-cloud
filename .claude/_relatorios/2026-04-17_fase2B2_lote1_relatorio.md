# RELATÓRIO FASE 2.B.2 — LOTE 1 (CÉREBRO)

**Data:** 2026-04-17
**Modo:** PROTECÇÃO TOTAL
**Escopo:** Camada 1 (Cérebro) — 5 skills
**Source of truth:** `.claude/.ai/business_rules.md` v2 (906 linhas, 26 secções)

---

## 1. Backup

- **Localização:** `.claude/_backups/2026-04-17_fase2B2_lote1/`
- **5 ficheiros preservados:**
  - decision_engine.md (222 linhas)
  - decision_registry.md (164 linhas)
  - learning_engine.md (141 linhas)
  - memory.md (115 linhas)
  - product_analyst.md (113 linhas)
- **Total preservado:** 755 linhas (estado pré-transformação).

---

## 2. Skills modificadas

### 2.1 decision_engine.md
- **Antes / depois:** 222 / 222 linhas · v1.1.0 / v1.1.0 (sem alteração)
- **Estado:** já previamente transformado para v1.1.0 na Fase 2.B.1.
  Cumpre todos os requisitos do Lote 1 sem necessidade de nova edição.
- **Verificação:**
  - ✅ `protection_mode: read-only`
  - ✅ 2 Exemplos Worked (timeout 40→30s · barbearia ao domicílio)
  - ✅ Secção REFERÊNCIAS BORA APP
  - ✅ Secção BENCHMARK UBER / IFOOD / GLOVO
  - ✅ Referências BR §X em vez de valores hardcoded
  - ✅ Secções originais (RESPONSABILIDADES, NÃO PODE FAZER, FRONTEIRAS, RULES) preservadas

### 2.2 decision_registry.md
- **Antes / depois:** 164 / 304 linhas · v1.1.0 → **v1.2.0**
- **Adicionado:**
  - Secção EXEMPLOS WORKED com 2 cenários (FIFO 200→300 m · timeout actual)
  - Secção REFERÊNCIAS BORA APP (tabela com 8 recursos)
  - Secção BENCHMARK UBER / IFOOD / GLOVO
  - Nova secção ZONAS PROTEGIDAS (espelho de BR §25.3)
- **Regenerado como espelho completo de BR v2:**
  - DISPATCH (§6): motor, ordem de seleção, raio FIFO, timeout, stacking, batching, guard, multi-stop
  - SLA (§9.1): base, crítico, raio preferido
  - BATCHING / STACKING (§6.4): máximo, critério, diálogo
  - PAGAMENTO (§2 · §3 · §8.3): métodos, limite dinheiro, buffer Stripe, markup, taxas, sacos, cancelamentos, payout
  - TOKENS (§4): ganho, cashback, conversão, expiração, consumo, tetos, prioridade driver, gorjetas
  - DRIVER HELP (§5.2)
  - REMUNERAÇÃO DO ESTAFETA (§5)
  - RESERVA DE MESA (§14) — nova secção
  - MARKETPLACE (§17) — nova secção
  - LIMPEZA (§18) — nova secção
  - ESTADOS (§1.3 · §1.4)
- **Divergências corrigidas face à versão anterior** (BR v2 venceu em todas):
  - Cancel antes dispatch: 1,50€ → **€1,00** (BR §8.3)
  - Cancel após aceite: 50% → **€2,50** taxa entrega (BR §8.3)
  - Batching pré-filtro 15 km (removido — BR §6.4 tem apenas 3 km entre lojas)
  - SLA extensão +5 min / total 15 min (removido — não existe em BR v2)
  - "50% do TOTAL incluindo taxas" → **até 50% do valor do pedido** (BR §4.3)

### 2.3 learning_engine.md
- **Antes / depois:** 141 / 243 linhas · v1.0.0 → **v1.1.0**
- **Adicionado:**
  - Frontmatter `protection_mode: read-only`
  - 2 Exemplos Worked (cluster temporal pg_cron/payout · concentração por estafeta 60%)
  - Secção REFERÊNCIAS BORA APP (8 recursos incluindo `git log`, `lib/stores/`, `lib/dispatch/`)
  - Secção BENCHMARK UBER / IFOOD / GLOVO
  - Padrões TEMPORAIS e PER-PERSON na lista de ANALYSIS PATTERNS
  - DATA SOURCES expandido (git log + business_rules.md)
- **Regras reforçadas:**
  - Proibido modificar `memory_store.md` directamente (delegar a `memory`)
  - Delegação explícita para `memory` persistir novos padrões
- **Secções originais preservadas.**

### 2.4 product_analyst.md
- **Antes / depois:** 113 / 230 linhas · v1.0.0 → **v1.1.0**
- **Adicionado:**
  - Frontmatter `protection_mode: read-only`
  - 2 Exemplos Worked (Favoritos de restaurantes · Moradas recentes no checkout)
  - Secção REFERÊNCIAS BORA APP (10 recursos — screens, stores, BR secções)
  - Secção BENCHMARK UBER / IFOOD / GLOVO (RICE, Customer Feedback Board, Friction Map)
  - Novo campo obrigatório no formato de sugestão: `**BR compatível?**`
  - KNOWN SYSTEM CONTEXT agora referencia BR §X em cada item
- **Substituições hardcoded → BR refs:**
  - `TOKEN_MAX_DISCOUNT_RATIO = 0.50` → "até 50% do pedido (ver BR §4.3)"
  - Service types → BR §1.2
  - Payment methods → BR §3.1 · §3.2 · §3.3
  - Pricing (markups, taxa entrega, apartamento) → BR §2.1 · §2.3 · §2.4
  - Driver UX (offer 40 s, checklist, código 4 dígitos) → BR §6.3 · §7.1 · §7.3 · §7.4
  - Client UX → BR §8.1–§8.6
- **Roles expandidos:** adicionado `partner` e `admin` (antes apenas `client, driver`).
- **Secções originais preservadas.**

### 2.5 memory.md
- **Antes / depois:** 115 / 215 linhas · v1.0.0 → **v1.1.0**
- **Adicionado:**
  - Frontmatter `protection_mode: read-write-append-only`
  - 2 Exemplos Worked (Registar SLA crítico 7 min · Registar bug map_master)
  - Secção REFERÊNCIAS BORA APP (7 recursos)
  - Secção BENCHMARK UBER / IFOOD / GLOVO (Decision Log, Knowledge Base, Incident Journal)
  - Novo campo `BR REF: §X` no WRITE FORMAT para decisões, patterns e regras
  - Novo campo `FICHEIROS:` e `DATA:` no formato de BUG
  - Regra: cruzar memory vs BR v2 antes de escrever; BR vence em divergência
  - Regra: não duplicar conteúdo que já existe em BR v2 (preferir referência §X)
- **Secções originais preservadas.**

---

## 3. Verificação global

| Critério | decision_engine | decision_registry | learning_engine | product_analyst | memory |
|---|:-:|:-:|:-:|:-:|:-:|
| Frontmatter `protection_mode` | ✅ read-only | ✅ read-only | ✅ read-only | ✅ read-only | ✅ read-write-append-only |
| EXEMPLOS WORKED (≥2) | ✅ | ✅ | ✅ | ✅ | ✅ |
| REFERÊNCIAS BORA APP | ✅ | ✅ | ✅ | ✅ | ✅ |
| BENCHMARK UBER/IFOOD/GLOVO | ✅ | ✅ | ✅ | ✅ | ✅ |
| Hardcoded → BR §X | ✅ | ✅ (espelho completo) | n/a | ✅ | n/a |
| Secções originais preservadas | ✅ | ✅ | ✅ | ✅ | ✅ |
| Versão incrementada | — (já 1.1.0) | → 1.2.0 | → 1.1.0 | → 1.1.0 | → 1.1.0 |

### Invariantes respeitadas
- ✅ Código Bora App (`lib/`, `supabase/`) **NÃO** foi tocado
- ✅ `business_rules.md` v2 **NÃO** foi tocado
- ✅ Outras skills fora do Lote 1 **NÃO** foram tocadas
- ✅ Backup íntegro em `.claude/_backups/2026-04-17_fase2B2_lote1/`
- ✅ Todas as referências `BR §X` verificadas contra BR v2 (2026-04-17)

---

## 4. Observações

### Padrões detectados nas 5 skills
- **Separação clara de papéis está sólida:** `decision_engine` decide, `decision_registry` consulta, `learning_engine` detecta, `product_analyst` sugere, `memory` persiste. Sem sobreposição crítica.
- **Delegação cruzada documentada em todas:** cada skill tem secção FRONTEIRAS que aponta para as outras 4. Coerente após transformação.
- **BR §X é agora a "moeda comum"** entre as 5 skills — qualquer facto travado tem ref.

### Duplicações residuais
- `decision_registry` e `memory` têm papéis complementares mas próximos.
  Mantidos separados com notas explícitas: registry é **índice travado**, memory é **histórico cronológico append-only**. Diferença documentada em ambas.
- `learning_engine` e `memory` interagem: learning lê, memory escreve. Delegação agora explícita (learning_engine não escreve directamente).

### Dúvidas arquiteturais
- `memory_store.md` está referenciado mas não foi inspeccionado no Lote 1 (está em `.claude/.ai/memory/` — fora do escopo do lote).
  Sugestão para Lote 2 ou separado: verificar se `memory_store.md` está de facto em uso e se a sua estrutura bate com o WRITE FORMAT desta skill.
- `product_analyst` é a única skill com role fortemente especulativa (sugere features). Pode beneficiar no futuro de integração com um "backlog" persistente — hoje sugestões vivem só no turno actual.

---

## 5. Próximo passo

**Lote 2 — Camada de Controle:**
- `.claude/.ai/skills/guardian.md`
- `.claude/.ai/skills/flow_guard.md`
- `.claude/.ai/skills/refactor_guard.md`
- `.claude/.ai/skills/state_validator/` (subdirectório)

Mesma transformação (protection_mode, exemplos, referências, benchmark, subst. hardcoded).

---

*Relatório — Fase 2.B.2 Lote 1 (Cérebro) — 2026-04-17*
