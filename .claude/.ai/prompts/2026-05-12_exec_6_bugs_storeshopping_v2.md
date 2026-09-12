# PROMPT ELITE — Sessão Execução 6 Bugs StoreShopping V2

**Para colar na próxima sessão Claude Code.**
**Modo:** Protecção total + CEO-AI orchestrator.
**Tempo estimado:** ~3h30min sequencial (ou ~2h30min com BUG E em paralelo).

---

```text
⚠️ MODO PROTECÇÃO TOTAL ⚠️
⚠️ USAR OPUS 4.7 — sessão crítica (storeShopping V2 financeiro + push) ⚠️

Invoca o CEO-AI orchestrator em .claude/skills/ceo-ai/ para esta tarefa.

═══════════════════════════════════════
CONTEXTO — APROVAÇÃO SESSÃO ANTERIOR
═══════════════════════════════════════

Sessão análise READ-ONLY 2026-05-11 produziu plano detalhado para 10 bugs
descobertos em teste real 2-devices Continente Guarda CASH €13.66.

Danilo aprovou:
1. BUG B → aceitar como falso bug (NÃO mexer RLS — caminho actual funciona)
2. BUG G → FALSO POSITIVO confirmado (distance_km=4.445 é real entre loja
   Rua do Ferrinho e Via de Cintura Externa; €5.79 driver_earnings está
   matematicamente correcto)
3. BUG D → auto-resolve após BUG A
4. V1 deprecated não-parceiro → documentar em business_rules §52.3
5. 3 skills novas aprovadas para criação (já criadas — ver
   .claude/skills/storeshopping-v2-debugger/ etc)

Ler ANTES de começar:
- .claude/.ai/reports/2026-05-11_storeshopping_v2_real_test_analysis.md
  (plano completo, secção por bug, ficheiros, riscos)
- .obsidian-vault/sessoes/2026-05-11_storeshopping_v2_real_test_analysis.md
  (mirror)

Branch: autonomous-night-2026-04-29
HEAD esperado: 64748d9 (após sessão 17-bugs)

═══════════════════════════════════════
A0 — PRE-FLIGHT
═══════════════════════════════════════

cd bora_app
git status -s
git branch --show-current
git log --oneline -6

Esperado:
- Branch: autonomous-night-2026-04-29
- HEAD: 64748d9 ou superior
- Sujos pre-existentes habituais OK

═══════════════════════════════════════
ÁREAS PROIBIDAS (NÃO TOCAR)
═══════════════════════════════════════

Mesmas das sessões anteriores. Resumo:
- pricing_service.dart e pricing_*.dart (LEITURA apenas para BUG F)
- finalize_storeshopping_purchase v1 (deprecated, NÃO modificar)
- Stripe webhooks / MBWay webhooks
- dispatch-engine Edge Function
- 17 triggers existentes em orders (trigger #18 já adicionado anteriormente)
- enforce_financial_immutability
- wallet_apply_post_delivery_adjustment / wallet_credit_refund_split
- supabase/.temp/

Skip um bug se exige tocar área proibida. NÃO bloqueia outros bugs.

═══════════════════════════════════════
ORDEM DE EXECUÇÃO APROVADA
═══════════════════════════════════════

Sequencial (ou BUG E em paralelo):

1. BUG A — Migration receipts bucket sync (~10min, BAIXO)
2. BUG C — UX upload error AlertDialog (~30min, BAIXO)
3. BUG I — UX disable button sem foto (~20min, BAIXO)
4. BUG D — VALIDATE RPC v2 chamado (~10min teste, NULL)
5. BUG E — Push tokens defensive + retry + logs release (~1h, MÉDIO)
   ⚠️ PODE CORRER EM PARALELO a 1-4 (independente)
6. BUG F — Server-side quote pre-checkout (~1h, MÉDIO)
7. BUG H — Tela CASH breakdown completo (~30min, BAIXO)
8. BUG G — Reportar falso positivo (5min doc)
9. BUG J — Doc V1 deprecated não-parceiro (5min doc)

═══════════════════════════════════════
BLOCO A — INFRA + UX (BUGS A, C, I, D)
═══════════════════════════════════════

▓▓▓ BUG A — Migration receipts bucket sync ▓▓▓

Path: supabase/migrations/20260511220000_create_receipts_bucket.sql

Conteúdo (idempotente, comentários PT-PT, UTF-8 sem BOM):

INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) VALUES (
  'receipts',
  'receipts',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

NÃO duplicar RLS policies (já existem em prod desde sessão close-todos).

Aplicar via MCP apply_migration (vai no-op em prod porque já existe via
INSERT manual MCP).

VALIDATION:
SELECT * FROM storage.buckets WHERE id='receipts';
→ Esperado: 1 row, file_size_limit=10485760

COMMIT: "feat(storage): receipts bucket migration sync repo (BUG A)"

▓▓▓ BUG C — UX upload error AlertDialog ▓▓▓

Ficheiro: lib/screens/driver_map_screen.dart
Localização: try/catch upload (linha ~2812-2816)

Antes:
} catch (e) {
  messenger.showSnackBar(SnackBar(
      content: Text('Erro upload talão: $e')));
  return;
}

Depois:
} catch (e) {
  debugPrint('[driver_map] receipt upload error: $e');
  if (!mounted) return;
  await _showUploadErrorDialog(context, e);
  return;
}

Criar método _showUploadErrorDialog no mesmo ficheiro (ou static helper
function ao fundo, similar a _captureReceiptForV2):

Future<void> _showUploadErrorDialog(BuildContext context, Object error) async {
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
      title: const Text('Falha ao enviar talão'),
      content: const Text(
        'Não foi possível guardar a foto do talão. Verifica a tua '
        'ligação à internet e tenta de novo.\n\n'
        'Se o problema persistir, contacta o admin.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

PT-PT. Bora design (#1B5E20 + #E65100) — herda do AppTheme.

COMMIT: "fix(ux-driver): AlertDialog claro em upload talão falha (BUG C)"

▓▓▓ BUG I — UX disable button sem foto ▓▓▓

Ficheiro: lib/screens/driver_map_screen.dart
Localização: _ReceiptCaptureSheet._ReceiptCaptureSheetState build method,
o ElevatedButton.icon "Confirmar" no fim.

Antes: onPressed: _submitting ? null : _onSubmit
Depois:
final canSubmit = !_submitting && _photo != null && _totalCtrl.text.trim().isNotEmpty;
ElevatedButton.icon(
  onPressed: canSubmit ? _onSubmit : null,
  ...
)

E adicionar:
@override
void initState() {
  super.initState();
  _totalCtrl.addListener(() => setState(() {})); // rebuild para canSubmit
}

E texto helper visível quando disabled:
if (!canSubmit && !_submitting)
  Padding(
    padding: EdgeInsets.only(top: 8),
    child: Text(
      _photo == null
        ? 'Tira foto do talão para continuar'
        : 'Digita o valor pago',
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
    ),
  ),

COMMIT: "fix(ux-driver): disable Confirmar até foto+valor (BUG I)"

▓▓▓ BUG D — VALIDATE RPC v2 chamado ▓▓▓

NÃO É CÓDIGO. É TESTE.

Após BUG A migration aplicada:
1. Criar novo pedido teste storeShopping não-parceiro CASH (qualquer mercado)
2. Estafeta aceita, picked up, finaliza compra
3. Modal foto+valor → confirmar
4. Query DB:
   SELECT id, purchase_flow_version, is_purchase_finalized, status,
          final_purchase_value, cash_total_due
   FROM orders WHERE id='<novo_id>';

   Esperado: purchase_flow_version=2, is_purchase_finalized=true,
   status='onTheWay', final_purchase_value>0, cash_total_due>0

5. SELECT count(*) FROM order_purchase_items_v2 WHERE order_id='<novo_id>';
   Esperado: count = items pedido

6. SELECT * FROM order_receipts_v2 WHERE order_id='<novo_id>';
   Esperado: 1 row, photo_url existe, driver_typed_total_cents > 0,
   reimbursement_status='cash_settled' (CASH)

7. Tentar download via SDK ou MCP:
   SELECT storage.foldername(name) FROM storage.objects
   WHERE bucket_id='receipts' AND name LIKE '%<novo_id>%';
   Esperado: 1 row

Reportar resultados no relatório final. Se falhar, voltar para BUG A.

═══════════════════════════════════════
BLOCO B — PUSH TOKENS (BUG E)
═══════════════════════════════════════

▓▓▓ BUG E — Push tokens defensive + retry + logs release ▓▓▓

Hipóteses (validar com logs):
1. saveTokenForDriver NÃO é chamado para teste9 (login flow)
2. _fcmToken null no momento da chamada
3. auth.currentUser null durante race condition
4. consent_granted = false
5. RPC falha silenciosamente

Fix em 3 camadas:

1. lib/services/push_token_service.dart:
   - Adicionar retry: 3 tentativas com backoff (1s, 3s, 9s) quando
     getToken() retorna null
   - Substituir debugPrint por print() em release (visibilidade ADB
     logcat / Xcode console) ou usar logger.dart se disponível
   - Adicionar log explícito de cada decisão skip:
     [PushTokenService] skip — auth.currentUser null
     [PushTokenService] skip — getToken returned null after 3 retries

2. lib/screens/_root_navigator.dart (OU lib/main.dart auth gate):
   - Detectar mudança de auth.currentUser ≠ null + role known
   - Chamar PushTokenService.registerForRole(role) post-frame
   - Idempotente (já é via _lastRegisteredToken cache)

3. lib/screens/driver_home_screen.dart:
   - Em initState(), Future.microtask para garantir Provider settled:
     Future.microtask(() {
       if (!mounted) return;
       PushTokenService.registerForRole('driver');
     });

VALIDATION:
- Aplicar fix + buildar release APK
- Estafeta teste9 login → check logcat para mensagens [PushTokenService]
- Query DB:
  SELECT count(*) FROM driver_push_tokens
  WHERE user_id='519d0782-88f9-4a5f-8249-8bdae11de7a8'::uuid
    AND active=true;
  Esperado: ≥ 1

COMMIT: "fix(push): driver tokens defensive register + retry + release logs (BUG E)"

═══════════════════════════════════════
BLOCO C — PRICING UX + TELA CASH (BUGS F, H)
═══════════════════════════════════════

▓▓▓ BUG F — Server-side quote pre-checkout ▓▓▓

Ficheiros:
- lib/stores/cart_store.dart (linha ~158)
- lib/screens/cart_screen.dart (linha ~437)

⚠️ NÃO TOCAR pricing_service.dart — área proibida. Apenas ler.

Mudança:
1. CartStore: novo método async quoteOrderPricing() que chama
   Supabase RPC quote_order_pricing com payload completo do cart
2. Cart screen checkout: antes de cartStore.finishOrder, chamar
   quoteOrderPricing → obter totals server-authoritative → exibir
   total real ao cliente + esperar confirm
3. Throttle: cache resultado 30s (evita spam quota)

NÃO eliminar PricingService.calculateBreakdown — continua a servir
para previews durante navegação (não bloquear UI). Apenas substituir
no momento do CHECKOUT FINAL.

VALIDATION:
- Criar pedido entrega distância > 4km
- Cliente vê total = server total (não diff de €0.22+)

COMMIT: "fix(cart): server-authoritative total pre-checkout via quote_order_pricing (BUG F)"

▓▓▓ BUG H — Tela CASH breakdown completo ▓▓▓

Ficheiro: lib/screens/driver_map_screen.dart linhas ~2680-2700

Antes (current):
if (isCash) {
  Row('Cliente paga na entrega:', '€${adjustedTotal.toStringAsFixed(2)}')
}
// adjustedTotal = boughtTotal + bagFee + addedFinalTotal (omite taxas)

Depois:
if (isCash) {
  final cashTotal = adjustedTotal + order.serviceFee + order.deliveryFee;

  Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SummaryRow(label: 'Produtos comprados', value: boughtTotal),
      _SummaryRow(label: 'Sacos', value: _bagFee),
      if (addedFinalTotal > 0)
        _SummaryRow(label: 'Adicionados', value: addedFinalTotal,
                    color: Colors.blue),
      _SummaryRow(label: 'Taxa de serviço', value: order.serviceFee),
      _SummaryRow(label: 'Entrega', value: order.deliveryFee),
      const Divider(),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Cliente paga na entrega:',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text('€${cashTotal.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17,
                  color: Colors.green.shade700)),
        ],
      ),
    ],
  )
}

Branch MBWay/Stripe (else) inalterado — já mostra "Bora reembolsa-te €X".

VALIDATION:
- Pedido teste CASH €13.66:
  Tela mostra: Produtos €8.44 + Sacos €0.10 + Adicionados €0 +
              Taxa €2.50 + Entrega €2.72 = €13.76 (com sacos)
  Sem sacos: €13.66

COMMIT: "fix(ui-driver): tela CASH breakdown completo com taxa+entrega (BUG H)"

═══════════════════════════════════════
BLOCO D — DOCUMENTAÇÃO (BUGS G, J)
═══════════════════════════════════════

▓▓▓ BUG G — Reportar falso positivo ▓▓▓

NÃO É CÓDIGO. É DOC.

Adicionar entrada em .claude/.ai/business_rules.md §52.3 secção
"Driver earnings — fórmula":

> Validação prática (pedido teste 2026-05-11):
> distance=4.445km, subtotal=€8.44, fee=€2.50+€2.72
> → driver_earnings=€5.79 (correcto pela fórmula).
> Para validar futuros casos suspeitos, usar skill
> driver-earnings-validator.

▓▓▓ BUG J — V1 deprecated não-parceiro ▓▓▓

Adicionar nota em business_rules §52.3:

> ⚠️ V1 finalize_storeshopping_purchase é **DEPRECATED** para
> storeShopping NÃO-PARCEIRO desde 2026-05-11 (trigger #18 força V2
> em novos pedidos). Mantém-se em código apenas para retro-compat com
> pedidos v1 antigos + storeShopping PARCEIRO + restaurant.
> Bug histórico de cálculo €1.70 não será corrigido — V1 não recebe
> novos pedidos não-parceiro.

COMMIT: "docs(rules): §52.3 V1 deprecated não-parceiro + BUG G falso positivo (BUG G+J)"

═══════════════════════════════════════
RELATÓRIO FINAL
═══════════════════════════════════════

Path: .claude/.ai/reports/2026-05-12_exec_6_bugs_storeshopping_v2.md
Sync: .obsidian-vault/sessoes/

Estrutura:
1. Resumo executivo (5 linhas) — quantos fixed, validation status, riscos
2. Por bug (A, C, I, D, E, F, H, G, J): estado, commit SHA, validation
3. Bugs novos descobertos (anti-perda info)
4. Áreas proibidas tentadas (transparência)
5. Próximos passos sugeridos
6. Skills criadas/actualizadas

Push branch no fim:
git push origin autonomous-night-2026-04-29

═══════════════════════════════════════
DEFESAS FINAIS
═══════════════════════════════════════

1. flutter analyze: 0 erros novos (warnings info-level OK)
2. Migration falha → REVERTER e seguir próximo bug
3. Tempo > 4h → commit+push estável + relatório do que faltou
4. Área proibida → SKIP + documentar
5. Pedido teste validation Falha → BUG D fica blocked → reportar

NÃO PARAR PARA PERGUNTAR. Aplicar fixes em sequência.

/ctx doctor
/ctx stats
```

---

## Cheatsheet validação ponta-a-ponta

Após todos os fixes, criar um pedido teste CASH non-partner:
1. Cliente faz checkout → vê total server-authoritative
2. Estafeta aceita → picked up
3. Finaliza compra → vê tela CASH com breakdown completo (BUG H)
4. Modal foto+valor → não consegue clicar Confirmar sem ambos (BUG I)
5. Tira foto, digita valor, confirma → upload + RPC v2 ok
6. DB: orders.purchase_flow_version=2, items_v2/receipts_v2 populated
7. driver_push_tokens active=true para o estafeta (BUG E)
8. Push notification chega ao cliente "Compra finalizada"
9. Cliente entrega: estafeta recebe TOTAL completo cash

## Cheatsheet skills

- `/storeshopping-v2-debugger <order_id>` — relatório de um pedido v2
- `/storage-bucket-validator receipts` — audit bucket
- `/driver-earnings-validator <order_id>` — validar fórmula
