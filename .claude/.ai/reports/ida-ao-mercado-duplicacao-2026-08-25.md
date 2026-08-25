# Ida ao mercado — lista gravada duas vezes, talão a repetir e progresso perdido

**Data:** 2026-08-25 · **Branch de trabalho:** `tvde/reserva-agendada-2026-08-20`
**Âmbito autorizado:** só Flutter (app do estafeta) + 1 ecrã do painel admin.
Sem migrations, sem Edge Functions, sem pricing, sem tokens, sem dispatch.

---

## 1. O que aconteceu de verdade (caso do Continente, 2026-08-25)

- O ecrã de finalizar a ida ao mercado **gravou a mesma lista de 6 linhas duas vezes**
  (18:03:12 e 18:03:38) e a `notify-purchase-finalized` correu duas vezes → a cliente
  viu tudo repetido na app dela.
- `upload-receipt` respondeu **200 nas duas chamadas** e, mesmo assim, a app voltou ao
  ecrã da câmara e obrigou o estafeta a **repetir a foto do talão 3 vezes**.
- O reconhecimento automático do talão **veio a zero** (não leu o total).
- O estafeta **saiu da app a meio** da ida ao mercado e **perdeu tudo o que já tinha
  marcado**, tendo de escolher os artigos outra vez.

## 2. Causa-raiz, encontrada no código (não deduzida)

| # | Causa | Onde |
|---|---|---|
| 1 | `finalizeStoreShoppingV2WithReceipt` **não tem** guarda de "já finalizado" (a v1 tem: `if (order.isPurchaseFinalized) return 'Compra já foi finalizada.'`). A RPC `finalize_storeshopping_purchase_v2` também não a tem — só levanta UNAUTHENTICATED / ORDER_NOT_FOUND / WRONG_SERVICE_TYPE / PARTNER_STORE_USE_V1 / NOT_ASSIGNED_DRIVER / INVALID_TOTAL / RECEIPT_URL_REQUIRED. Logo, **cada nova chamada volta a inserir tudo e volta a notificar**. | `lib/stores/order_store.dart:1923` (🔴 ficheiro bloqueado pela Trava — a guarda foi posta em quem chama) |
| 2 | O botão "Confirmar compra" era `onPressed: allDecided ? () async {…}` — **sem qualquer trava**: dois toques = dois fluxos completos. | `lib/screens/driver_map_screen.dart` |
| 3 | `ReceiptUploadService` decidia sucesso pela **forma do corpo** (`data as Map`, `data['success'] != true`, `data['path'] as String`). Um 200 com corpo diferente do previsto, ou uma ligação que morre **depois** de o servidor gravar, caía no `catch` → dialog "Falha ao enviar talão" → o estafeta voltava à câmara. O servidor, esse, registou 200. | `lib/services/receipt_upload_service.dart` |
| 4 | A leitura automática do talão é **shadow** e assíncrona (`net.http_post` para `ocr-receipt`, com `EXCEPTION WHEN OTHERS → RAISE NOTICE`): nunca deveria travar o estafeta. O que o travava era a foto ser **descartada** a cada falha a jusante, obrigando a nova captura. | `supabase/migrations/20260511110100_…v2.sql` (só lido) |
| 5 | O progresso da lista vivia **só na memória** do `_ShoppingListSheetContent`. Fechar a folha ou o SO matar o processo apagava tudo. | `lib/screens/driver_map_screen.dart` |

## 3. O que ficou feito

### App do estafeta (PT-PT)

1. **Botão à prova de duplo toque e de reenvio.**
   Caminho único `_onConfirmPressed → _finalizeShopping`, com `_submitting` a fechar a
   porta ao primeiro toque (o rótulo passa a "A concluir…"). Antes de gravar, o ecrã
   **lê o servidor**: se a lista **e** o talão já lá estão, não regrava nem notifica —
   só avança com "Esta compra já estava registada no servidor".
   Novo `lib/services/store_shopping_finalize_guard.dart` (read-only sobre
   `order_purchase_items_v2` + `order_receipts_v2`, com as políticas RLS que o estafeta
   já tem). Serve também **depois** de um erro: se os dados ficaram lá (erro a seguir à
   escrita, ou a barreira `trg_opi_v2_block_duplicate` a recusar a 2.ª escrita), avança
   em vez de mandar repetir tudo.

2. **200 = avança, sempre.**
   `ReceiptUploadService` foi reescrito: o `functions_client` só devolve `FunctionResponse`
   em 2xx (em ≥400 lança `FunctionException` — verificado no pacote instalado,
   `functions_client-2.5.0/lib/src/functions_client.dart:181-190`), portanto **qualquer 2xx
   é sucesso**. O `path` é derivado com tolerância (`data['path']`, corpo em String, ou o
   path determinístico `<orderId>.jpg` que a própria Edge Function usa com `upsert:true`).
   Erro de rede → **uma** repetição automática (inofensiva, é upsert); só depois é falha.
   Mensagens PT-PT por código para as respostas não-200.

3. **Talão ilegível não obriga a repetir a foto.**
   A foto fica retida em `_pendingReceipt`: qualquer falha a jusante (rede, RPC, leitura
   automática que não consegue ler o total) **reaproveita a foto** — nunca se volta à
   câmara. O valor que vale é o que o estafeta escreveu à mão. O dialog de erro passa a
   dizer isso: "A foto que tiraste ficou guardada: toca outra vez em Concluir compra e
   não precisas de a repetir." A revisão fica visível ao admin (ponto 4 abaixo).

4. **Rascunho local do progresso.**
   Novo `lib/services/store_shopping_draft_service.dart`: grava por pedido, em
   SharedPreferences, o estado de cada artigo (comprado / em falta / pendente), os artigos
   extra adicionados e o n.º de sacos. Grava a cada marcação (`_setItemStatus`,
   `_changeBagCount`, adicionar produto) e restaura ao reabrir a folha, com aviso
   "Retomámos a tua lista: N artigos já marcados". Expira em 12 h e é apagado quando a
   compra fecha. **Do rascunho só volta o estado do estafeta — artigos e preços vêm
   sempre do pedido**, nunca do rascunho.

### Painel admin (PT-BR)

Nova aba **"Ida ao mercado"** no detalhe do pedido
(`lib/screens/admin/admin_order_purchase_tab.dart`, ligada em
`admin_order_detail_screen.dart`, 4 → 5 abas):

- lista de `order_purchase_items_v2` com **estado por linha** (Comprado / Em falta /
  Substituído / Adicionado pelo entregador / Pendente), quantidade, preço, valores reais
  e a hora exacta em que a linha foi gravada (é isso que torna óbvia a gravação dupla);
- **linhas repetidas destacadas** (mesma chave nome+estado+qtd+preço) com aviso no topo e
  botão **"Apagar repetida"** (a primeira ocorrência fica);
- card do talão com o **estado do reconhecimento**: "não rodou ainda" / "total não lido"
  / "divergência sinalizada" / "conferido", valor digitado vs valor lido, diferença, loja
  lida, foto do talão (URL assinado) e notas do admin;
- botão **"Marcar como revisado"** — baixa `ocr_flagged` e deixa a nota
  "Revisado no painel em dd/mm/aaaa hh:mm" em `reimbursement_admin_notes`.
  **Nenhuma coluna de dinheiro é tocada** (`reimbursement_status` e valores só são lidos).

## 4. Provas

```
$ flutter analyze            (projeto inteiro)
224 issues found. (ran in 197.1s)
$ flutter analyze | grep -c "error -"
0
$ flutter analyze | grep -E "admin_order_purchase_tab|store_shopping_draft_service|store_shopping_finalize_guard|receipt_upload_service|driver_map_screen|admin_order_detail_screen"
   info - Use 'const' with the constructor to improve performance - lib\screens\admin\admin_order_detail_screen.dart:1001:17
warning - The name BRDriver is shown, but isn't used - lib\screens\driver_map_screen.dart:25:65
warning - A value for optional parameter 'bold' isn't ever given - lib\screens\driver_map_screen.dart:2085:10
```
Os três avisos acima são **pré-existentes** (import de `BRDriver`, parâmetro `bold` do
`_SummaryRow`, `BorderSide` do `_ActionButton`) — nenhum está em código escrito agora.
Os ficheiros novos não produzem uma única linha de análise.

```
$ python .claude/juiz/anti_trapaca.py --base HEAD
  JUIZ · CHÃO ANTI-TRAPAÇA (determinístico)  →  ✅ CLEAN
  ficheiros alterados: 25 (teste: 0, código: 7)   Δ casos de teste: +0
  VEREDITO: chão limpo.
```

## 5. Ficheiros tocados

| Ficheiro | O quê |
|---|---|
| `lib/services/receipt_upload_service.dart` | reescrito — 2xx é sempre sucesso, retry de rede, mensagens PT-PT |
| `lib/services/store_shopping_finalize_guard.dart` | **novo** — leitura de idempotência (read-only) |
| `lib/services/store_shopping_draft_service.dart` | **novo** — rascunho local do progresso |
| `lib/screens/driver_map_screen.dart` | botão de concluir reescrito, foto retida, rascunho, dialog de erro |
| `lib/screens/admin/admin_order_purchase_tab.dart` | **novo** — aba admin PT-BR |
| `lib/screens/admin/admin_order_detail_screen.dart` | +1 aba (4 → 5) |

## 6. O que NÃO foi feito, e porquê

- **Nada no banco, nada em Edge Functions** — proibido nesta tarefa. A barreira
  `trg_opi_v2_block_duplicate` (aplicada hoje por MCP) fica a proteger o servidor; o app
  agora lida com ela sem prender o estafeta.
- **`order_store.dart` não foi tocado** — é zona protegida pela Trava (contém
  `finalizePurchase*`). A guarda de idempotência foi posta em quem chama, o que resolve o
  caso real sem furar a Trava.
- **Falta 1 política de RLS para o botão "Apagar repetida" funcionar de facto.**
  `order_purchase_items_v2` só tem, para admin, `admin_select_all_items` (SELECT).
  Sem política de DELETE, o PostgREST responde 200 e apaga 0 linhas. O ecrã **deteta isso**
  (`.delete().select()` devolve lista vazia) e diz-lo ao admin, sem fingir sucesso.
  Proposta (alteração de banco — **não aplicada**, precisa do "vai"):

  ```sql
  CREATE POLICY "admin_delete_items" ON public.order_purchase_items_v2
    FOR DELETE USING (public.is_admin());
  ```

## 7. Publicação

`git push origin autonomous-night-2026-04-29` **não foi executado**: um push nessa branch
dispara o CI que publica em produção (Play `internal,alpha,production` + web). É Lista
Vermelha por ser build/publicação de produção. O trabalho está commitado localmente e
pronto a empurrar com um "vai".
