# Missão compra-guardada-2026-11-14 (+ adenda 1: fila de pedidos)

Motor: Opus 5.5 · Porta: Claude Code no PC · Ramo: `ai/2026-11-14-compra-guardada` (a partir de
`autonomous-night-2026-04-29` em 0832c5a8) · e2e_log run `compra-guardada-2026-11-14`.

## O que aconteceu (lido no servidor)

- Pedido `b2b746d7` (Auchan, storeShopping, não-parceiro): `orders.items` com `purchaseStatus`
  `pending` nos 12 itens. A lista de compras só vivia em `_ShoppingListSheetContent._items` (memória
  da folha aberta por cima do mapa).
- Favor `09ee41da` (errand normal) aceite pelo estafeta `4f61dd31` às 16:32:03 (`driver_accept_offer`)
  com o Auchan ainda `driverAccepted`. O foco do mapa (RouteOptimizer) passou ao Favor e o botão
  "Ver compras" está preso ao `focusOrder` — o estafeta perdeu o caminho de volta à lista.
- O Auchan foi refeito e fechado às 16:34:48 e entregue às 16:42:37. O Favor `09ee41da` continua
  `driverAccepted` (não lhe toquei).
- O dispatch deu o Favor a um estafeta ocupado (a missão diz que `dispatch_candidatos_entrega` só o dá
  a quem está livre). Não mudei quem recebe ofertas; fica para investigar (ver "Erros encontrados").

## O desenho escolhido

### 1. Compra guardada a cada toque
- App: `lib/services/compra_rascunho_service.dart`. Cada toque (Comprado, Não há, desmarcar, produto
  acrescentado/trocado com o preço, sacos, valor do talão, caminho da foto do talão) grava logo no
  telemóvel (SharedPreferences, também na web) e manda ao servidor com fila: um envio de cada vez por
  pedido, 3 tentativas (1 s, 3 s, 5 s) e depois volta a tentar sozinho (30 s → 5 min). Um número
  crescente (`seq`) impede que uma gravação atrasada apague uma mais nova; toque duplo = o último fica.
- Ao abrir a lista: memória → telemóvel → servidor, ganha o `seq` maior. Se o estafeta já tocou antes
  de o servidor responder, o ecrã não é sobrescrito.
- Texto discreto na folha: "A guardar…", "Guardado", "Guardado no telemóvel · envia com rede".
- Servidor (migração `20261114190000_compra_guardada_e_fila_estafeta.sql`): tabela
  `order_purchase_drafts` (RLS ligada, sem acesso direto), `estafeta_guardar_progresso_compra`,
  `estafeta_ler_progresso_compra` (estafeta atribuído ou admin), `_rascunho_compra_itens_fecho`
  (monta o `p_items` igual ao `TalaoNaoParceiroService.montarItens`), `admin_rascunho_compra`.
- **Dinheiro não mudou:** `finalizar_talao_nao_parceiro` e `finalize_storeshopping_purchase_v2` ficam
  iguais. O fecho só passa a poder usar o rascunho.

### 2. Dois pedidos ativos / fila (adenda 1)
- Em curso = o pedido que o estafeta aceitou quando estava livre, guardado em
  `estafeta_pedido_em_curso` (gatilho `trg_fila_0_em_curso`). O que ele aceita por cima fica EM
  ESPERA: não aparece no mapa nem no início, não troca o pedido. Ao entregar (ou cancelar/passar a
  outro) o seguinte passa a em curso: o já recolhido; senão o da mesma loja (a volta continua); senão
  Favor URGENTE (`errand_speed='express'`, 10 €) → entregas → Favor normal (6 €), e a hora de aceitação
  (`driver_assigned_at`).
- Pedidos da mesma loja do em curso continuam juntos (o agrupamento do `DriverCapacityService` não se
  partiu) e um pedido já recolhido nunca se esconde.
- Ecrã do estafeta: só o pedido ativo + "Tens N pedidos na fila" (toque mostra a ordem). Ao entregar,
  o seguinte abre com vibração, som e o aviso "Próximo pedido · loja — cliente" com "Abrir pedido".
  Com fila, o mapa já não volta ao início depois de entregar.
- Com mais de um pedido ativo (mesma loja) aparece "Pedido aberto" com os nomes da loja e do cliente;
  o estafeta troca com um toque e a app nunca troca sozinha (o pedido com a compra aberta fica com o foco).
- Regra gémea: app `lib/services/fila_estafeta.dart` ↔ servidor `fila_do_estafeta` /
  `_fila_proximo_em_curso`. A app pergunta ao servidor (`estafeta_minha_fila`) uma vez por mudança nos
  pedidos; sem rede usa a mesma regra local.
- Aviso ao cliente: gatilho `trg_fila_avisar_cliente` — quando uma ENTREGA fica em espera, um aviso
  por pedido (notificação + caixa da app): "O estafeta está noutro pedido perto de si. Assim que o
  terminar, segue para o seu." O ecrã do pedido do cliente mostra o mesmo (`cliente_fila_do_meu_pedido`).
  Favor nunca avisa. O aviso nunca trava a aceitação (erro → só NOTICE).

### 3. Painel admin (PT-BR)
- Menu "Filas dos entregadores": a fila de cada entregador (ATIVO / EM ESPERA, tipo, loja, cliente,
  itens marcados). Toque → rascunho da compra.
- Detalhe do pedido: secção "Rascunho da compra" (cada item com Comprado / Não tem / Falta marcar,
  acrescentados com preço, sacolas, valor e foto do cupom, hora da última marcação) e "Copiar itens
  (p_items)" para fechar sem refazer a compra.

## Revisão com contexto limpo (verificador)

Um revisor independente encontrou 10 problemas (nenhum de dinheiro). Corrigidos: (1) uma leitura
lenta do servidor podia repor uma versão velha por cima de um toque novo — agora fica sempre o `seq`
maior e a folha junta o do servidor só nas linhas não tocadas; (2) pedido sem loja (NULL) passava à
frente do Favor urgente na ordem do servidor — `COALESCE(..., false)`; (3) gravação recusada por ser
"velha" aparecia como "Guardado" — agora reenvia acima do número do servidor; (4) app reiniciada sem
servidor esquecia o em curso — fica guardado no telemóvel e a compra começada tem prioridade; o aviso
"Próximo pedido" só aparece quando um pedido saiu mesmo; (5) o preenchimento inicial do em curso usa o
primeiro aceite, não a classe; (6) o aviso ao cliente volta a confirmar a cada minuto; (7) o mesmo
estafeta reescrito de user_id para drivers.id já não muda o em curso; (8) linhas sem productId usam o
nome como chave (igual à app); (9) resposta velha do servidor já não sobrescreve a nova; (10) duas
aceitações ao mesmo tempo ficam em fila por um cadeado (advisory lock). Por fazer: o aviso "Próximo
pedido" só existe no mapa (no início aparece o cartão do pedido seguinte, sem som).

## Provas

- `supabase/tests/compra_guardada_fila_prova.mjs` no PGlite 0.2.17 com a migração tal como está:
  **48 certos, 0 falhados**. Anti-mentira: as mutações que mudam o comportamento são apanhadas (seq
  atrasado, classe do urgente, Favor sem aviso, em curso velho, NULL no DESC, mesmo estafeta
  reescrito, chave sem productId).
- `flutter analyze` dos ficheiros mexidos: 0 erros; os avisos que aparecem são de código antigo.
- `flutter test`: `fila_estafeta_test.dart`, `compra_rascunho_service_test.dart`,
  `compra_guardada_lista_widget_test.dart` (ver o resultado literal no e2e_log).

## O que NÃO ficou provado (e porquê)

- **Migração não aplicada em produção**: a bora-tranca recusou (`apply_migration` = publicar) e a
  trava recusou a prova em rollback. Fica para a Claude.ai aplicar (ver abaixo). Até lá a app guarda
  só no telemóvel (já protege contra trocar de pedido, fechar e reiniciar no mesmo telemóvel) e a fila
  usa a regra local; servidor, painel e aviso ao cliente ligam quando a migração entrar.
- **Pedido de teste em dinheiro nas 3 plataformas, publicar nas lojas**: depende da migração e de
  publicar (Claude.ai). O PC tinha 70–250 MB livres (portão do emulador: 3 GB), sem emulador possível.
- O envio para `autonomous-night-2026-04-29` é da Claude.ai (a tranca recusa o push ao executor).

## Para a Claude.ai publicar

1. Aplicar `supabase/migrations/20261114190000_compra_guardada_e_fila_estafeta.sql` (inteira, uma vez).
   Verificação: `select public.fila_do_estafeta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7');` deve devolver
   o Favor 09ee41da como `ativo` (é o único em curso dele) e
   `select count(*) from public.estafeta_pedido_em_curso;` ≥ 1.
2. Juntar o ramo `ai/2026-11-14-compra-guardada` em `autonomous-night-2026-04-29` (o CI sobe o
   versionCode e publica Android + web; iOS pelo TestFlight).
3. Prova nas 3: pedido de teste em dinheiro (is_test_order) numa loja não-parceira, conta demo do
   estafeta: marcar 3 itens + 1 acrescentado + sacos → `select * from order_purchase_drafts where
   order_id='<id>'` → matar a app → reabrir → lista igual. Aceitar um 2.º pedido de teste por cima →
   o mapa continua no 1.º com "Tens 1 pedido na fila" → entregar o 1.º → aparece "Próximo pedido".

## Fechar um pedido pelo rascunho (se a app falhar) — só com ordem do Danilo

A conta é a de sempre (`finalizar_talao_nao_parceiro`); o rascunho só evita refazer a compra.

```sql
-- 1) ver o que está marcado
select public.admin_rascunho_compra('<pedido>');   -- no painel: Filas dos entregadores → pedido
-- 2) fechar como o estafeta (o JWT dele), com a foto e o valor do talão que ele já subiu
do $$ declare d record; r jsonb; begin
  select * into d from public.order_purchase_drafts where order_id = '<pedido>';
  perform set_config('request.jwt.claim.sub', d.driver_uid::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', d.driver_uid, 'role', 'authenticated')::text, true);
  r := public.finalizar_talao_nao_parceiro('<pedido>', d.receipt_photo_path,
         d.receipt_total_cents, public._rascunho_compra_itens_fecho('<pedido>'), d.bag_count);
  raise notice 'fecho: %', r;
end $$;
```

## Erros encontrados pelo caminho (não corrigidos — fora do âmbito)

1. O dispatch ofereceu e deixou aceitar o Favor `09ee41da` a um estafeta com um pedido ativo
   (Auchan), contra o que a missão diz de `dispatch_candidatos_entrega`. Com a fila isto já não troca o
   pedido, mas convém ver porque é que o Favor chegou a um estafeta ocupado (zona vermelha: dispatch).
2. `finalizar_talao_nao_parceiro` não escreve o `purchaseStatus` de volta em `orders.items` (fica
   `pending` mesmo depois de fechado); o histórico real está em `order_purchase_items_v2`. Não mexi
   (dinheiro).
3. `flutter pub get` reescreve `analysis_options.yaml` e os registos de plugins de linux/macos/windows;
   não foram enviados.
