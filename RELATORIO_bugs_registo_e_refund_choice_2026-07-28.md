# Relatório — Bug A (`_formKey`) e Bug B (`_tokenValueCentsX100`) — 2026-07-28

Branch `autonomous-night-2026-04-29`. `flutter analyze` nos dois ficheiros → **0 erros**.

Confirmados os 2 fixes já aplicados por MCP directamente na Supabase (não mexidos):
- `notify-client` v18 — pass-through do `type` do body.
- `partner_cancel_appointment` — chama `refund` automaticamente quando o depósito estava `paid`.

---

## Bug A — `lib/screens/register_partner_screen.dart:33`

**Confirmado por leitura:** `_formKey` era criada mas nunca associada a nenhum `Form`, e nenhum
`TextFormField` do ecrã tinha `validator:`. A validação real sempre foi feita à mão em
`_validateStep1()` / `_validateStep3()` (checagem de campo por campo + `SnackBar`) — isso
continua a funcionar exactamente como antes, não toquei nessa lógica.

**Fix cirúrgico (2 pontos):**
1. `Stepper` passou a estar dentro de `Form(key: _formKey, child: Stepper(...))`.
2. `_submit()` ganhou `if (!(_formKey.currentState?.validate() ?? true)) return;` no topo.

Como nenhum campo tem `validator:`, `validate()` devolve sempre `true` — **comportamento
idêntico ao de antes**, zero regressão. O que muda é só que `_formKey` deixa de ser código
morto (o `unused_field` desapareceu do `flutter analyze`).

## Bug B — `lib/widgets/refund_choice_dialog.dart:65`

**Confirmado por leitura, incluindo o cálculo que usa o campo:** `_tokenValueCentsX100` era lido
de `platform_settings.token_value_cents_x100` em `_loadSettings()`, mas `_previewSplit()` **já
ignorava esse valor** e usava uma constante fixa (`tokensCents * 20`). Ou seja: **nenhum cálculo
dependia dele em silêncio** — o campo era buscado e nunca lido. Segui a instrução (remover
quando nada depende dele) e não a fórmula hardcoded, que fica fora de scope.

**Fix cirúrgico:**
1. Removido o campo `int _tokenValueCentsX100`.
2. Removida a chamada RPC `get_setting('token_value_cents_x100')` em `_loadSettings()` que só o
   alimentava — sem o campo, era uma chamada de rede sem propósito.
3. **Nenhum import ficou órfão** — `supabase_flutter` continua a servir o RPC de
   `wallet_split_free_pct`; `wallet_service` continua a servir `WalletService.instance`.

### Achado a reportar, não corrigido (fica fora do scope pedido)

`_previewSplit()` mostra ao cliente uma **estimativa de tokens hardcoded** (`* 20`, ou seja,
assume 1 token = €0,05), mesmo que `platform_settings.token_value_cents_x100` (default 50 →
1 token = €0,005) diga outra coisa. Os dois valores nem batem certo entre si — o comentário no
código diz "1 token = €0,005" mas a fórmula usada corresponde a €0,05.

Isto é só o **texto de preview** no diálogo — o cálculo real do refund corre server-side em
`WalletService.instance.cancelWithChoice` → RPC, que não vi (fora deste ficheiro). Mas se o
Danilo alguma vez mudar `token_value_cents_x100` em produção, este diálogo passa a mostrar ao
cliente um número de tokens errado antes de ele confirmar. Como toca `bora_tokens`/wallet
(zona 🔴), não mexi na fórmula — fica registado para uma tarefa própria do `pagamentos-wallet`.

---

## Fecho

- `flutter analyze` nos dois ficheiros: **0 erros**. Os 4 warnings de imports não usados que
  aparecem em `register_partner_screen.dart` (`partner_product_store.dart`,
  `restaurant_store.dart`, `bora_primary_button.dart`, `partner_login_screen.dart`) são
  **pré-existentes** — já constavam do `flutter analyze lib` completo antes desta tarefa — e
  ficam fora do escopo de "Bug A" (que era só sobre `_formKey`). Não lhes toquei.
- Commit + push confirmados abaixo.
