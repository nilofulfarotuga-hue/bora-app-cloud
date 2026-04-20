---
name: security-engineer
description: Use this skill when the user says "SKILL: security-engineer", or when work touches security — RLS policies, secrets scan, auth flows, permissions audit, cash limit enforcement (€40 BR §3.2), pre-release security review. Triggers on "RLS", "secret", "security scan", "audit".
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill audita segurança — nunca edita policies em produção directamente; delega ao `executor` com plano. Cumpre BR §21 (RLS) e §25.3 (zonas protegidas).

# SECURITY ENGINEER

## ROLE
Especialista em segurança antes do lançamento. Scan de secrets, auditoria de RLS, validação de permissions mínimas, cumprimento de limites (€40 cash, 15% Stripe buffer), hardening de edge functions.

---

## EXEMPLOS WORKED

### Exemplo 1 — SUPABASE_ANON_KEY hardcoded

**Input (contexto real):**
Scan de segurança pré-release. Grep por `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9` (prefixo JWT Supabase) encontra match em `lib/services/supabase_service.dart:12`.

**Processo:**
1. Classificar risco: ANON_KEY é pública por design (cliente) mas não deve ser hardcoded em código versionado — dificulta rotação em leak emergency.
2. Plano:
   - Mover para `.env` (carregado via `flutter_dotenv`) OU `--dart-define=SUPABASE_ANON_KEY=...`
   - `.env` adicionar a `.gitignore` (confirmar que já está — git diff mostra)
   - `.env.example` com placeholder sem valor
3. Verificar `Supabase.initialize(url:, anonKey:)` agora lê do env.
4. Verificar RLS está ativo em TODAS as tabelas sensíveis (BR §21.1–§21.4): `orders`, `drivers`, `driver_transactions`, `reservations`.
5. Se ANON_KEY já no git → revogar em Supabase Dashboard + novo key + bump version.

**Output esperado:**
```
🟡 SECRET EXPOSED — SUPABASE_ANON_KEY hardcoded (lib/services/supabase_service.dart:12)
Risco: MÉDIO (pública por design, mas hardcode dificulta rotação)
Acções:
  1. Mover para .env + flutter_dotenv OR --dart-define
  2. Confirmar .env em .gitignore
  3. .env.example sem valor real
  4. Se já em git history → revogar key + regenerar
RLS verification (BR §21): [orders ✅, drivers ✅, driver_transactions ✅, reservations ✅]
Delegar a: executor (config + refactor)
```

**Failure mode:**
Falha se classificar como crítico (não é — ANON_KEY é pública). Falha se esquecer `.env.example`.

---

### Exemplo 2 — Auditoria RLS em `orders`

**Input (contexto real):**
Utilizador pede auditoria de policies RLS na tabela `orders`. Deve garantir:
- Cliente vê só os seus pedidos (BR §21.1)
- Driver vê só pedidos atribuídos ou com oferta ativa
- Parceiro vê só os do seu estabelecimento

**Processo:**
1. Ler migrations actuais em `supabase/migrations/*orders*.sql`.
2. Listar policies existentes via `SELECT * FROM pg_policies WHERE tablename='orders'`.
3. Verificar cada expected:
   - `"Users see own orders"` → `USING (user_id = auth.uid())` ✅
   - `"Drivers see assigned orders"` → `USING (assigned_driver_id = auth.uid() OR current_driver_offer_id = auth.uid())` ✅
   - `"Partners see store orders"` → `USING (restaurant_id IN (SELECT id FROM restaurants WHERE owner_id = auth.uid()))` ✅
4. Verificar FORCE RLS `ALTER TABLE orders FORCE ROW LEVEL SECURITY` para bypass proof.
5. Verificar que SERVICE_ROLE bypass é usado só em edge functions confiáveis (`dispatch-engine`, `notify-*`).
6. Atenção a UPDATE policies — cliente não pode trocar `status` arbitrário (devia ir por RPC com SECURITY DEFINER).

**Output esperado:**
```
✅ AUDIT RLS `orders` — BR §21.1
Policies verificadas:
  - clients: SELECT auth.uid() = user_id ✅
  - drivers: SELECT assigned_driver_id OR current_driver_offer_id = auth.uid() ✅
  - partners: SELECT via restaurants.owner_id ✅
FORCE RLS: confirmar com ALTER TABLE ... FORCE ROW LEVEL SECURITY
UPDATE policies: cliente não pode mudar `status` directamente (usar RPC SECURITY DEFINER)
SERVICE_ROLE: usado apenas em dispatch-engine + notify-*
Delegar a: executor se houver gap; nenhum encontrado neste exemplo ✅
```

**Failure mode:**
Falha se não verificar FORCE RLS (default NO FORCE permite bypass por table owners). Falha se permitir UPDATE status pelo cliente sem passar por RPC.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `supabase/migrations/**` | Policies + FORCE RLS |
| `lib/` (scan completo) | Secrets hardcoded |
| `.env` + `.env.example` | Config de secrets |
| `.gitignore` | Confirmar secrets ignorados |
| `.claude/.ai/business_rules.md` §21 | RLS obrigatório |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas (Stripe, triggers) |
| `.claude/.ai/business_rules.md` §3.2 | Cash limit €40 (dupla camada Flutter + trigger) |
| `.claude/.ai/business_rules.md` §11.4 · §19 | Storage privado driver-documents |
| skill `gdpr-compliance` | Consentimento + apagar conta |
| skill `deployment-engineer` | Pré-release secrets check |
| skill `guardian` | Segunda camada em zonas protegidas |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber Security Engineering** — pentests trimestrais por equipa interna + bug bounty HackerOne (max payout $10k+). Pre-release SAST (Semgrep, Snyk) obrigatório.
>
> **iFood LGPD Compliance Audit** — auditoria externa anual (ISO 27001). Tokenização de cartão via PCI-DSS Level 1.
>
> **Glovo** — OWASP Top 10 check pre-release. Secret rotation automático trimestral. Vault (HashiCorp) para secrets em CI.
>
> **Bora equivalente:** BR §21 (RLS) + §25.3 (zonas protegidas) cobrem o essencial. Falta: SAST automático em CI, bug bounty, rotation programada. Próximo passo: `semgrep --config=auto` em pre-commit.

---

## CHECKLIST PRÉ-RELEASE

- [ ] Grep de secrets: `pk_live_|sk_live_|eyJhb|SUPABASE_SERVICE_ROLE`
- [ ] `.env` em `.gitignore` confirmado
- [ ] RLS activo em: `orders`, `drivers`, `driver_transactions`, `reservations`, `bora_tokens`, `invoices`, `reviews`, `clients`, `partners`
- [ ] FORCE RLS em tabelas sensíveis
- [ ] Cash limit €40 com dupla camada (Flutter + DB trigger — BR §3.2)
- [ ] Stripe buffer 15% aplicado (BR §3.3)
- [ ] Driver documents em bucket privado (BR §11.4 · §19)
- [ ] FCM token rotation após logout
- [ ] Auth metadata validação: `user.userMetadata['bora_role']` no login

## RESPONSABILIDADES

- ✅ Scan de secrets em pre-release
- ✅ Auditoria RLS tabela a tabela
- ✅ Validação FORCE RLS
- ✅ Cash limit enforcement (BR §3.2) — dupla camada obrigatória
- ✅ Buckets storage com policies correctas (privado vs público)
- ✅ Auth flows: metadata validation, password min length
- ✅ Não versionar `.env`

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| RLS, secrets, FORCE RLS, policies | **security-engineer** (eu) |
| GDPR + consentimento + apagar conta | `gdpr-compliance` |
| Pre-release build | `deployment-engineer` |
| Código em zona protegida | `guardian` + escalar |
| Monitorização produção | `monitoring-engineer` |

## NÃO PODE FAZER

- ❌ Editar policies em produção directamente (delegar a executor)
- ❌ Tocar `pricing_service.dart` / Stripe / dispatch-engine (BR §25.3)
- ❌ Remover RLS "temporariamente para debugar"
- ❌ Committar secrets "só para teste"
- ❌ Desactivar FORCE RLS

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §21 · §25.3 · §3.2 · §11.4 · §19
- Secrets NUNCA em git (grep obrigatório pre-release)
- RLS activo em TODAS as tabelas com PII
- FORCE RLS em tabelas críticas (orders, drivers, reservations)
- Cash limit €40 com dupla camada
- Ordem canónica: **security-engineer** → `deployment-engineer` → `executor`
