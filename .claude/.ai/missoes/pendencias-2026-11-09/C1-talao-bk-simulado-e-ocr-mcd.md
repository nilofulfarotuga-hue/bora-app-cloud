# C1 — Robô do talão no BK (simulado) e talão do McDonald's por ler (09/11/2026)

## 1. catalog_price_update_from_receipt no talão BK a244493e (simulado em produção, nada gravado)

Simulação: bloco DO que chama a função e acaba em RAISE EXCEPTION (sem EXECUTE). Depois confirmei por SELECT:
0 linhas em catalog_price_updates para o talão, 0 avisos `catalogo_extra_mais_caro` do pedido, menu a 13,25.

Saída literal da função (versão no ar, md5 b6993ee2…, kill switch `catalog_price_live_update_enabled` = true):
`{"ok":true,"aplicadas":0,"pendentes":1,"sem_match":0,"ja_batiam":0,"segunda_volta":0,"extras_mais_caros":[2 linhas]}`

- Preços aplicados sozinho: **0**.
- Linhas pendentes: **1** — Triple Whopper Spicy Menu (bk-078771af-…) 13,25 → 11,87, "Tripwhopper + EXTRA BACON 2 FATIAS +
  Com Cebola + Batatas Media + Cola Media + 3C Whopper", confiança 0,588. O balcão é mais BARATO, por isso fica pendente
  (regra só subir) — deve ser **rejeitada**.
  Atenção: o 11,87 está torto. Os dois menus são iguais mas um tem Batatas Supreme (+0,50); a lista `v_items` é feita com
  `jsonb_agg` sem ordem e em produção os dois itens trocaram de lugar, por isso o +0,50 foi descontado ao grupo errado
  (em PGlite, com a ordem certa, dá 12,37). Ver erros fora do âmbito.
- Extras: 2 (um por menu) — "EXTRA BACON 2 FATIAS" 250 cêntimos ao balcão contra 91 na app → 1 aviso
  `catalogo_extra_mais_caro` em admin_notifications. Nenhuma linha de extra em catalog_price_updates (é o que o C3 muda:
  com a migração nova fica +1 linha pendente "EXTRA Bacon 0,91 → 2,50").
- Correr isto de verdade hoje não muda nenhum preço: só cria 1 pendente (a rejeitar) e 1 aviso.

## 2. Talão do McDonald's 3b47bc38 (pedido 7abb748d, 08/11) — como se corre o ocr-receipt (NÃO corrido)

Estado: o OCR correu às 20:47:54 de 08/11 mas o Gemini respondeu 503 → `ocr_raw_response = {"error":"gemini_503"}`,
`receipt_parsed` nulo. Nada volta a tentar sozinho (o único cron de talões é `settlement-receipts-retry`, de outra coisa).
O estafeta escreveu 28,80 €; o reembolso já está `admin_paid`.

Edge Function `ocr-receipt` no ar: versão 21, igual ao repo (v12, com a verificação do NIF), `verify_jwt = true`.

Como o próprio servidor a chama (`finalizar_talao_nao_parceiro`), com a chave de servidor do cofre:

```sql
select net.http_post(
  url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/ocr-receipt',
  headers := jsonb_build_object('Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                                'Content-Type', 'application/json'),
  body    := jsonb_build_object('order_id', '7abb748d-5a45-4256-82e3-fa7da62e7d15'));
```

Parâmetro único: `order_id` (não o id do talão; procura o talão por `order_receipts_v2.order_id`). Também aceita um admin
com sessão válida no `Authorization`.

Efeitos, por ordem:
1. Kill switch `receipt_ocr_enabled`; descarrega a foto do bucket `receipts`.
2. Gemini 3.1 flash-lite (se vier vazio, tenta o 3.1 flash). Se falhar outra vez: grava só `ocr_ran_at` e
   `ocr_raw_response = {"error":"gemini_…"}` e pára.
3. Grava em `order_receipts_v2`: `receipt_parsed` (+ `nif_check`), `receipt_parsed_total_cents`, `receipt_parsed_store`,
   `receipt_match` (|28,80 − lido| ≤ 1,00 €), `ocr_extracted_total_cents`, `ocr_diff_cents`, `ocr_flagged`
   (diferença > 0,50 €, foto que não parece talão, ou NIF errado), `ocr_raw_response`, `ocr_ran_at`.
4. NIF: compara o NIF do cliente impresso com o que o estafeta tinha de dar; se for outro, aviso `nif_talao_diferente`.
5. Gatilhos: `trg_enqueue_errand_catalog` só para Favores (este é restaurante → nada); os outros dois não disparam
   (não mudam essas colunas). O reembolso não é tocado.
6. Se houver linhas: chama `catalog_price_update_from_receipt` → **pode SUBIR preços do McDonald's sozinho**
   (até +50% quando o balcão é mais caro), cria linhas pendentes quando é mais barato e o aviso de extras.
   Por isso correr o OCR deste talão é mexer em preços: precisa do "autorizo".

Recomendação: aplicar primeiro o C3 (os extras passam a ficar pendentes) e depois correr o OCR. A sessão paralela
volta-deposito-kfc tem uma `ocr-receipt` v13 ainda por publicar (NIF da loja, linhas de depósito); se ela publicar
antes, o OCR corre já com a v13.
