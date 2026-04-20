---
name: gdpr-compliance
description: Use this skill when the user says "SKILL: gdpr-compliance", or when a task touches consent, cookie banner, account deletion, data export, or anything under BR §20 (GDPR / proteção de dados). Also triggers for "apagar conta", "banner cookies", "consentimento", "LGPD/GDPR".
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill planeia conformidade GDPR — nunca apaga dados directamente; delega execução ao `executor`. Qualquer prazo legal (10 anos fiscais, 30 dias de resposta) vem da BR v2 §20.

# GDPR COMPLIANCE

## ROLE
Especialista em GDPR e protecção de dados. Garante que o app respeita o Regulamento (UE) 2016/679 e as obrigações AT portuguesas (faturas 10 anos).

---

## EXEMPLOS WORKED

### Exemplo 1 — Utilizador pede apagar conta

**Input (contexto real):**
Cliente em `profile_screen.dart` → "Apagar conta". Cliente tem 14 pedidos nos últimos 8 meses, 2 dos quais com fatura emitida.

**Processo:**
1. Consultar BR §20.2 → separação dupla:
   - **Apagar imediato:** nome, foto, telefone, endereços, chat, avaliações dadas, tokens
   - **Guardar 10 anos:** faturas (nº, valor, data, NIF), extractos fiscais, comprovativos Stripe (obrigação AT)
2. Substituir nome em pedidos antigos → "Utilizador apagado"
3. Mostrar aviso obrigatório BR §20.2: "Os teus dados pessoais serão apagados imediatamente. Por obrigação legal, os dados fiscais (faturas) são guardados por 10 anos. Confirmar?"
4. Plano de RPC Supabase: `delete_user_personal_data(user_id)` — preserva `invoices` table + anonymiza `orders.customer_name`.
5. Hard delete no Supabase Auth → sign out forçado → redirect para role screen.

**Output esperado:**
```
✅ PLANO APAGAR CONTA — BR §20.2
Apaga imediato: perfil, fotos, chat, avaliações, tokens, addresses
Preserva 10 anos: invoices, payment_receipts (obrigação AT)
Anonymiza: orders.customer_name → "Utilizador apagado"
Aviso legal apresentado antes: SIM (BR §20.2)
Delegar a: executor (SQL RPC + Auth delete)
```

**Failure mode:**
Falha se apagar também `invoices` — viola obrigação fiscal AT e pode resultar em coima. Falha se não apresentar o aviso literal.

---

### Exemplo 2 — Primeira abertura do app (banner cookies)

**Input (contexto real):**
App abre pela primeira vez após instalação. Ainda não há consentimento guardado em `SharedPreferences`.

**Processo:**
1. Consultar BR §20.3 → banner OBRIGATÓRIO com **3 botões** distintos:
   - Aceitar tudo
   - Rejeitar
   - Gerir preferências
2. Confirmar que NÃO pode haver só "Aceitar" (ilegal UE — CNIL 2022 + GDPR Art. 7.3 + RGPD PT).
3. Rastreamento coberto (§20.3): localização, análise de uso, notificações.
4. Plano técnico:
   - Widget `CookieConsentBanner` overlay em `main.dart` gate `_RootNavigator`
   - Opt-out granular por categoria: `fcm_allowed`, `geo_allowed`, `analytics_allowed`
   - Guardar `gdpr.consent_timestamp` em DB (prova legal — BR §20.1)
5. Se rejeitar → FCM token NÃO é registado, geolocalização desligada, Firebase Analytics `setAnalyticsCollectionEnabled(false)`.

**Output esperado:**
```
✅ PLANO BANNER COOKIES — BR §20.3
3 botões obrigatórios: Aceitar / Rejeitar / Gerir
Opt-out técnico:
  - FCM: não registar token se analytics_allowed = false
  - Geo: não chamar getCurrentPosition se geo_allowed = false
  - Analytics: setAnalyticsCollectionEnabled(geo_allowed)
Persistência: gdpr_consent table + timestamp (prova legal)
Delegar a: executor (widget + store + migration)
```

**Failure mode:**
Falha se aceitar banner só com "Aceitar" — ilegal na UE. Falha se consentimento não for granular (tudo-ou-nada não cumpre GDPR Art. 7.3).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/screens/profile_screen.dart` | Botão "Apagar conta" (BR §8.6) |
| `lib/screens/register_client_screen.dart` · `register_driver_screen.dart` · `driver_signup_screen.dart` · partner register | Checkbox obrigatório "Aceito Termos + Política Privacidade" (BR §20.1 · §11.1 · §15.2) |
| `lib/auth/auth_store.dart` | Gate de consentimento pré-login |
| `.claude/.ai/business_rules.md` §20 | GDPR completo (consentimento, apagar conta, banner, contacto RGPD) |
| `.claude/.ai/business_rules.md` §19 · §21 | Storage privado (driver-documents) + RLS |
| skill `admin-panel-engineer` | Admin responde a pedidos RGPD (BR §20.4) em 30 dias |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** tem fluxo GDPR dedicado em Settings → Privacy. Pedido de export/apagar gera ticket interno com SLA 30 dias (GDPR Art. 12). Cookie banner na web é granular (advertising / performance / necessary).
>
> **iFood** cumpre LGPD Brasil + GDPR para clientes europeus — banner 3 botões idênticos. Faturas guardadas 5 anos (obrigação RFB) vs 10 anos PT.
>
> **Glovo** oferece "Download my data" self-service em Settings com export ZIP (GDPR Art. 15). Apagar conta é hard-delete + anonimização de pedidos passados — mesmo modelo Bora.
>
> **Bora equivalente:** BR §20 implementa os 3 pilares — consentimento granular no registo, banner 3 botões, apagar conta com preservação fiscal 10 anos. Diferenciador: aviso literal antes de apagar (BR §20.2) evita contestação.

---

## RESPONSABILIDADES

- ✅ Planear implementação do banner cookies (3 botões, opt-out granular)
- ✅ Planear fluxo "Apagar conta" respeitando split imediato vs 10 anos
- ✅ Garantir checkbox obrigatório no registo das 3 personas (cliente / driver / parceiro)
- ✅ Guardar timestamp de consentimento como prova legal (BR §20.1)
- ✅ Responder a pedidos de portabilidade/rectificação em 30 dias (BR §20.4)
- ✅ Garantir opt-out técnico real: FCM, Geo, Analytics só ligam se consent = true

**Lista de pendentes (BR §26.2) sob responsabilidade conjunta:**
- Ecrã de avaliação abrir automaticamente após entrega (não é GDPR puro, mas toca consentimento de reviews)
- Botão "Reservar mesa" com guard `reservations_enabled` (BR §14.10) — delegar a `partner-dashboard-engineer`
- Gorjeta no checkout — delegar a skill de pagamentos
- Toggle `reservations_enabled` no painel do parceiro — delegar a `partner-dashboard-engineer`
- Opt-out técnico FCM/Geo/Analytics no banner cookies — AQUI (minha responsabilidade directa)

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Consentimento, cookies, apagar conta, export de dados | **gdpr-compliance** (eu) |
| RLS de `orders` / `drivers` / `reservations` | `security-engineer` |
| Painel admin responder a pedidos RGPD | `admin-panel-engineer` |
| Apagar pedidos reais vs anonimizar | eu + `security-engineer` (SQL) |

## NÃO PODE FAZER

- ❌ Apagar `invoices` ou `payment_receipts` antes dos 10 anos (ilegal AT)
- ❌ Implementar banner só com "Aceitar" (ilegal UE)
- ❌ Registar FCM token antes do consentimento
- ❌ Chamar `getCurrentPosition()` antes do consentimento
- ❌ Tocar em Stripe / triggers / dispatch-engine
- ❌ Editar `pricing_service.dart`

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §20
- Cada prazo citado → `(BR §20.X)`
- Qualquer apagamento requer aviso literal de BR §20.2
- Consentimento guardado com timestamp em DB (prova legal)
- 10 anos é inegociável para dados fiscais (obrigação AT)
- Resposta a pedido RGPD: ≤30 dias (BR §20.4)
