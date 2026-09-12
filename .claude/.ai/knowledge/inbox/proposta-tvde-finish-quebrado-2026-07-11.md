---
id: proposta-tvde-finish-quebrado-2026-07-11
tipo: proposta
zona: vermelha
origem: [E2E loop noturno 2026-07-11]
estado: aguarda-aprovacao-danilo
confianca: alta
---

# 🔴 PROPOSTA — TVDE: corrida nunca finaliza ("erro dos dois lados")

> **NÃO APLICAR sem "vai" do Danilo.** Mexe em RPC de dinheiro TVDE + coluna de tokens
> em `tvde_rides` → Lista Vermelha. Preparado e verificado, falta só aprovação.

## Sintoma reportado (Danilo)
Ao adicionar uma **parada extra** numa corrida de motorista, a corrida **não termina
nem do lado do cliente nem do motorista** e **aparece um erro**.

## Causa raiz (CONFIRMADA na base de produção, read-only)
A RPC `public.tvde_finish_ride` (overload de 4 args, para onde o overload de 3 args
também delega) faz este UPDATE:

```sql
UPDATE public.tvde_rides SET ...
  tokens_applied_count       = CASE WHEN p_tokens_to_apply > 0 THEN p_tokens_to_apply
                                    ELSE tokens_applied_count END,
  tokens_applied_value_cents = CASE WHEN p_tokens_to_apply > 0 THEN v_tokens_discount_cents
                                    ELSE tokens_applied_value_cents END,
  ...
```

Mas a tabela `tvde_rides` **NÃO tem** as colunas `tokens_applied_count` nem
`tokens_applied_value_cents` (confirmado via `information_schema.columns`). Como o
ramo `ELSE` **lê a coluna mesmo quando `p_tokens_to_apply = 0`**, **qualquer**
chamada a `tvde_finish_ride` levanta `column "tokens_applied_count" does not exist`.

→ A transição para `finalizada` aborta, a corrida fica presa em `em_andamento`, e o
app mostra erro nos dois lados. **Isto vale para TODAS as corridas TVDE, não só com
parada extra** — a parada extra é só o cenário em que o Danilo tropeçou.

App chama isto em `lib/stores/tvde_driver_store.dart:331`
(`_sb.rpc('tvde_finish_ride', ...)`).

Bate certo com o Cérebro: `project_tvde_tokens_half_deployed` — "RPCs threading
aplicados em prod mas colunas `tvde_rides.tokens_applied_*` NÃO".

## Correção proposta (aditiva, reversível)
Aplicar a migration **que já existe no repo, ainda não aplicada a prod**:

`supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`

```sql
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS tokens_applied_count       INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tokens_applied_value_cents INTEGER NOT NULL DEFAULT 0;
```

- **Só colunas aditivas, DEFAULT 0.** Não altera nenhuma tarifa, comissão, ganho de
  motorista nem débito de tokens. Não mexe na matemática de `v_fare`/`v_driver_earn`/
  `v_bora_cut`. Rollback trivial (`DROP COLUMN`, incluído no ficheiro).
- Depois de aplicada, `tvde_finish_ride` deixa de rebentar → corrida finaliza dos dois
  lados. O gasto real de tokens no TVDE continua a NÃO acontecer (o app passa
  `p_tokens_to_apply` só quando o Danilo ligar essa feature; por agora é 0).

## Porque é 🔴 e precisa do Danilo
Toca em `tvde_rides` (tabela de dinheiro) + numa RPC que calcula ganho de motorista e
corte da plataforma. Por regra, migration em tabela financeira = aprovação humana.
Mesmo sendo aditiva, não aplico sozinho.

## Como aplicar (após "vai")
1. `supabase db push` da migration `20260709010000_...` (ou MCP `apply_migration`).
2. Verificar: `\d tvde_rides` mostra as 2 colunas.
3. Correr uma corrida TVDE de teste (2 telemóveis) até `finalizada` — confirmar que
   fecha nos dois lados e `driver_earn_cents`/`bora_cut_cents` ficam corretos.

## Nota sobre a lista de sugestões de morada (parada extra)
O corte/não-clicável do bottom sheet de sugestões **já foi corrigido em código** no
commit `ee695ff` ("fix(tvde): parada extra — lista de sugestões cortada/não-clicável
no bottom sheet"). Falta só **build + install do APK** no telemóvel para confirmar em
runtime (o device pode estar a correr APK pré-fix — mesmo padrão do
`autocomplete_guarda_stale_apk`). Verificação = manual/humano (2 telemóveis).
