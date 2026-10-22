# Revisão N3b — contexto limpo (maker/checker) · 22/10/2026 ~05:15

Revisor: Claude Code (Opus), sem ter escrito o trabalho. Objeto: commit `b740fb3d` (ramo `n3b-22-10`, sobre
`origin/autonomous-night-2026-04-29` = `4e6030c1`), duas migrações ainda **não aplicadas**:
`20261022050000_n3b_lavagem_escrita_direta_guarda.sql` e `20261022050100_n3b_pedido_cliente_loja_estafeta_guarda.sql`.
RAM medida no arranque: 1812 MB disponíveis (portão leve 400 MB: ok).

## VEREDICTO: NÃO (por agora)

O núcleo está certo e não parte nada que a app faça hoje. Mas a entrega deixa o cliente escrever o estafeta
por outra porta (criar o pedido já com a lista de estafetas excluídos), e a metade "leitura" da ordem não foi
feita **nem foi dita ao Danilo em lado nenhum** — só num comentário do SQL que cita um relatório que não o diz.
São 3 mudanças pequenas para passar a SIM (fim deste ficheiro).

## O que está bem (com prova)

- **Ataques bloqueados** (prova do autor + a minha): dono muda loja / tira parceiro / muda nome da loja / põe
  estafeta / põe oferta / pré-atribui / exclui estafetas / põe ajudante / mexe no histórico de ofertas → `42501`.
  O meu t03 (transição que o R2 deixa, `created→preparing`, **mais** estafeta na mesma escrita) →
  `42501 pedido_loja_estafeta_so_pelo_servidor (assigned_driver_id)`. Lavagem: cliente mexe em total, estado, ganho,
  pagamento, `offer_washer_id`, `rating` → `42501 lavagem_so_pelo_servidor (...)`.
- **Defeito plantado apanha** (do autor: d1/d2; meus: dA tirar o gatilho de UPDATE → t03 passa a `PASSOU (1)`;
  dB guarda da lavagem vazia → c01 passa a `PASSOU (1)`). O teste não é vazio.
- **Nenhum caminho legítimo da app parte** (procurado no código, não adivinhado):
  - `lib/`: só 9 escritas diretas em `orders` (`order_store.dart` 1071, 1510, 1967, 1995, 2019, 2961, 2995, 3014;
    `driver_store.dart` 638). Só a 1510 (`cancelDelivery`) toca colunas guardadas — é o estafeta, não o dono, e
    **não tem chamadores** (só a definição aparece no `grep`); o ecrã usa o RPC `driverCancelAcceptedOrder`.
    `_updateOrderStatusInDatabase` só manda `driver_offer_expires_at` se lhe passarem `driverOfferExpiresAt`, e
    nenhum chamador passa (1285, 1357).
  - `lib/`: **uma só** escrita direta em `carwash_bookings` (`carwash_store.dart:372`, `photos_client`). Zero
    `insert/upsert` diretos em `orders` em `lib/`, `supabase/functions/`, `web/` (procura por `.from('orders').insert`
    e por `rest/v1/orders` com POST/PATCH).
  - Edge Functions que escrevem `orders`: todas pelo cliente de serviço (`admin`/`supabase` com a chave de
    serviço); o cliente com o token do utilizador só faz `auth.getUser()` e `rpc(...)`.
  - Base: **0** funções SECURITY INVOKER (em qualquer esquema) com `UPDATE/INSERT INTO orders|carwash_bookings`
    (regex com `\y`); as que escrevem (50 em `orders`, 20 em `carwash_bookings`) são todas SECURITY DEFINER do
    dono `postgres` → `current_user = postgres` → a guarda deixa passar.
  - Demo: `t10b` (conta demo cria pedido sem estafeta) → `PASSOU driverAccepted drv=dede…0002/dede…0001`: o gatilho
    `a_trg_pedido_demo_caixa_fechada` continua a pôr o estafeta demo, porque `a00_…_ins` corre antes e o `WHEN`
    vê o NEW ainda sem estafeta.
- **Não dá para forjar a exceção "dono que aceitou como estafeta"**: `order_status_events` só tem
  `authenticated:SELECT` (sem INSERT; `anon` nada), RLS ligada, uma política só de leitura. O R2 só deixa ao
  cliente `created→preparing` e `preparing→callingDriver`, nunca `driverAccepted`. Na base há **0** eventos
  `driverAccepted` com `actor_uid` = dono do pedido. Buraco nenhum, nem novo nem antigo.
- **anon**: `t06` → `PASSOU (0)` (a RLS não lhe mostra linhas). `auth.uid()` nulo → a guarda deixa, mas a RLS de
  `orders_update_client` (`auth.uid() = user_id`) já não deixa nada. `_pedido_cliente_loja_estafeta_recusa`:
  `authenticated` executa, `anon` não.
- **Ordem dos gatilhos BEFORE** (nomes em ordem "C"): UPDATE em `orders` = `a00_pedido_cliente_guarda` (R2, não mexe
  no NEW) → `a00_pedido_loja_estafeta_guarda_upd` → `aa_…`; INSERT = `a00_pedido_loja_estafeta_guarda_ins` →
  `a0_orders_preenche_restaurant_id` → `a_trg_pedido_demo_caixa_fechada`; `carwash_bookings` UPDATE =
  `a00_lavagem_escrita_direta_guarda` → `trg_carwash_bookings_touch` → `trg_checkin_premio_guarda_pagamento_upd`.
  Nenhum gatilho anterior muda as colunas guardadas. `carwash_bookings` não tem colunas geradas (o `to_jsonb(NEW)`
  não dá falsos "mudou").
- **Igual ao que vai ser aplicado**: md5 do `prosrc` dentro da transação = md5 local do corpo nos ficheiros
  (`8ad7e521…`, `67427293…`, `98379cf2…`). md5 dos ficheiros = os do RESULT do autor (`166ffb57…`, `96de454f…`).
- **Nada ficou**: antes/depois da minha prova — md5 dos 3 pedidos de teste `78a9b148…` = `78a9b148…`, md5 das
  lavagens `6697513f…` = `6697513f…`, 2 lavagens, 2 eventos, 1 auditoria, fila pg_net 0, pedidos do T 0, do A 4,
  0 funções e 0 gatilhos N3b no ar.

## Achados

| # | Gravidade | Onde | Cenário concreto | Prova |
|---|---|---|---|---|
| 1 | **MÉDIA (bloqueia)** | `20261022050100_…sql:71-79` e `:114-120` (INSERT só olha 5 colunas) | O cliente cria o pedido **direto pela API** (política `orders_insert_client`, que nenhuma app usa) já com `tried_driver_ids` = todos os estafetas menos o amigo → o despacho nunca oferece aos outros. É exatamente o ataque `o7` que a própria entrega chama ataque e bloqueia no UPDATE. O mesmo com `driver_offer_expires_at` e `driver_offer_history`. | `t09b`: `PASSOU created tried={dede…0002}`; `t13`: `PASSOU created exp=…`; `t09a`: chega ao `CASH_LIMIT_EXCEEDED` (a guarda nem disparou). |
| 2 | **MÉDIA (bloqueia — honestidade do relatório)** | `20261022050000_…sql:13-16` | A ordem diz "leitura/escrita". A leitura **continua aberta**: o cliente vê quanto o lavador ganha e a taxa da Bora; o lavador vê a taxa da Bora. A razão técnica é verdadeira (`carwash_store.dart:178/231`, `washer_store.dart:139/159` fazem `.select()` = todas as colunas; tirar o SELECT de colunas a `authenticated` dá erro a essas leituras e o lavador também deixaria de ver o próprio ganho). **Mas** o comentário diz "relatório da noite 21/10, PARA O DANILO" e esse texto não existe: procurei em todos os `.md` das missões desde 19/10 (worktree e árvore principal) e no `RELATORIO-D.md` — a única menção é sobre **escrita** (linhas 272-273). Não há `RELATORIO-N3b.md`. | `c05`: `PASSOU total=2000 ganho_lavador=1700 taxa_bora=300` (cliente); `c06`: `PASSOU total=2000 taxa_bora=300` (lavador). |
| 3 | BAIXA-MÉDIA | `20261022050000_…sql:30-31` | `photos_client` fica livre para **qualquer** não-admin com acesso à linha, incluindo o lavador: pode apagar/trocar as fotos que o cliente tirou ao carro (a prova do estado do carro numa queixa de risco). | `c03`: `PASSOU (1)` (lavador põe `["do-lavador.jpg"]`). |
| 4 | BAIXA | prova do autor `prova_n3b_rollback.sql:76-78, 81-82, 83-84` | Três "legítimos iguais" são vazios e contam como sucesso: `l3` (cliente cria sem estafeta) falha com `STORE_CLOSED` antes **e** depois — não prova que o INSERT legítimo passa; `l5` (admin muda loja) = `PASSOU (0)` — 0 linhas, não há política de UPDATE de admin em `orders`; `l6` (estafeta desiste) falha por RLS antes e depois (código morto). Não escondem defeito (os meus `t12`/`t10b` cobrem o INSERT legítimo e o demo), mas o RESULT não deve chamar-lhes "legítimos que passam". | RESULT do autor, linha 2. |
| 5 | BAIXA | `20261022050100_…sql:43-54` | Colunas vizinhas que o dono continua a escrever: `pickup_lat/pickup_lng` (o ponto de recolha = onde está a loja; o estafeta é mandado para outro sítio) e `driver_phone`. A app do cliente não as escreve (lista das 9 escritas acima). `fn_recalc_earnings_on_assign` não usa `pickup_lat` (verificado), por isso não é dinheiro. | `t01`: `PASSOU (1)`; `t02`: `PASSOU (1)`. |
| 6 | INFO (fora da ordem; buraco antigo) | políticas `orders_update_driver` / `orders_update_partner` | Quem **não** é dono continua a escrever loja/estafeta: o estafeta muda a loja do pedido que leva; o parceiro põe um estafeta direto no pedido da sua loja, sem passar por `ops_reassign_order`. `platform_settings.orders_driver_direct_update_block = false`. | `t07`: `PASSOU (1)`; `t08`: `PASSOU (1)`. |
| 7 | INFO (buraco antigo) | política `orders_insert_client` | O cliente cria um pedido cru direto na tabela (sem itens, sem loja, preço à escolha), saltando o `create_order`. Nenhuma app usa este caminho. | `t12`: `PASSOU created` (sendPackage, preço 10, sem itens). |

## O que tem de mudar para passar a SIM

1. **INSERT (achado 1)** — escolher uma:
   - (a, mínima) no gatilho `a00_pedido_loja_estafeta_guarda_ins` e no `CASE` juntar
     `coalesce(cardinality(NEW.tried_driver_ids),0) > 0`, `NEW.driver_offer_expires_at IS NOT NULL`,
     `coalesce(NEW.driver_offer_history, '[]'::jsonb) <> '[]'::jsonb` (verificado na base: `driver_offer_history`
     nasce `'[]'::jsonb` por defeito; `tried_driver_ids` é `text[]` sem defeito; `driver_offer_expires_at` sem
     defeito — comparar com NULL bloquearia todos os INSERTs); ou
   - (b, mais limpa) recusar **todo** o INSERT direto de `authenticated` não-admin em `orders` (nenhuma app o usa;
     `create_order` é SECURITY DEFINER e não passa por aqui). Fecha também o achado 7 e o `is_partner_store`
     escolhido à mão no INSERT.
   Acrescentar à prova o ataque `t09b` (tem de dar `42501`) e um INSERT legítimo que **chegue ao fim** (`t12`,
   sendPackage sem loja) para não depender da hora da loja.
2. **Leitura (achado 2)** — escrever no relatório N3b, em português simples, para o Danilo: "a escrita ficou fechada;
   a **leitura não**: o cliente ainda consegue ver quanto o lavador ganha e a taxa da Bora, e o lavador vê a taxa da
   Bora. Fechar isto obriga a mudar a app (pedir só as colunas que cada um precisa) e publicar nas 3 lojas; só
   depois se tira a leitura na base." Tirar do comentário do SQL a referência a um relatório que não o diz (ou
   apontar para o relatório N3b novo).
3. **Fotos (achado 3)** — deixar mudar `photos_client` só quando `auth.uid() = OLD.client_user_id`. Uma linha.
4. Recomendado (não bloqueia): marcar `l3/l5/l6` como "vazios" no RESULT, ou trocá-los por casos que corram;
   considerar `pickup_lat/pickup_lng` na lista guardada (a app do cliente não os escreve).

## Chão determinístico (saída literal)

```
python .claude/juiz/anti_trapaca.py --base origin/autonomous-night-2026-04-29 --head HEAD
  JUIZ · CHÃO ANTI-TRAPAÇA (determinístico)  →  ✅ CLEAN
  ficheiros alterados: 8 (teste: 0, código: 0)
  VEREDITO: chão limpo. Segue para Camada 1/2/3.
exit=0

python .claude/juiz/zonas_diff.py --base origin/autonomous-night-2026-04-29 --head HEAD
  JUIZ · CAMADA 2 (3) ZONAS PROTEGIDAS  →  ✅ CLEAN
  Nenhuma zona protegida no diff.
exit=0
```

Nota: o `zonas_diff` só olha ficheiros; estas migrações põem gatilhos na tabela `orders` (vizinha da "RLS de
orders" protegida). Não mudam políticas nem valores, e a ordem do Danilo de 22/10 04:33 pede-o explicitamente.

## Ficheiros da revisão

- `n3b/revisor_prova_n3b.sql` — a minha prova (parte 1 + as duas migrações tal como estão + parte 3), DO + RAISE.
  Corri o mesmo texto com o cabeçalho de comentários da 2.ª migração encurtado; os corpos das funções batem por md5.
- `n3b/revisor_prova_n3b_RESULT.json` — saída literal + antes/depois.
- Nada aplicado, nada empurrado, sem commit.

---

# Ronda 2 — commit `3745d21b` (sobre `b740fb3d`) · revisão às ~05:25 de 22/10

RAM no arranque da ronda: 2010 MB disponíveis (portão leve: ok).

## VEREDICTO RONDA 2: SIM — aplicar as duas migrações na base

Os 3 achados que bloqueavam estão corrigidos e provados por mim, de forma independente, com defeito plantado.
**Uma condição antes de levar os ficheiros ao GitHub** (achado R2-1): a frase do relatório "não dispara build" está
errada para um envio ao ramo de produção.

## O que conferi (saída literal em `n3b/revisor_prova_n3b_r2_RESULT.json`)

- **Diff `b740fb3d..3745d21b` nas migrações**: só três mudanças de código — (1) no INSERT, o `CASE` e o `WHEN` do
  gatilho `_ins` passam a recusar `cardinality(tried_driver_ids) > 0`, `driver_offer_expires_at IS NOT NULL` e
  `coalesce(driver_offer_history,'[]') <> '[]'` (iguais nos dois sítios); (2) `photos_client` só muda se
  `auth.uid() = OLD.client_user_id`, senão `42501 lavagem_fotos_so_do_cliente`; (3) comentários. A função
  `_pedido_cliente_loja_estafeta_recusa` (UPDATE) não mudou (md5 `67427293…` igual à ronda 1).
- **O texto testado é o dos ficheiros**: md5 do `prosrc` na transação = md5 local do corpo em `3745d21b`
  (`425ae3c9…`, `6b7051b4…`, `67427293…`). md5 dos ficheiros = os do RESULT r2 do autor (`8c0c3906…`, `061d9f9b…`).
- **Achado 1 fechado**: `t09b` (criar com lista de excluídos) → `42501 … (tried_driver_ids)`; `t13` (oferta a
  expirar + histórico) → `42501 … (driver_offer_expires_at)`; novos: `n2` (histórico `null` em JSON) e `n2b` (só
  histórico) → `42501 … (driver_offer_history)`.
- **Sem falsos positivos no INSERT**: `L5` cliente cria sem estafeta → `PASSOU created tried=- hist=[]` (o
  `'[]'` por defeito não dispara); `L6` com lista vazia `'{}'` e `'[]'` → `PASSOU created`; `L7` conta demo →
  `PASSOU driverAccepted drv=dede…0002/dede…0001` (o gatilho demo continua); `L8` servidor com lista e histórico →
  `PASSOU created`.
- **Achado 3 fechado**: `c03` lavador troca foto → `42501 lavagem_fotos_so_do_cliente`; `c03b` lavador apaga (NULL)
  → igual. Continuam: `L1` cliente anexa foto como a app (`[{"angle":"","url":…}]`) → `PASSOU (1)`; `L2` lavador
  escreve sem mexer na foto → `PASSOU (1)`; `L3` admin troca foto → `PASSOU (1)`; `L4` servidor → `PASSOU (1)`.
- **Ronda 1 continua**: `t03` → `42501 … (assigned_driver_id)`; `c01` → `42501 … (offer_washer_id)`; `L9` dono muda
  notas → `PASSOU (1)`. Privilégios: `authenticated` executa a função de decisão, `anon` não.
- **Defeitos plantados meus**: `dC` gatilho `_ins` com o `WHEN` da ronda 1 → `t09b` volta a `PASSOU created`;
  `dD` guarda da lavagem sem a regra das fotos → `c03` volta a `PASSOU (1)`. O teste não é vazio.
- **Achado 2 fechado**: `RELATORIO-N3b.md` (novo) tem "PARA O DANILO" n.º 1, em português simples: o que fica aberto
  (exemplo 20 € / 17 € / 3 €), porquê (a app lê a lavagem inteira; o lavador precisa do seu ganho), e os 3 passos
  (mudar a app → publicar nas 3 e esperar → tirar a leitura na base). O comentário de `20261022050000` aponta para lá.
- **Achado 4 fechado**: no RESULT r2 do autor, `v3/v5/v6` estão como "vazios" e fora da contagem de legítimos;
  entraram `o9b/o9c/o9d`, `l10`, `l11`, `c9`, `d3`, `d4` — todos com o resultado esperado.
- **Reversão** (`n3b/reversao_N3b.sql`) cobre os 3 gatilhos e as 3 funções.
- **Nada ficou** depois da minha prova: md5 pedidos de teste `78a9b148…`, lavagens `6697513f…`, 2 lavagens,
  2 eventos, 1 auditoria, fila pg_net 0, pedidos do T 0, do A 4, 0 funções e 0 gatilhos N3b no ar.

## Achados da ronda 2

| # | Gravidade | Onde | O quê | Prova |
|---|---|---|---|---|
| R2-1 | **MÉDIA (condição para o envio ao GitHub, não para aplicar na base)** | `RELATORIO-N3b.md:53-54` | Diz que o envio "(só migrações e documentos: não dispara build)". Se for um envio ao ramo `autonomous-night-2026-04-29`, **dispara**: `build_android.yml` e `build_web_deploy.yml` só ignoram `**.md`, `.claude/**`, `docs/**` e 2 ficheiros do Em Dia — `supabase/migrations/*.sql` não está na lista, e basta um ficheiro fora da lista para o build correr (novo versionCode + Play + site). Push é publicação. Corrigir a frase e decidir se os `.sql` vão sozinhos (gastam uma versão sem mudar a app) ou à boleia da próxima publicação a sério. O iPhone não dispara (`build_ios.yml` só olha `lib/**`, `ios/**`, `pubspec.yaml`…). | `paths-ignore` lidos nos dois ficheiros (ver conversa); `git diff --name-only origin/…  HEAD` mostra os 2 `.sql` no ramo. |
| R2-2 | BAIXA | `prova_n3b_rollback_r2_RESULT.json:1` e `RELATORIO-N3b.md:40` | Dizem que a prova r2 correu "~05:35"; o commit `3745d21b` é das 05:19:57 e o relógio da base marcava 05:23 quando verifiquei. Hora estimada, não medida. O conteúdo reproduzi-o eu (acima), por isso não muda o veredicto — só corrigir a hora. | `git log` + `now()` da base. |
| R2-3 | INFO | commit `3745d21b` | O autor meteu no commit o meu `REVISAO-N3b.md` e os meus `revisor_prova_n3b*.sql/json` (iguais ao que escrevi: `git status` limpo antes desta ronda). Não é problema; fica registado que o commit não foi meu. | `git diff --stat b740fb3d 3745d21b`. |

Ficam como estavam (não bloqueiam, já estão no "PARA O DANILO" do relatório): leitura do dinheiro das lavagens
aberta; estafeta/parceiro ainda escrevem loja/estafeta (não são donos); INSERT "cru" direto (toca preços → decisão
dele); coordenadas de recolha e telefone do estafeta pelo dono.

## Chão determinístico (ronda 2, saída literal)

```
python .claude/juiz/anti_trapaca.py --base origin/autonomous-night-2026-04-29 --head HEAD
  JUIZ · CHÃO ANTI-TRAPAÇA (determinístico)  →  ✅ CLEAN
  ficheiros alterados: 14 (teste: 0, código: 0)
  VEREDITO: chão limpo. Segue para Camada 1/2/3.
exit=0

python .claude/juiz/zonas_diff.py --base origin/autonomous-night-2026-04-29 --head HEAD
  JUIZ · CAMADA 2 (3) ZONAS PROTEGIDAS  →  ✅ CLEAN
  Nenhuma zona protegida no diff.
exit=0
```

## Ficheiros da ronda 2

- `n3b/revisor_prova_n3b_r2.sql` — a minha prova r2 (DO + RAISE). `n3b/revisor_prova_n3b_r2_RESULT.json` — saída.
- Nada aplicado, nada empurrado, sem commit meu.
