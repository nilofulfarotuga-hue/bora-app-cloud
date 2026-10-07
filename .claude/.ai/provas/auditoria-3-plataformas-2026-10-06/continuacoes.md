# Triagem das continuações do inbox — o que está feito e o que falta

Escrito a 07/10/2026 por uma sessão só de leitura. Nada foi editado, apagado, commitado nem empurrado; no Supabase só correram SELECT e leitura de registos.

Base de comparação: a pasta limpa `C:\BoraLocal\_auditoria-3p`, cujo `HEAD` é `383708b4` (ci: bump versionCode to 655), igual a `origin/autonomous-night-2026-04-29` (`git rev-parse` dos dois deu o mesmo hash). Os ficheiros de inbox lidos são os dessa pasta (iguais aos da principal). Estado do ar no momento: `platform_settings.app_latest_version_code = 655`, Edge `dispatch-engine` v62, `notify-tvde-driver` v21.

Legenda: FEITO, AINDA-FALTA, JA-NAO-FAZ-SENTIDO. Marquei também cada item que falta como ZONA-PROTEGIDA/DINHEIRO (só propor), PRECISA-DE-APARELHO (emulador ou estafeta real) ou SEGURO-AGORA (Flutter ou SQL sem dinheiro).

## Resumo em uma linha por ficheiro

1. `CONTINUAR-contas-claras-20260920.md` — quase tudo feito; faltam as decisões de dinheiro do Danilo e dois defeitos de identidade (id contra user_id) em SQL de leitura.
2. `CONTINUAR-contas-claras-20260921.md` — C6 e C7 feitos; faltam rejeitar a candidatura acidental, o vigia do vermelho dos parceiros e arrumação de nomes.
3. `CONTINUAR-fable-13-09.md` — ARQUIVAR: tudo feito ou obsoleto.
4. `CONTINUAR-hora-lisboa-2026-10-06.md` — manter: 6 dos 7 pontos ainda faltam (um é dinheiro).
5. `CONTINUAR-missao-noite-2026-10-03.md` — manter: o Gmail tem prazo de 10/10 (daqui a 3 dias); o ponto 4 (Favor) está feito.
6. `CONTINUAR-noite-fecho-2026-09-24.md` — ARQUIVAR: o marco de arranque ficou velho, a missão fechou a 25/09.
7. `CONTINUAR-ronda-dinheiro-despacho-2026-10-05.md` — manter só os restos; o grosso está feito; há um valor temporário de despacho que ficou por repor.
8. `CONTINUAR-tvde-oferta-fantasma-2026-10-01.md` — falta só a prova no emulador, que não se pode fazer com estafetas reais ligados; fundir com a prova viva de 06/10 e arquivar.
9. `CONTINUAR-tvde-oferta-sobreposta-2026-09-21.md` — ARQUIVAR (Edge subida; o Aceitar já foi provado em produção); sobra uma prova opcional do Recusar.
10. `ORDEM-PENDENTE-iphone-automatico-2026-09-22.md` — ARQUIVAR: o essencial está feito por outras missões; sobram ideias opcionais.
11. `CONTINUAR-ios-portugal-2026-09-16.md` — ARQUIVAR: a app está na App Store de Portugal (prova abaixo).

---

## 1. contas-claras 20/09

Feito, com prova:
- Autoteste dos três perfis e push (ponto 1): FEITO. `e2e_log` fluxo `contas-claras-2026-09-20`, passo "C6 publicação (2.ª, com o C7)": push `1a5c3b1e..1aa46f0a`, CI run 35594439475 com "Autoteste 3 perfis" sucesso, build AAB sucesso, commit `20642af9` "ci: bump versionCode to 613".
- Botão antigo "Marcar pago" que creditava a carteira (ponto 2): FEITO. Em `lib/screens/admin/admin_receipts_screen.dart` há agora dois caminhos separados: linha 544 `admin_mark_receipt_paid` com diálogo "Pagar na carteira do estafeta" (diz que credita) e linha 651 `admin_mark_receipt_paid_external` ("Já paguei por fora", sem creditar). O web foi no mesmo push da C6.
- Invólucro da semana em curso e TVDE no acerto (ponto 3): FEITO pela Claude.ai (a própria nota o diz).
- Proposta `staged_contas_claras_20260920_b8` (ponto 5): FEITO. `platform_settings.staged_contas_claras_20260920_b8.estado = aplicada_pela_claude_ai`, e `pg_get_functiondef` de `compute_driver_settlement` contém `cash_in_hand_cents`. O `e2e_log` "fim-adendo" confirma "b8 aplicado (+gatilho grita no Telegram)".
- Vigia diário (b5): FEITO e activo. `cron.job` `vigia-dinheiro-diario`, `10 6 * * *`, `active = true`.

Falta:
- Ponto 4, decisões de dinheiro do Danilo (cada uma com "vai"): AINDA-FALTA, DINHEIRO, só propor. Estado parcial que consegui provar: o ajuste de +36,00 do TVDE foi aplicado a 23/09 (`admin_audit_log` `tvde_balance_adjust`, 23/09) e houve `settlement_adjust` e `settlement_mark_paid` a 05/10. Não consegui reavaliar uma a uma as restantes (Valdemir 19,50 e Danilo 18,30 de corridas antigas, compensações de 1,50, 14,20, Sabores do Brasil 10,29, linha da Isabel −3,09, Stripe Connect da Goola). Os payouts: a tabela `payouts` tem 10 linhas, todas `failed` desde 07/09; não sei se são os mesmos "3 parados" do relatório. Tudo isto é decisão do Danilo e passa pela Claude.ai.
- Ponto 6a, `get_driver_current_week_summary` lê `drivers` por `id = auth.uid()`: AINDA-FALTA, confirmado. A definição viva tem literalmente `SELECT mbway_phone INTO v_mbway FROM public.drivers WHERE id = v_uid;`. Há 8 estafetas com `id <> user_id`, 4 deles com `mbway_phone` preenchido, para quem o telefone MB Way vem vazio. Correcção: uma palavra (`WHERE user_id = v_uid`). É só leitura de um telefone, mas a função pertence à família do acerto semanal e a Trava do PC tende a recusar DDL aqui: fazer pela Claude.ai com prova em transacção desfeita. Tamanho: 1 linha de SQL.
- Ponto 6b, `v_driver_weekly_earnings` junta por `drivers.id`: AINDA-FALTA, confirmado. Definição viva: `LEFT JOIN driver_balances db ON db.driver_id = d.id` e as `driver_transactions` por `d.id`. Medido: de 4 linhas em `driver_balances` só 2 casam por `drivers.id` (as outras 2 casam só por `user_id`), e de 53 `driver_transactions` só 39 casam por `drivers.id` (14 só por `user_id`). A vista alimenta `lib/screens/admin/admin_driver_payments_screen.dart:42` (painel "Pagamentos a estafetas"), logo mostra valores incompletos para os estafetas com `id <> user_id`. Correcção: juntar por `IN (d.id, d.user_id)` (cerca de 6 linhas de SQL numa vista de leitura). Não move dinheiro, mas é o painel de pagamentos; propor à Claude.ai.

## 2. contas-claras 21/09

Feito:
- C6 (ler o run e registar): FEITO. Linhas "C6 publicação" e "fim" no `e2e_log` (21/09 10:32 e 12:13), run 35594439475 verde, bump 613.
- Helpers de leitura `_repo_*` removidos: FEITO (migration `20260921094845_contas_claras_c6_remove_helper_leitura_repo_2026_09_21.sql` no repo).
- C7, `create_order` a somar a taxa de pedido pequeno: FEITO no ar. `pg_get_functiondef` de `create_order(jsonb)` contém `v_small_order_fee`; `e2e_log` "C7 create_order passa a cobrar a taxa de pedido pequeno" (21/09 13:41) e "C7 prova ponta-a-ponta em rollback" (parceiro 13,87 = quote).

Falta:
- Rejeitar a candidatura acidental do utilizador `c9fccf85-03ee-4efc-83bf-613f211a78ff` (conta do painel): AINDA-FALTA. SELECT: `drivers` com esse `user_id`, `approval_status = pending`, criada 20/09 15:31 UTC, nome "Danilo"; `public.users.email` desse id é NULL (devia ser nilofulfarotuga@gmail.com). Tem de ser pela função `admin_reject_driver(p_driver_id uuid, p_reason text)` com sessão de admin simulada, e o email por UPDATE em `users` (não é uma das tabelas de dinheiro). Não é Flutter. Pequeno: 1 chamada e 1 UPDATE; peço-lhe à Claude.ai/sessão com a Trava aberta; precisa do "vai" por serem dados de uma conta real.
- Vigia do vermelho para parceiros: AINDA-FALTA, confirmado. `_trg_alerta_pedido_no_vermelho_fn` continua a começar por `IF COALESCE(NEW.is_partner_store, false) THEN RETURN NEW; END IF;`, ou seja, ignora os parceiros. É só um alerta (chama `notify_admin_event`), não mexe em valores, mas a função lê `order_driver_reimbursement` e a Trava tende a recusar o texto: propor. Tamanho: cerca de 15 linhas de SQL.
- Reenviar os recibos da semana 14–20/09 (Valdemir e Erika): precisa do "vai" do Danilo e, sendo de há mais de duas semanas, é provável que JA-NAO-FAZ-SENTIDO; não o verifiquei.
- Arrumação: `staged_contas_claras_20260921_c7.estado` ainda diz `por_aplicar` embora a função esteja aplicada, e o ficheiro continua com nome `supabase/migrations/20260921112223_PROPOSTA_contas_claras_c7_pedido_nasce_com_taxa_pedido_pequeno.sql`. SEGURO-AGORA mas é escrita (renomear ficheiro, UPDATE na chave `staged_`): fica para quem tiver autorização de escrita.

## 3. fable-13-09 — ARQUIVAR

- Android 604: FEITO (hoje o versionCode é 655).
- Edge `dispatch-engine` repo v58 contra ar v61: FEITO. O repo tem v62 (`supabase/functions/dispatch-engine/index.ts` linha 2, "v62 (ronda 04/10/2026)") e o ar também (`list_edge_functions` devolve `dispatch-engine` versão 62).
- Frase "Se a App Store disser que ainda não está disponível…" no `baixar`: FEITO. `grep` no repo `bora-site` dá 0 ocorrências e a página viva `https://boraguarda.com/baixar` (HTTP 200) não a contém.
- Linha local `ios-lancamento` (52 commits) fora da produção: JA-NAO-FAZ-SENTIDO. `git cherry` mostra 42 dos 53 commits já na produção por conteúdo (`-`), e `origin/ios-lancamento` é ancestral da produção. Dos 11 que ficam, sobra o andaime "empresa-agentes" (`orquestracao/agentes`, `docs/agentes`) e notas ao revisor da Apple já obsoletas; as duas mudanças de código (`platform_tag_service.dart`, `small_order_fee.dart`) existem na produção.
- Filme do talão no ecrã do estafeta: JA-NAO-FAZ-SENTIDO (a prova foi o pedido real 36e6812a + SELECTs; ver FABLE-2026-09-13 linha 24).
- `cortex_memorizar` que não correu e ferramentas locais: informativo.

## 4. hora-lisboa 06/10 (commits `af8838f3`, `a1aa5594` já no ar; relatório `.claude/.ai/reports/2026-10-06-hora-lisboa.md`)

1. iPhone 1.0.12: FEITO. O relatório `tvde-cartao-preso-2026-10-06.md` linha 71 diz: CI iPhone 171 verde, versão 1.0.12 criada e submetida, estado lido de volta `WAITING_FOR_REVIEW`, lançamento automático. (A 1.0.11 já saiu: o `itunes lookup` de hoje devolve `currentVersionReleaseDate 2026-10-06T18:46Z`.) Falta só a Apple aprovar a 1.0.12, sem nada a fazer.
2. Hora da mesa (reservas): AINDA-FALTA. `lib/stores/reservation_store.dart` linhas 355 e 402 continuam com `'reserved_for': reservedFor.toUtc().toIso8601String()`. Correcção: `instanteDeLisboa(reservedFor).toIso8601String()` nas duas linhas (a função existe em `lib/utils/hora_lisboa.dart:28`), com um teste por fuso. Fica dentro das funções que criam o pagamento do sinal de 3 euros: não muda nenhum valor, mas é código de pagamento; só com o "vai" do Danilo (Lista Vermelha por proximidade). 2 linhas + teste.
3. Dias fechados (`special_dates`): AINDA-FALTA, confirmado. `BusinessHours.fromJson` (`lib/models/restaurant_model.dart:102-113`) só lê `mon..sun`; `isOpenNow` (linha 378) e `statusLabel` (397) nunca consultam dias especiais. O servidor sim: `is_partner_open` procura `special_dates[].date` igual ao dia de Lisboa e usa esse elemento como horário do dia (mesmos campos `open/close/closed`); também respeita `partner_status_override`, que a app também não lê. SEGURO-AGORA (Flutter, sem dinheiro, com testes por instante). Tamanho: cerca de 40 linhas em `restaurant_model.dart` + um teste.
4. Outras diferenças app/servidor: AINDA-FALTA, confirmado pelo código das duas pontas. Servidor: `business_hours` nulo ou não-objecto devolve aberta (`no_hours_configured`); dia sem chave devolve fechada; horas ilegíveis devolvem aberta; não olha a `is_online`. App: `BusinessHours.fromJson(não-mapa)` devolve o horário por omissão 09:00–22:00, e `DayHours.fromJson(null)` também. É uma decisão: qual dos dois cede. SEGURO-AGORA depois da decisão; mexe na regra de aberto/fechado de todas as lojas.
5. Horas das marcações no fuso do telemóvel: AINDA-FALTA. `lib/stores/services_store.dart:301` (`dt.toLocal()` nos slots) e `grep` dá 50 usos de `toLocal()` em 35 ficheiros de `lib` (por exemplo `my_appointments_screen.dart` 435/465/729/751 e `booking_success_screen.dart:112`). Só aparência; já existe o auxiliar `toLisboa()` em `lib/utils/hora_lisboa_ext.dart`. SEGURO-AGORA mas largo: começar pelos três ecrãs do cliente.
6. TVDE "fim de semana" do plano: AINDA-FALTA. `lib/screens/client/tvde/tvde_request_ride_screen.dart:388-390` usa `DateTime.now().weekday`. DINHEIRO (planos de viagens), só propor.
7. Admin "forçar até hoje" expira logo: AINDA-FALTA. `lib/screens/admin/admin_partner_detail_screen.dart:1624` faz `endsAt: instanteDeLisboa(fim)` com `fim` a meia-noite do dia escolhido (o `showDatePicker` dá a data sem hora); escolher "hoje" dá um instante já passado. Correcção: usar o fim do dia (somar 1 dia antes de `instanteDeLisboa`) e mudar a etiqueta para "Até ao fim de dia X". É uma decisão pequena do Danilo. 2 linhas.

## 5. missao-noite 03/10 (relatório `OPUS-2026-10-03-noite-6-blocos.md`)

1. Gmail do caça-clientes: AINDA-FALTA, COM PRAZO 10/10. O `e2e_log` `caca-clientes` passo `c5-ligar` (03/10 21:06) prova que o carteiro está ligado e que o teste de envio e resposta passou; o passo `gmail-permitir` (05/10) diz que a autorização de 03/10 ficou OK. O robô continua vivo (`b4-enviar` de hora a hora até 07/10 05:05 UTC). Mas o token OAuth em modo de teste caduca ao fim de 7 dias (nota do próprio fecho de 03/10): falta Google Cloud, projecto "Default Gemini Project", Branding (as duas páginas dão HTTP 200 hoje: `https://boraguarda.com/` e `/privacidade`) e Audience, "Publicar app". PRECISA-DE-NAVEGADOR (perfil Bora, deviceId `d9e862e0…`), não é Flutter nem SQL; fazer até 09/10.
2. Prova no emulador da troca de modo: AINDA-FALTA. Não encontrei no `e2e_log` nenhuma linha posterior a 03/10 com esta prova. O botão existe (`lib/widgets/profile_switcher_button.dart`, usado em 10 sítios). PRECISA-DE-APARELHO e de uma conta de teste com limpeza e cliente.
3. Medição de frames dos mapas e `TvdeDriverStore.loadCurrent` só notificar quando algo muda: AINDA-FALTA. `lib/stores/tvde_driver_store.dart:301-338`: o `loadCurrent` chama `notifyListeners()` incondicionalmente em cada leitura bem sucedida (linha ~326), e a rede de segurança lê de 10 em 10 segundos quando não há oferta, logo cada leitura redesenha tudo o que ouve a store. Correcção: comparar o estado novo (corrida activa, em stand by, em fila, oferta; por id, estado e prazo) com o anterior e só notificar se mudou; tamanho cerca de 25 linhas + testes (a store tem `debugLeitor` para isso). É Flutter sem dinheiro, mas fica no mesmo ficheiro que a correcção do cartão preso de 06/10 (`b7e529be`, `0fc4b0da`), cuja causa foi justamente avisos que não chegavam ao host: convém fazê-lo com verificador independente e correr `test/tvde_cartao_preso_test.dart`. A medição de frames precisa de aparelho e de uma corrida de teste com IDs blindados.
4. Mesmo defeito do Favor nos formulários de envio de pacote e de levar compras: FEITO. `lib/screens/send_package_form_screen.dart` linhas 145-156 e `lib/screens/carry_groceries_form_screen.dart` linhas 142-152 fazem `await Navigator.push<bool>` ao pagamento e, com `true`, `popUntil` à raiz e abrem `OrdersScreen`; ambos têm a trava `_aAbrirPagamento` (linhas 92 e 90), tal como o `errand_form_screen.dart` (460, 548-557).

## 6. noite-fecho 24/09 — ARQUIVAR

O ficheiro é um marco de arranque ("a começar / a fazer") que nunca foi actualizado. A missão fechou: `e2e_log` `noite-fecho-2026-09-24` passo `fim` (25/09 06:57) diz B1 a B6 feitos.
- `/verificar/<token>`: FEITO e vivo. `GET https://boraguarda.com/verificar/teste-token-inexistente` devolve HTTP 200 com a página "Verificação de motorista TVDE — Bora".
- Resend, espelho das Edge, decisor Hermes em sombra, radar de vídeos, ecrãs do painel: feitos (ver o `fim`).
- Os 3 testes do ecrã da ficha legal que falhavam: o ficheiro `test/motorista_ficha_legal_test.dart` só foi tocado a 23/09, e o CI do iPhone correu a suite completa a 05/10 ("998 passaram, 1 caiu", a que caiu era outra e foi corrigida em `ac626b95`) e a 06/10 (corrida 168). Logo já passam.
- Resto, não-código: commits do `bora-site` por empurrar (AINDA-FALTA de higiene; o site já está no ar por `wrangler`): `git rev-list --count origin/main..HEAD` no repo `bora-site` dá 8 commits à frente, ramo `motorista-ficha-legal-2026-09-23`, mais pastas `avenca/*` por seguir. O repo é público e o push é do Danilo (o guardrail só deixa o ramo do Bora). O decisor continua em sombra de propósito (acerto medido 5/10 e 2/6).

## 7. ronda-dinheiro-despacho 05/10

Feito, com prova:
- Publicar a correcção da loja fechada (ponto 1): FEITO (21h29 de 05/10; entrada #26 do Cérebro actualizada para "Publicado" em `bugs-resolvidos.md` linha 210).
- Armadilha do relógio UTC do autoteste (ponto 2): FEITO, resolvida na raiz pela missão hora-lisboa (a app decide por Lisboa; o autoteste do CI passou às 15h22 UTC sob a nova regra).
- Motor v62 com o primeiro pedido verdadeiro (ponto 3): FEITO. `query_logs` das últimas 24 h: 24 `v62 INVOKED`, 20 `[dispatch] N candidatos` e 20 `SUCCESS`, 0 linhas `v62 403`, 0 `dispatch_candidatos_entrega error`. Exemplo: pedido `947f7206…` (McDonald's, 06/10 22:30 UTC) com "1 candidatos (de 1, excl 0)"; o pedido acabou `cancelled`.
- Favor, dinheiro da paragem em casa: FEITO. `lib/widgets/errand_execution_sheet.dart:262` chama `estafeta_registar_dinheiro_paragem` e a migration `20261005080746` está aplicada.
- Relógio do aparelho nos três sítios (gémeos): FEITO a 06/10.

Falta:
- Valor temporário do despacho: AINDA-FALTA. `platform_settings.dispatch_gps_fresh_seconds_entregas = 172800` (48 h). O `e2e_log` `dispatch-v62-alivio-gps` (05/10 08:14) diz TEMPORÁRIO e "voltar a 900 quando os estafetas tiverem a versão com posição a cada 60 s". Ainda não voltou. ZONA-PROTEGIDA (despacho): só propor; decidir quando os estafetas ligados já mandam posição de minuto a minuto.
- Ponto 4, fecho de "parceiro chama estafeta": AINDA-FALTA, DINHEIRO. `dispatch_parceiro_chama_estafeta_ligado = false`; nenhuma migração a seguir à `20261005061548` toca `post_order_to_ledger` ou `apply_order_financial_split`. Só propor.
- Loja aberta por link partilhado: AINDA-FALTA, confirmado. `lib/screens/deep_link_store_screen.dart:46-66` constrói o `MarketStoreScreen` sem `CartStore.configureSession`; só `restaurants_screen.dart:261`, `stores_screen.dart:392`, `reorder_service.dart:65` e os formulários de favor a chamam. SEGURO-AGORA no sentido de ser Flutter sem zona protegida, mas toca a ligação do carrinho: carregar o `RestaurantModel` completo (como faz `openRetailBusiness`) e fazer o mesmo `configureSession`, com teste; cerca de 30 linhas. Prova ao vivo na web em `#/loja/<id>`.
- Restos do travão: AINDA-FALTA. `CartStore.increaseQuantity` (`lib/stores/cart_store.dart:976-983`) não consulta a loja fechada (3 linhas); a regra "fechada" continua em três sítios (`restaurants_screen`, `stores_screen`, `ReorderService.lojaFechada`); a captura `zz-loja-fechada-sem-carrinho` (`integration_test/demo_real_test.dart:505`) continua sem "falha" no nome, por isso `tool/ci/autoteste_emulador.sh` não a conta como falha suave (renomear = 1 linha). Os "restos do Pedir de novo" não os reverifiquei: nenhum commit depois de `311f8371` toca em `reorder_service.dart`, `orders_screen.dart` ou `market_reorder_tab.dart`, por isso presumo-os inalterados.
- Lojas Lidl, Mercadona e Pizza Hut com `is_online = false`: continuam. `restaurants` confirma as três `false`, `approved`. Pergunta para o Danilo: é de propósito?
- Restos pequenos (secção 6 do ficheiro):
  - `pricing_service.dart` com 2,5 em vez de 0,99: ZONA-PROTEGIDA, e a própria missão disse que já não é preciso (o servidor cobra 0,99). JA-NAO-FAZ-SENTIDO enquanto o ficheiro estiver trancado.
  - Festas, orçamento com saco (`20260825091000_festas_money_patch.sql`): DINHEIRO.
  - "Deixar à porta" com dinheiro, guarda no servidor: gatilho em `orders`, só propor.
  - Rascunhos de pagamento: AINDA-FALTA; `admin_orphan_payments_screen.dart:46-110` já diz a verdade (`.delete().select('id')`), mas o botão continua a existir e não funciona por falta de política. Decisão do Danilo: tirar o botão (Flutter, cerca de 10 linhas) ou dar função própria.
  - Sinal com segredo: fora do que se pode fazer sem mexer em estafetas ao vivo.
  - Carrinho abandonado: o aviso está desligado; falta decidir a regra de quem aceitou promoções.
  - `_notify_partner_status_change`: AINDA-FALTA, confirmado: a função continua a mandar `Bearer <chave anónima>` ao `notify-partner` (que tem `verify_jwt = true`), logo o aviso de mudança de estado ao parceiro não chega. SQL pequeno (usar a chave do cofre como as outras funções), push apenas, sem dinheiro.
  - `log_admin_action`: AINDA-FALTA, confirmado. As duas sobrecargas (`text,text,text,jsonb` e `text,text,uuid,jsonb`) não chamam `is_admin` (a segunda só exige sessão); estão fechadas a `anon`. Os chamadores que encontrei estão todos em ecrãs admin (`admin_bloqueios_screen`, `admin_folgas_screen`, `admin_home_banners_screen`, `admin_orphan_payments_screen`). SQL de segurança sem dinheiro, 1 guarda por sobrecarga; confirmar antes que nenhum ecrã não-admin a chama.
  - Dois ecrãs mortos do parceiro: AINDA-FALTA. `lib/screens/restaurant_dashboard_screen.dart` e `lib/screens/partner_reservations_screen.dart` existem e nenhum `import` os referencia (o único `import 'partner_reservations_screen.dart'` é o da pasta `partner/reservations/`, que é outro ficheiro). SEGURO-AGORA: apagar os 2 ficheiros (e confirmar o `analyze`).
  - Push `carrinho_abandonado` a abrir o carrinho: AINDA-FALTA, pequeno em `notification_service.dart`; sem valor enquanto o aviso estiver desligado.
  - Categoria "Undefined" do Continente: AINDA-FALTA. 14 produtos do Continente com `category` e `category_root` = `undefined`. Correcção de dados (UPDATE em `products`), cerca de 14 linhas; precisa do mapeamento certo de cada produto.
- Secção 7 (só se prova no aparelho): PRECISA-DE-APARELHO e de estafetas/clientes reais.
- Handoff da secção 8: FEITO (a entrada #26 diz "Publicado").

## 8. tvde-oferta-fantasma 01/10

- Correcção no ar: FEITO (commit `7df0fc49`, versão 636).
- Prova no emulador (passo `b3-emulador`): AINDA-FALTA. O `e2e_log` do dia diz que não se fez por falta de RAM; a de 06/10 também não se fez (`tvde-cartao-preso-2026-10-06.md` linha 53: "havia dois motoristas reais ligados… a regra é não fazer pedidos sintéticos"). PRECISA-DE-APARELHO e de zero motoristas reais ligados: não fazer agora. Recomendo juntá-la à prova viva que a missão de 06/10 já deixou marcada ("na próxima corrida real do Danilo, já com a versão 654 ou a 1.0.12") e arquivar este ficheiro quando essa prova existir.

## 9. tvde-oferta-sobreposta 21/09 — ARQUIVAR

1. Subir a Edge `notify-tvde-driver` v17: FEITO e ultrapassado. `list_edge_functions` devolve `notify-tvde-driver` versão 21, `verify_jwt` true; o ficheiro do repo contém `driverEarn`, `offerExpiresAt` e `accept,reject` (14 ocorrências).
2. Botões da notificação no aparelho: PARCIAL. O Aceitar foi exercido em produção: `b7e529be` conta que o Danilo aceitou a volta do pacote pelo botão "Aceitar" da notificação com a app em segundo plano e a corrida entrou. O Recusar continua sem prova própria a frio; hoje o código mantém `showsUserInterface: false` no Recusar (`lib/services/notification_service.dart` linhas 1335-1340), ou seja, headless, e já houve correcção da recusa a 03/10 (`c325d7c5`). PRECISA-DE-APARELHO sem motoristas reais ligados; opcional.
3. Captura do painel admin: JA-NAO-FAZ-SENTIDO (opcional, e a RPC e o botão "Forçar nova roda" existem em `lib/screens/admin/admin_tvde_rides_screen.dart:238`).

## 10. ORDEM-PENDENTE iphone-automático 22/09 — ARQUIVAR

A ordem nunca foi arrancada com este nome, mas o essencial foi feito por outras missões e provado nos ficheiros:
- iOS a construir-se a cada push na branch de produção: FEITO. `.github/workflows/build_ios.yml` linhas 26-47: `concurrency` por ramo com `cancel-in-progress: false`, `push` em `autonomous-night-2026-04-29` com os `paths` do Android, número da build por `github.run_number` (linhas 635-636). O comentário das linhas 28-29 dá a origem: "cada publicação vai para as TRÊS plataformas sozinha" (30/09).
- Porta de qualidade antes de enviar: FEITO (job A com análise, testes unitários, goldens e varredura de ecrãs; o job B só corre se o A ficar verde; a hora-lisboa viu-o a passar a 06/10).
- Envio e submissão para revisão sozinhos, com lançamento automático depois da aprovação: FEITO (`.github/scripts/ios_publicar.py`; `ios-lancar-102-2026-09-23`; 1.0.12 `WAITING_FOR_REVIEW` a 06/10).
- Segredos ASC válidos: provados pelos envios 161 a 171.
Sobra, opcional e sem urgência: grupo interno do TestFlight por API (não há rasto no `ios_publicar.py`), investigar o lançamento faseado e escrever o pedido de revisão acelerada (nada no `LANCAMENTO-IOS-ESTADO.md`), e a proposta de um ecrã admin com a versão no ar em cada loja (só existe `app_latest_version_code` nas definições da plataforma). Nenhum bloqueia nada.

## 11. ios-portugal — ARQUIVAR

Evidência feita agora, ao vivo: `GET https://itunes.apple.com/lookup?id=6809954739&country=pt` devolve `resultCount=1`, `trackName=Bora — entregas e serviços`, `version=1.0.11`, `releaseDate=2026-09-12`, `currentVersionReleaseDate=2026-10-06T18:46:13Z`, `sellerName=Danilo Fulfaro da Silva` e `trackViewUrl=https://apps.apple.com/pt/app/bora-entregas-e-servi%C3%A7os/id6809954739`. O caso da Apple e a espera da verificação de comerciante estão portanto ultrapassados; já a 23/09 o `e2e_log` `ios-lancar-102-2026-09-23` passo 13 registava `lookup country=pt` com `resultCount=1` e versão 1.0.2.
Duas notas que sobrevivem ao arquivo, para outra ordem:
- `platform_settings.ios_hide_nonpartner_logos` continua `false` (SELECT de hoje), e `ios/LANCAMENTO-IOS-ESTADO.md` linhas 49-51 chama-lhe risco 5.2 (logos de terceiros no iPhone), mais as perguntas novas de classificação etária. A 1.0.11 foi aprovada e publicada assim, mas a decisão de ligar o interruptor é do Danilo.
- O questionário fiscal dos EUA e o IBAN do Danilo: não os reverifiquei; deixaram de ser bloqueio de Portugal.

---

## O que se pode fazer já, sem zona protegida nem dinheiro nem aparelho

Flutter (cada ponto com teste):
- `lib/screens/deep_link_store_screen.dart`: ligar o link partilhado a `configureSession` (cerca de 30 linhas).
- `lib/stores/cart_store.dart:976`: `increaseQuantity` respeita a loja fechada (3 a 5 linhas).
- `lib/models/restaurant_model.dart:102-113, 378-410`: ler e aplicar `special_dates` (cerca de 40 linhas).
- Apagar `lib/screens/restaurant_dashboard_screen.dart` e `lib/screens/partner_reservations_screen.dart` (2 ficheiros mortos).
- `lib/screens/admin/admin_partner_detail_screen.dart:1624`: "forçar até" cobre o fim do dia (2 linhas; decisão pequena do Danilo).
- `lib/stores/tvde_driver_store.dart:301-338`: só notificar quando o estado muda (cerca de 25 linhas; mesmo ficheiro da correcção de 06/10, usar verificador independente).
- `lib/stores/services_store.dart:301` e os ecrãs de marcações do cliente: mostrar pela hora de Lisboa (primeiro 3 ecrãs, depois o resto dos 35 ficheiros).
- `integration_test/demo_real_test.dart:505`: renomear a captura para entrar na contagem de falhas suaves (1 linha).
- `lib/screens/admin/admin_orphan_payments_screen.dart`: tirar o botão de excluir rascunhos, se o Danilo disser que sim (cerca de 10 linhas).

SQL sem dinheiro (a migrar com prova em transacção desfeita e espelho em `supabase/migrations`):
- `log_admin_action` (2 sobrecargas): guarda de admin.
- `_notify_partner_status_change`: chave do cofre em vez da anónima.
- `get_driver_current_week_summary` (1 linha) e `v_driver_weekly_earnings` (cerca de 6 linhas): identidade `user_id`; pedem cuidado por serem a família do acerto e do painel de pagamentos.
- Dados: as 14 linhas "undefined" do Continente; rejeitar a candidatura `c9fccf85…` e preencher `users.email`.

## Só propor (zona protegida ou dinheiro)

Fecho do "parceiro chama estafeta"; `dispatch_gps_fresh_seconds_entregas` de volta a 900; hora da reserva no pagamento do sinal; dia de fim de semana do plano de viagens; Festas e saco; "Deixar à porta" com dinheiro; `pricing_service.dart`; decisões de acerto do Danilo (Valdemir 19,50, Danilo 18,30, 14,20, 1,50, Sabores do Brasil 10,29, Isabel, Goola, os 10 payouts `failed`); `vigia do vermelho` dos parceiros (função que lê o reembolso do estafeta).

## Precisa de aparelho ou de pessoas reais

Prova no emulador da oferta fantasma e do Recusar a frio; prova da troca de modo da limpeza; medição de frames dos mapas; sinal do estafeta em segundo plano; "Deixar à porta" com cartão e MB Way ponta a ponta; telemóvel noutro fuso. Nenhuma se faz com estafetas reais ligados.

## Com prazo

Gmail do caça-clientes: publicar a app OAuth até 09/10, senão o token de teste caduca a 10/10.

## Para o Danilo

1. Lidl, Mercadona e Pizza Hut estão `is_online = false`: é de propósito?
2. `ios_hide_nonpartner_logos` a `true` no iPhone, ou deixar como está?
3. "Forçar até dia X" no painel quer dizer até ao fim do dia X?
4. O botão de excluir rascunhos de pagamento: tirar?
5. Horário vazio ou dia sem chave: a app deve passar a seguir o servidor (aberta/fechada) ou o servidor passa a seguir a app (09h–22h)?
