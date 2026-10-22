# RELATÓRIO A1 — Encomendas = cópia exacta do Bora Motorista (só outras palavras)

> 21/10/2026 · agente-encomendas · super-missão `fechar-pendencias-2026-10-20` · motor Opus.
> Ramo `encomendas-20-10` (worktree `C:\BoraLocal\wt-encomendas-20-10`, saído de
> `origin/autonomous-night-2026-04-29` c9226719). **Sem push.** e2e_log fluxo
> `fechar-pendencias-20-10`, run `fechar-pendencias-2026-10-20`, passos `A1-*` (ids 4116, 4121–4133 e o fecho).
> RAM medida: 1892 MB (início), 1343 MB (antes do analyze), 1564 MB (antes dos testes) — acima dos
> 800 MB do portão pesado; nenhum emulador.

## RONDA 1 do revisor (21/10, depois do `REVISAO-A1.md`) — lê isto primeiro

Veredicto do revisor: publicar com o interruptor desligado SIM; ligar NÃO ainda. Corrigido no mesmo
ramo, commits novos, sem push. RAM: 1948 MB antes do analyze, 2812 MB antes dos testes.
e2e_log passos `A1-r1-1`…`A1-r1-5` (ids 4159–4163).

**Em palavras simples.** Fiz isto: (1) fechei o buraco em que uma encomenda que falhava no cartão
deixava a corrida seguinte, a dinheiro, de passageiro, a nascer como "encomenda"; (2) tirei as
palavras de passageiro que ainda apareciam numa encomenda (espera na recolha, quanto ganhaste, fim da
entrega, reservas, recibo, ecrã inicial do estafeta, opções de mobilidade reduzida); (3) deixei pronto,
sem publicar, o aviso do telemóvel "📦 Nova encomenda!"; (4) o painel "Acertos por tipo" passou a
contar as gorjetas pagas por cartão/MB Way, como o acerto a sério. Falta isto: publicar nas 3 e a tua
decisão do acesso (abaixo, "PARA O DANILO") antes de ligar. Próximo passo: revisor → publicar → decides.

| # | O quê | Onde | Prova (saída literal no ficheiro) |
|---|---|---|---|
| 1 | **Defeito E na raiz.** A declaração do tipo leva forma de pagamento + origem + destino, vale 2 min e é gasta por QUALQUER pedido. Só passa à corrida do mesmo pagamento online e do mesmo trajecto; um pedido a dinheiro nunca a herda; declarar com dinheiro é recusado (`invalid_payment_method`). `tvde-payment` intocada. | migração `20261021095810` (md5 104544080a…eb23 = banco), `tvde_store.dart`, commit `b84c5f20` | `a1/prova_r1_declarado_RESULT.json`: ataque exacto do revisor (cartão declarado + dinheiro mesmo trajecto) → `passageiros`; outro trajecto, MB Way vs cartão, declaração com 3 min, passageiros explícito → `passageiros`; encomenda cartão 500/400, reserva MB Way 500/400, ida-e-volta cartão 1760 com ida 855 / volta 855 → `encomendas`. As 3 RPCs só trocaram a linha do resolvedor (md5 conferido antes e reversível ao corpo de 20/10), ACL igual, 1 assinatura cada. |
| 2 | **Palavras.** Estafeta: "À espera na recolha · mm:ss", "Ganhaste €X nesta entrega", "Entrega concluída — ganhaste €X. Próxima entrega ativada.", próxima entrega / fila, os 2 diálogos de devolver reserva (corrida e agenda), avaliação, ecrã inicial ("corridas e encomendas" quando o interruptor está ligado). Cliente: opções de português/mobilidade reduzida escondidas no pedido de encomenda; "As minhas reservas", agenda, avaliação e recibo usam o tipo DE CADA LINHA (`r.rideKind`/`ride.rideKind`), não o do aparelho; etiqueta "📦 Encomenda"; "Código da entrega"; acompanhamento. Servidor: `_tvde_recibo` dá "Resumo da entrega" só às encomendas. | commit `ee624f8c`; migração `20261021101037` (md5 5571f92d…7604 = banco) | `a1/prova_r1_recibo_RESULT.json`: encomenda e passageiro com total 500 / transporte 400 / taxa 100 iguais, só título e aviso mudam. Teste novo `test/encomenda_sem_palavras_de_passageiro_test.dart` (11 casos): estados, fases, cartão de oferta, oferta caducada, reserva, controlos, e varre 15 ficheiros — falha se aparecer passageiro/corrida/boleia num texto de encomenda. |
| 3 | **Aviso push** "🚗 Nova corrida!" → "📦 Nova encomenda!" (e fila, atribuída, passada, cancelada, reservas) feito POR CIMA da v22 do ar (md5 d6d28e6a…), não do repo (que leva a chave do Bloco G). **Não publicado.** | `a1/notify-tvde-driver/` + `a1/notify-tvde-driver_titulo_encomenda.md`, commit `902649ec` | 24 trocas por âncora com contagem; `index.ts` md5 eb45b7af…; passageiros recebem o texto de sempre. |
| 4 | **Acertos por tipo** somam as gorjetas online (mesma regra de `gorjetas_online_do_prestador`), coluna própria no painel. | migração `20261021100840` (md5 05c8f71a…2b3b = banco), `admin_tvde_acertos_tipo_tab.dart`, commit `4fda7b0e` | `a1/prova_r1_gorjetas_no_ar_RESULT.json` (contra a função aplicada): encomenda demo 4,00 a dinheiro + gorjeta 1,50 por cartão → painel **550** cêntimos = acerto real `total_earnings` **5,50**. Depois do rollback: 0 corridas e 0 gorjetas demo gravadas, interruptor `false`. |
| 5 | Decisão do acesso + lei + foto + planos | §9 abaixo | e2e_log `A1-r1-5` (reportado) |

**Dinheiro e despacho intactos (md5 no ar, 21/10 depois das 3 migrações):** `tvde_calculate_fare`
4a1c99dd…, `tvde_fare_breakdown` 96a1fcfc…, `tvde_quote_roundtrip` 5f038a01…,
`tvde_roundtrip_price_for_km` 570bc296…, `tvde_offer_to_next` 40dd523a…, `tvde_dispatch_sweep`
6218c0a3…, `tvde_reservation_offer_to_next` a57c6a5c…, `tvde_reservations_sweep` c2eb13c9…,
`tvde_accept_ride` 88bf043c…, `tvde_cancel_ride` 8712208f…, `tvde_finish_ride` 67eddac1…,
`compute_driver_settlement` 2510dea3…, `gorjetas_online_do_prestador` bded89df…, `_tvde_exige_acesso`
98381d7a…. anon não executa `tvde_definir_tipo_pedido` nem o acerto; o resolvedor nem o cliente executa.
Reversão: `a1/reversao_A1.sql` repõe agora 8 funções (inclui `_tvde_recibo` e `fn_tvde_rides_prefs`) e
apaga o resolvedor/definir novos — reprovada em transacção desfeita: md5 8/8, ACL 8/8, sobra 0.

**Qualidade:** `flutter analyze --no-pub` dos 17 ficheiros tocados → `13 issues found` (0 erros, 0
avisos, 13 infos); as mesmas 4 telas na versão da base dão 14 infos → nenhuma nova. `flutter test` dos
18 ficheiros que tocam estas telas/textos (inclui o teste novo, `ride_kind_textos_test`,
`l10n_cobertura_test`, goldens do TVDE) → `+224: All tests passed!`; antes do último retoque (2 `const`)
a suite inteira deu 1549/1549. `anti_trapaca.py --base origin/autonomous-night-2026-04-29 --head HEAD`
→ `✅ CLEAN`, 60 ficheiros, Δ casos de teste +44. `zonas_diff.py` → `Nenhuma zona protegida no diff`.

**O que continua por fazer (dito, não escondido):**
- Aviso ao cliente "Ainda queres a tua viagem?" (`reserva_confirmar`): quem o manda é
  `tvde_reservations_sweep` (despacho, md5 c2eb13c9…) — não toquei. Numa reserva de encomenda sai
  com "viagem". O aviso "agendada" ao cliente não é enviado pelo servidor.
- Cabeçalho "As minhas corridas" do histórico (lista com os dois tipos misturados) e o ecrã vazio da agenda.
- Frases com valor no meio que o teste-varredura não apanha (só as que estão no mapa são provadas).
- Corridas de balcão e reservas criadas pelo admin nascem sempre passageiros.
- O aviso push só muda quando se publicar `a1/notify-tvde-driver/index.ts`.

## O que NÃO ficou feito (primeiro, como manda o PADRAO §3.9)

> Estado da 1.ª entrega. Depois da ronda 1: o ponto 1 está pronto mas por publicar, o ponto 3 ficou
> reduzido ao que está em "O que continua por fazer" da secção RONDA 1.

1. **O aviso do sistema ao estafeta ainda diz "🚗 Nova corrida!" numa encomenda** (o que aparece
   com o telemóvel bloqueado). Precisa de publicar a Edge `notify-tvde-driver`; não publiquei porque
   o ficheiro do repo está À FRENTE do ar (leva a troca de chave de 16/10, Bloco G) e é a função que
   toca TODAS as ofertas de passageiros. Proposta pronta: `a1/notify-tvde-driver_titulo_encomenda.md`.
   Dentro da app o cartão da oferta já diz "Nova encomenda — agora" com o ganho em número grande.
2. **Não está publicado nas 3** (Android, iPhone, web) nem há capturas de ecrã: é o Bloco F
   (publicador, depois do SIM do revisor). O interruptor `tvde_encomendas_enabled` está **FALSE**.
3. Ficam ainda com palavras de passageiro numa encomenda (raros, listados em "Por fazer"):
   avisos de RESERVA (cliente e estafeta, enviados pelo varrimento das reservas), o recibo do
   servidor (`tvde_recibo_viagem`), o "Código da viagem: …", dois diálogos de devolver reserva
   do estafeta e o ecrã inicial do motorista.
4. Córtex: o MCP do Córtex pede nova autorização nesta sessão — nada gravado lá.

## Em palavras simples (para o Danilo)

Fiz isto: as encomendas passaram a correr no mesmo motor do Bora Motorista. O cliente toca em
"Enviar Encomenda", vê o mesmo ecrã de pedir (mesmo preço, dinheiro/cartão/MB Way, marcar para
depois, ida e volta), mas as palavras são de encomenda: "Pedir entrega", "Estafeta a caminho da
recolha", "Encomenda recolhida", "Encomenda entregue". O estafeta recebe a oferta com "Nova
encomenda" e o que ganha em grande, e os botões dizem "Cheguei à recolha", "Recolhi a encomenda",
"Entreguei a encomenda". No painel há filtro Passageiros/Encomendas nas corridas, nas reservas e um
separador novo com o acerto da semana partido por tipo, e o interruptor para ligar as encomendas.
Provei cinco preços iguais ao cêntimo entre passageiros e encomendas e uma encomenda de teste do
pedido até ao acerto, tudo desfeito no fim, sem tocar em ninguém real.

Falta isto: publicar nas 3 lojas e ligar o interruptor; publicar o título do aviso ao estafeta.

Erros que encontrei pelo caminho: ver "Achados fora do âmbito".

Próximo passo: revisor → publicar → ligar `tvde_encomendas_enabled` → provar 1 encomenda demo nas 3.

---

## 1. Desenho escolhido e diferenças face ao trabalho de 19/10

Segui o desenho do MISSAO.md de 20/10 ("um motor só"), como o orquestrador decidiu. O trabalho de
19/10 (`C:\BoraLocal\wt-encomendas-19-10`, 3 migrações nunca aplicadas) **não foi tocado**.

| Ponto | 19/10 (não aplicado) | Agora (aplicado) | Porquê |
|---|---|---|---|
| Valores de `ride_kind` | 'passageiro'/'encomenda' | **'passageiros'/'encomendas'** | MISSAO.md |
| Como o tipo chega à corrida | só estado `tvde_tipo_pedido` + gatilho | **parâmetro `p_ride_kind` nas 3 RPCs** + tipo declarado SÓ no caminho cartão/MB Way | MISSAO.md manda o parâmetro. Mas o cartão/MB Way cria a corrida dentro da Edge `tvde-payment` (intocável), que chama as RPCs sem o parâmetro → reaproveitei a ideia de 19/10 (tipo declarado, vale 5 min) só para esse caminho, gasto pela própria RPC |
| Omissão do parâmetro | — | **`DEFAULT NULL`** (não 'passageiros') | NULL = "não disse" → usa o declarado; senão 'passageiros'. Para todas as versões instaladas e para a Edge o efeito é 'passageiros' (provado) |
| Volta do pacote | gatilho herda da ida | **igual (gatilho `trg_tvde_ride_kind_da_volta`)** | compatível; cobre `tvde_request_return_ride` e `tvde_roundtrip_schedule_return_core` sem lhes mudar uma linha |
| Acesso | encomendas não pedem o acesso do Bora Motorista | **igual** (portão próprio: `tvde_encomendas_enabled`; admin passa) | decisão do Danilo de 19/10 ("Executa desse jeito"); sem isto o ladrilho Encomendas ficava fechado à maioria dos clientes |
| `tvde_passageiros_enabled` | desligado = só quem tinha acesso antes de 30/09 | **TRUE e ninguém o lê** | NÃO fechar o Bora Motorista |
| `tvde_encomendas_enabled` | TRUE | **FALSE** | orquestrador liga depois de publicar |
| 3.º interruptor `encomendas_antigo_enabled` | criado | **não criado** | o ladrilho decide só por `tvde_encomendas_enabled`; o fluxo antigo (`sendPackage`) fica intocado |
| Avisos ao cliente | título/corpo de encomenda ("motorista") | **igual, com "estafeta"** | MISSAO: motorista → estafeta |
| Funções de cotar (`tvde_calculate_fare`, `tvde_fare_breakdown`, `tvde_quote_roundtrip`…) | — | **intocadas (md5 iguais)** | o preço não depende do tipo; um parâmetro que não muda nada seria uma sobrecarga nova por nada. A prova de dinheiro é sobre as corridas criadas |

**Quem recebe uma encomenda:** os mesmos motoristas do Bora Motorista (`tvde_offer_to_next`
intocado, md5 `40dd523a…`): `vehicle_type='carro_passageiros'`, aprovados, com sinal. A regra de
15/10 (quem desliga o papel não recebe) vale por construção: `tvde_driver_offer_allowed` chama
`aceita_papel` e a Edge `notify-tvde-driver` também. Na prova E2E a oferta da encomenda foi ao
estafeta demo pelo motor de sempre.

## 2. Migrações aplicadas (texto igual no repo, `supabase/migrations/`)

| Versão | Nome | O que faz | md5 do ficheiro |
|---|---|---|---|
| 20261021083257 | encomendas_base | backup das funções (`bkp_fn_encomendas_20261021`, RLS), coluna `ride_kind` (293 antigas = passageiros) + CHECK + índice parcial, 2 interruptores, `tvde_tipo_pedido` (RLS + política só do próprio), `tvde_definir_tipo_pedido`, `_tvde_ride_kind_resolver`, gatilho da volta | d6e26489… |
| 20261021083355 | encomendas_rpcs_ride_kind | as 3 RPCs ganham `p_ride_kind` por troca de âncora sobre a definição no ar (md5 conferido), DROP da assinatura antiga + CREATE (sem sobrecarga), permissões repostas, prova byte a byte dentro da migração | d74f55f1… |
| 20261021083510 | encomendas_avisos_e_painel | aviso ao cliente com palavras de encomenda; `ride_kind` nas listas do painel; `admin_tvde_acertos_por_tipo` (só leitura) | 4283df83… |
| 20261021090625 | encomendas_sem_preferencias_de_passageiro | uma encomenda não herda cadeira de rodas/cão-guia/língua do cliente | efa1d8fb… |

**Reversão:** `a1/reversao_A1.sql` — provada em transacção desfeita: as 7 funções voltam ao md5 e às
permissões de antes, a coluna sai (só se não houver encomendas gravadas).

## 3. md5 e diff das funções protegidas

| Função | md5 antes | md5 depois | corpo sem as linhas do tipo = antes? |
|---|---|---|---|
| tvde_request_ride | 2a60a458a08fdca190c1c6875a7cc45d | 8040a532f11f676ba8eccae5f2ece92e | **sim** (verificado na migração e de novo por fora) |
| tvde_schedule_ride | 9ab25a911968650cf1f83fda6207c3b9 | 72acbc58d18ddbca9e5c67b38a734aff | **sim** |
| tvde_schedule_roundtrip | 15c6d850789b1272ad78702c1d80fe40 | 6bbcc4772c08a394d283b12eb4627fd2 | **sim** |
| fn_tvde_rides_prefs | e0a687d63ff66a9cdae823659726c112 | ccc697f3323c0454d64fb42e82eb5d81 | **sim** (só +2 linhas) |

Diff linha a linha (gerado no banco, antes vs depois), o MESMO nas 3 RPCs:
```
- …(…, p_tokens_to_apply integer DEFAULT 0)            + …(…, p_tokens_to_apply integer DEFAULT 0, p_ride_kind text DEFAULT NULL::text)
+   v_ride_kind TEXT;
-   PERFORM public._tvde_exige_acesso(v_uid);
+   v_ride_kind := public._tvde_ride_kind_resolver(v_uid, p_ride_kind);
+   IF v_ride_kind = 'passageiros' THEN PERFORM public._tvde_exige_acesso(v_uid); END IF;
-     tokens_applied_count, tokens_applied_value_cents)  +     tokens_applied_count, tokens_applied_value_cents, ride_kind)
-     v_tokens_discount_cents)                           +     v_tokens_discount_cents, v_ride_kind)
```
(`tvde_schedule_ride`: idem com `customer_note, payment_status, ride_kind)` / `…ELSE NULL END, v_ride_kind)`;
`tvde_schedule_roundtrip`: em vez do INSERT passa `v_ride_kind` à `tvde_schedule_ride`.)

Intactas (md5 iguais antes/depois, conferido dentro da prova): `tvde_offer_to_next`,
`tvde_calculate_fare`, `tvde_quote_roundtrip`, `tvde_roundtrip_price_for_km`, `tvde_fare_breakdown`,
`tvde_finish_ride`, `tvde_cancel_ride`, `tvde_accept_ride`, `compute_driver_settlement`,
`tvde_create_roundtrip_credit(_cash)`, `tvde_request_return_ride`, `tvde_roundtrip_schedule_return_core`,
`tvde_reservation_offer_to_next`, `tvde_dispatch_sweep`, `_tvde_exige_acesso`, `tvde_ride_charge_cents`,
`tvde_request_plan`, `tvde_quote_plan`. Nada de `dispatch_engine`, `pricing_service.dart`,
`quote_order_pricing`, `create_order`, tokens, Stripe, `stripe-webhook`, `tvde-payment`, RLS de
orders/wallets/ledger, `.claude/settings.json`.

**Chamada antiga e nova vão à mesma função:** 1 assinatura por nome; pelo PostgREST no ar, a
chamada antiga (9 parâmetros, como as apps instaladas e a Edge) e a nova (+`p_ride_kind`) dão
`42501 permission denied for function tvde_request_ride` como anónimo (= função encontrada, igual a
antes); controlo com parâmetro inexistente → `404 PGRST202`. Reserva e ida-e-volta antigas: idem.

## 4. As 5 cotações (iguais SIM, ao cêntimo) — transacção desfeita, cliente demo

| # | Cenário (mesma origem/destino) | Passageiros cliente/motorista/Bora | Encomendas cliente/motorista/Bora |
|---|---|---|---|
| C1 | na hora, dinheiro, 3 km | 500 / 400 / 100 | 500 / 400 / 100 |
| C2 | na hora, dinheiro, 12 km | 1100 / 880 / 220 | 1100 / 880 / 220 |
| C3 | na hora, **cartão**, 7 km (caminho da Edge, sem `p_ride_kind`; encomenda pelo tipo declarado) | 600 / 480 / 120 | 600 / 480 / 120 |
| C4 | **ida-e-volta marcada**, dinheiro, 10 km (servidor: 11,49 km) | 1760 / 855+855 | 1760 / 855+855 (a volta herdou `encomendas`) |
| C5 | **reserva marcada**, dinheiro, 5 km | 500 / 400 / 100 | 500 / 400 / 100 |

10 linhas em e2e_log (ids 4121–4130). Resultado literal: `a1/prova_rollback_dinheiro_RESULT.json`.
Na mesma prova: tipo inválido recusado; sem acesso ao Bora Motorista → passageiros recusado
(`no_tvde_access`) e encomenda aceite; interruptor desligado → `encomendas_desligadas` (pedir e
declarar); o declarado é gasto pela corrida.

**Encomenda demo do pedido ao fim** (transacção desfeita, motoristas reais offline só lá dentro,
`SET CONSTRAINTS ALL IMMEDIATE`): oferta ao estafeta demo → aceitar (`motorista_a_caminho`) →
cheguei → recolhi (`em_andamento`) → entreguei (`finalizada`): cliente 500, estafeta 400, Bora 100,
dinheiro em mão 500; acerto do demo 0 → **−1,00 € (deve à Bora)**, igual à corrida de passageiros
feita a seguir (−2,00 com as duas). Avisos ao cliente com palavras de encomenda; passageiros com a
frase de sempre. Painel: lista e acerto por tipo com `ride_kind`. `a1/prova_rollback_e2e_RESULT_2.json`.

## 5. Flutter (o que mudou)

- `lib/models/ride_kind.dart` + `ride_kind_textos.dart`: o tipo e **um mapa único** (135 frases)
  passageiro → encomenda, PT e EN. `'texto'.trK(tipo)` (cliente, PT/EN), `.rk(tipo)` (estafeta/painel).
- Ecrãs com as palavras por tipo: pedir, acompanhar, reservas, avaliar, recibo, cancelar, MB Way
  (cliente); oferta (cartão e ecrã), a fazer a entrega, agenda, avaliação, aviso do pacote (estafeta).
- `TvdeStore`: `pedidoKind` (posto pelo ecrã, sem `notifyListeners` — evita o "setState a meio do
  build"), `p_ride_kind` só numa encomenda (`tvdeParamTipo`), declaração antes da Edge, repetir
  encomenda = encomenda.
- Home: ladrilho "Enviar Encomenda" → `TvdeRequestRideScreen(rideKind: encomendas)` só com o
  interruptor ligado.
- Painel (PT-BR): filtro + etiqueta "📦 Encomenda" em Corridas e Reservas, coluna Tipo no CSV,
  separador "Acertos por tipo", interruptor editável nas Definições.

## 6. Qualidade (saída literal no e2e_log `A1-fecho`)

- `flutter analyze` dos 29 ficheiros Dart tocados/novos: **0 erros, 0 avisos**, 9 infos — **todas já
  existiam** em `origin` (comparado ficheiro a ficheiro com cópias da versão base).
- `flutter test` **suite inteira: 1536 passaram, 0 falharam** (inclui `l10n_cobertura`, goldens do
  TVDE e do painel). Teste novo `test/ride_kind_textos_test.dart`: 21 casos (mapa completo para os 2
  tipos, nenhuma "corrida/motorista/viagem/passageiro" numa encomenda, nem ride/driver em inglês,
  marcadores de dinheiro iguais, nada de literais coladas, passageiro igual ao de antes).
- `python .claude/juiz/anti_trapaca.py --base origin/autonomous-night-2026-04-29`: **CLEAN** (exit 0,
  +29 casos de teste, 0 achados).
- `identidade-estafeta/verificar.py`: OK (685 ficheiros).
- Fiscal de segurança: anon não executa nada novo nem as 3 RPCs; cliente → `admin_required` no
  acerto/lista, `permission denied` no resolver e na tabela; advisors sem linha nova nossa além do
  backup (RLS sem política, de propósito) e de `tvde_definir_tipo_pedido` (RPC do cliente, valida `auth.uid()`).

## 7. Commits (ramo `encomendas-20-10`, sem push)

- `fb29848a` feat(encomendas): o Bora Motorista ganha o tipo do pedido — passageiros ou encomendas, mesmo motor
- `2eaf1696` feat(encomendas): o mesmo ecrã do Bora Motorista fala de encomenda — camada de palavras por tipo
- `cbef213a` feat(admin): corridas, reservas e acertos do Bora Motorista com filtro Passageiros/Encomendas
- `47d89180` docs(encomendas): relatório do Bloco A1
- Ronda 1: `b84c5f20` (tipo declarado preso ao pedido), `ee624f8c` (palavras), `4fda7b0e`
  (acertos com gorjetas), `902649ec` (aviso push pronto sobre a v22) + commit desta actualização.

## 8. O que o orquestrador tem de fazer depois

1. Revisor de contexto limpo → SIM → push em avanço rápido para `autonomous-night-2026-04-29`
   (o último commit não leva `[skip ci]`; leva código, dispara Android/iOS/web).
2. Antes de ligar: **publicar o título do aviso ao estafeta** (opcional mas recomendado) seguindo
   `a1/notify-tvde-driver_titulo_encomenda.md` POR CIMA da v22 do ar (não o ficheiro do repo).
3. Publicado e provado nas 3: `select public.get_setting('tvde_encomendas_enabled')` → pôr TRUE pelo
   painel (Definições, TVDE) ou `update_platform_setting`, e provar 1 encomenda demo em DINHEIRO nas 3
   (cliente demo + estafeta demo, motoristas reais protegidos: ver memória
   `oferta-sintetica-foge-para-motorista-real`), com capturas do pedir, do "Estafeta a caminho" e do
   cartão de oferta com o ganho em grande.
4. Vigiar a próxima corrida REAL de passageiros depois das migrações (às 09:21Z ainda não houve
   nenhuma): `ride_kind='passageiros'` e estados normais.
5. Bloco F3: `business_rules.md` (Encomendas = TVDE com etiquetas; portão próprio; mesmas regras de
   dinheiro) e digest em `claude_ai_memoria`.

## 9. PARA O DANILO (decisões só tuas — o trabalho seguiu sem elas)

O interruptor das encomendas está **desligado** e assim fica até decidires isto:

- **Acesso (o mais importante).** Hoje o Bora Motorista só aceita clientes com o acesso ligado na
  conta (`users.tvde_access`; a 21/10: 159 de 180 contas têm). Com as Encomendas ligadas, **um cliente SEM esse acesso consegue chamar o mesmo carro
  TVDE desde que diga que é uma encomenda** — o revisor provou-o (sem acesso: passageiros recusado,
  encomenda aceite). Escolhe uma:
  - **(a) A mesma regra para os dois:** quem não tem acesso ao Bora Motorista também não pede
    encomendas. Mais seguro e mais simples de explicar; as encomendas ficam só para quem já tem acesso.
  - **(b) Encomendas abertas a todos:** qualquer cliente pede encomendas (como o "Enviar Encomenda"
    antigo), mas o carro e o motorista são os do TVDE — ou seja, abres o carro a todos por esta porta.
  Diz "a" ou "b". Não liguei nada nem mudei regra nenhuma.
- **Lei:** a licença TVDE é para levar **pessoas**; levar **mercadorias** com os mesmos carros e
  motoristas pode ter de ser enquadrado à parte (transporte de mercadorias / estafeta). Confirmar com
  o contabilista ou o IMT antes de ligar — sobretudo se escolheres (b).
- **Foto da encomenda:** o Encomendas antigo exigia foto antes de pedir; o Bora Motorista não tem.
  Como a ordem é "cópia exacta", ficou SEM foto. Queres a foto obrigatória de volta?
- **Planos:** quem tem plano do Bora Motorista também tem as encomendas cobertas pelo plano (é o
  mesmo motor, mesmo dinheiro). O ecrã diz isso. Se não quiseres, é regra de dinheiro nova.
- **Lei:** a licença TVDE é para passageiros; levar encomendas com os mesmos motoristas pode ter de
  ser enquadrado à parte (transporte de mercadorias / estafeta). Vale a pena confirmar com o contabilista.

## 10. Por fazer (fora do que dava para fechar sem publicar Edge/zonas)

- Avisos de reserva ao cliente ("Reserva marcada", "Ainda queres a tua viagem?") e ao estafeta
  (kinds `reservation_*` da `notify-tvde-driver`) — vivem no varrimento das reservas/Edge.
- Recibo do servidor (`tvde_recibo_viagem`/`tvde-recibo-viagem`): título e aviso legal vêm do
  servidor com "viagem"; a app só troca o texto de recurso.
- "Código da viagem: …" (frase com valor dentro), os 2 diálogos de devolver reserva do estafeta
  (frases coladas em `const`), ecrã inicial do motorista, cabeçalhos do histórico "As minhas corridas".
- Corridas de balcão e reservas criadas pelo admin nascem sempre passageiros (não têm o parâmetro).

## 11. Achados fora do âmbito (só reportados, e2e_log estado 'reportado')

1. `notify-tvde-driver`: o repo está à frente do ar (keys.ts de 16/10 não publicado nessa função) —
   ligado ao Bloco G; quem publicar a partir do repo leva a troca de chave junto.
2. `trg_tvde_ride_zz_dinheiro_em_mao` é `DEFERRABLE INITIALLY DEFERRED`: numa prova em transacção
   desfeita o dinheiro em mão fica NULL e o acerto parece "Bora paga ao motorista" — falso alarme em
   provas futuras; usar `SET CONSTRAINTS ALL IMMEDIATE` (em produção as 48 corridas a dinheiro dos
   últimos 30 dias têm o valor gravado).
3. Num caminho de erro do pedir (`Não foi possível pedir a corrida.`) o texto não tinha `.tr` e
   aparecia em português no modo inglês; agora traduz (só muda no modo EN).
4. A ferramenta Bash desta sessão come barras invertidas dentro de heredocs (scripts com regex têm
   de ir por ficheiro escrito à parte).
