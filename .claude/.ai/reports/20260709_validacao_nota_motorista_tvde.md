# Validação — Nota do cliente para o MOTORISTA (TVDE)

> Ordem: `ordem-20260709090419-28c0` · Data validação: 2026-07-09 · Modo: loop autónomo (executor)
> Resultado: ✅ APROVADO — código já correto, sem reescrita (mudança cirúrgica confirmada).

## Escopo
Paridade com a "Nota para o estafeta" do delivery/limpeza: o cliente TVDE deixa um
texto livre para o motorista. **Não-financeiro** — não toca tarifa, split nem
`payment_method`.

## Cadeia validada (Model → Store → Screen → DB)
| Camada | Ficheiro | Estado |
|---|---|---|
| DB coluna | `tvde_rides.customer_note TEXT` (nullable, aditiva) | ✅ aplicada em prod |
| DB RPC | `tvde_set_ride_note(uuid,text)` SECURITY DEFINER | ✅ aplicada em prod |
| Migration | `supabase/migrations/20260709000000_tvde_customer_note.sql` | ✅ |
| Widget | `lib/widgets/customer_note_field.dart` (partilhado, maxLength 200) | ✅ |
| Store | `lib/stores/tvde_store.dart::setRideNote` → RPC, falha silenciosa | ✅ (linhas 258-268) |
| Screen | `lib/screens/client/tvde/tvde_request_ride_screen.dart` | ✅ |

## Guardrails confirmados
- **Segurança RPC:** valida `auth.uid()`, dono da corrida (`not_ride_owner`), e recusa
  corridas terminais (`ride_terminal`). `LEFT(TRIM(...),200)` + `NULLIF` server-side.
- **Não-bloqueante:** grava só se `ride != null && trimmed.isNotEmpty` (screen linha 353);
  erro apanhado no store — a nota nunca falha o pedido.
- **Isolamento financeiro:** RPC dedicada fora do cálculo de tarifa (`tvde_request_ride`)
  e da Edge Function de pagamento. Zona 🟢 — não é Lista Vermelha.

## Verificações mecânicas (output real)
- `flutter analyze` (3 ficheiros tocados): **0 erros**, 3 `info` pré-existentes
  (build_context 233/235 + `activeColor` deprecated 952) — nenhum na feature da nota.
- DB check: `has_column=1`, `has_rpc=1`.

## Conclusão
Feature completa, coerente e segura. Nada a alterar.
