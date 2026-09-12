# Loop 2026-07-09 — Autocomplete "Continente cidade errada" (FIX) + TVDE tokens (BLOQUEADO 🔴)

## Bug #1 — Autocomplete quebrado no telemóvel real (CORRIGIDO ✅ zona segura)

**Causa raiz (o teste web não apanhou):** o viés `location+radius` do Google Places é
FRACO. Para "Continente" a API devolve 5 Continentes de cidades maiores e o da Guarda
**nem entra** no conjunto → o `_rankGuardaFirst` não tinha o que reordenar. E o antigo
fallback `"$query Guarda"` só disparava quando o resultado vinha **vazio** — para
"Continente" vinha cheio (outras cidades), logo nunca disparava.

**Correção:** sempre que NENHUM resultado da Guarda surge (`!any(_isGuarda)`), dispara-se
proativamente uma pesquisa explícita `"<query> Guarda"` e coloca-se à frente com dedupe
por `place_id` (`_mergeDedupe`). Cobre os dois casos do Danilo:
- "Continente" → surge o **Continente da Guarda** em 1.º.
- "Lavie" → dispara "Lavie Guarda" → devolve o **LaVie Shopping** (antes vinha vazio).
Fallback nacional sem viés mantido como última rede.

**Ficheiros:** `lib/services/place_autocomplete_service_io.dart` (Android/telemóvel real,
o que falhava), `lib/services/place_autocomplete_service_web.dart` (mirror). Helpers
`_isGuarda` + `_mergeDedupe` partilhados.

**Verificação:** `flutter analyze` nos 3 ficheiros → 0 erros, 0 issues novos (só 2 `info`
pré-existentes de deprecação `dart:html`/`dart:js`, linhas não tocadas). Testes de widget
existentes (`test/address_autocomplete_field_test.dart`) intactos.

**Prova visual em telemóvel real:** NÃO realizada — este loop é headless (sem display para
juiz_capture.py/adb screenshot). A correção é determinística e o mecanismo do bug está
identificado por análise. Recomenda-se ao Danilo repetir "Continente" e "Lavie" no device.

## Bug #2 — TVDE sem gastar Bora Tokens (BLOQUEADO — 🔴 LISTA VERMELHA)

Toca `bora_tokens` (gasto) E altera o valor cobrado ao cliente (desconto até 50%). É
dinheiro real → NÃO aplicado neste loop.

**Estado atual (verificado):**
- Fundação (colunas) já existe: `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`
  — aditiva/reversível, `tvde_rides.tokens_applied_count` + `tokens_applied_value_cents`.
  **NÃO aplicada** à BD.
- RPCs `tvde_request_ride`/`tvde_finish_ride` **não** referenciam `tokens_applied` (0 matches).
- Nenhum ecrã em `lib/screens/client/tvde` tem UI/toggle de tokens (0 matches).

**Pendente (só avança com "vai" do Danilo):** aplicar migration; threading do desconto
(mesma regra máx 50% = `platform_settings.token_payment_max_pct`) nas RPCs; débito real
de tokens; toggle "Usar Bora Tokens" no ecrã de pagamento TVDE espelhando o delivery.
NÃO mexer no ganho de tokens (já é zero para TVDE) — só o gasto.

## /ctx
- doctor: server PASS, FTS5 PASS, hook PASS, v1.0.89 (upgrade v1.0.169 disponível).
- stats: sessão 4 min, 1 tool call, sem savings ainda.
