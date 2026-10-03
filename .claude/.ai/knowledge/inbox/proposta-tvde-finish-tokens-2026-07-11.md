# 🔴 PROPOSTA (propose-only) — TVDE `finish_ride` erra: colunas `tokens_applied_*` em falta

> **Lista Vermelha (tokens/dinheiro + migration).** NÃO aplicado por executor headless.
> Diagnóstico completo abaixo; a aplicação da migration espera "vai" do Danilo.

## Sintoma reportado
"A corrida (motorista) não termina nem do lado do cliente nem do motorista, aparece erro"
— sobretudo com parada extra. (E2E `tvde-corrida-cliente-motorista`.)

## Causa raiz (verificada em prod, read-only)
`tvde_rides` **não tem nenhuma coluna `tokens%`** (query a `information_schema.columns` → vazio).
Existem **3 overloads** de `tvde_finish_ride`:

| Assinatura | deflen | refs `tokens_applied` |
|---|---|---|
| `tvde_finish_ride(uuid, numeric)` | 281 | não (stub) |
| `tvde_finish_ride(uuid, numeric, text)` | 331 | não (stub) |
| `tvde_finish_ride(uuid, numeric, text, integer)` | 5343 | **sim** (lógica real) |

O app (`lib/stores/tvde_driver_store.dart:331`) chama `tvde_finish_ride` com 3 params nomeados
(`p_ride_id`, `p_final_distance_km`, `p_distance_source`). A lógica real de settlement (4-arg)
referencia `tokens_applied_*` — colunas que **não existem** → a função real erra / o app cai no
stub que não faz o settlement. Alinha com a memória `project_tvde_tokens_half_deployed`:
> "RPCs threading aplicados em prod mas colunas `tvde_rides.tokens_applied_*` NÃO … TVDE quebrado
> até aplicar `20260709010000_tvde_tokens_applied_columns.sql`."

## Correção proposta (NÃO aplicada)
1. Aplicar a migration **`supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`**
   (adiciona `tvde_rides.tokens_applied_*`). Verificar antes que o ficheiro só faz `ADD COLUMN`
   (aditivo, não-destrutivo) e não recalcula valores já cobrados.
2. Confirmar a resolução de overload: garantir que o app atinge a versão 4-arg (settlement real)
   e não os stubs 2/3-arg — ou remover os stubs órfãos após aplicar as colunas.
3. Re-correr o E2E de finish (2 devices) e validar o trio `ledger_entries` (earning/platform/commission)
   + `driver_earnings` correto.

## Porque é 🔴 e fica à espera
Toca `bora_tokens`/settlement/`driver_earnings` + migration. Regra do Bora: dinheiro real =
propose-only. **⚠️ ISTO MEXE EM PAGAMENTO/TOKENS. Está diagnosticado e pronto — confirma que eu aplico.**

Esquadrão sugerido: `pagamentos-wallet`[propõe] + `backend-supabase` + `dados-sql` → Juiz.
