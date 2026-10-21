# RELATÓRIO N2 — Encomendas: o resto (aviso, palavras, mesmo acesso)

> 21/10/2026, noite · agente-encomendas-n2 · missão geral-noite-21-10 · worktree
> `C:\BoraLocal\wt-encomendas-n2-21-10`, ramo `encomendas-n2-21-10` (de origin e768931a), **sem push**.
> e2e_log fluxo `fechar-pendencias-20-10`, passos `N2-*` (ids 4265 a 4307 + o último).
> O interruptor `tvde_encomendas_enabled` **continua desligado** (questão legal do Danilo/IMT).

## Em palavras simples (para o Danilo)

**Fiz isto:**
1. **O telemóvel do estafeta já diz "📦 Nova encomenda!"** quando a corrida é uma encomenda
   (e "Entrega cancelada", "Encomenda em fila", "Encomenda marcada para aceitar"…). Para as
   corridas de passageiros o aviso continua exactamente igual ("🚗 Nova corrida!").
2. **Os avisos ao cliente numa encomenda falam de entrega**, incluindo os das reservas
   ("A tua encomenda ficou marcada", "Ainda queres a tua entrega?") — antes diziam "viagem".
3. **O e-mail do recibo de uma encomenda** diz "Resumo da tua entrega", "Estafeta",
   "Código da entrega", "Valor da entrega". Os números são os mesmos de sempre.
4. **Encomendas com a mesma regra de acesso do Bora Motorista**: quem não tem acesso ao Bora
   Motorista também não pede encomendas — no servidor (provado) e na app (o botão "Enviar
   Encomenda" passa pela mesma porta, que mostra o "pedir acesso"). Antes, com o interruptor
   ligado, um cliente sem acesso conseguia chamar o carro dizendo que era encomenda.
5. **Planos**: quem tem plano do Bora Motorista já tem as encomendas cobertas da mesma forma —
   não foi preciso mudar nada nem tocar em preço nenhum (confirmado no servidor).
6. **Foto da encomenda**: não é obrigatória (o ecrã de pedir não tem foto).
7. **Histórico do cliente**: quando há encomendas, o título passa a "As minhas corridas e
   encomendas" e cada encomenda tem a etiqueta "📦 Encomenda".
8. **Painel (PT-BR)**: o ecrã "Acesso — Bora Motorista" diz que o acesso vale também para as
   Encomendas, e a explicação do interruptor das Encomendas diz a regra nova.

**Falta isto:** ligar as encomendas (é tua a decisão legal) e publicar a parte da app nas 3
(Android, iPhone, web) — isso é do publicador, depois do revisor. O que já foi para o servidor
(avisos, e-mail, regra de acesso) está no ar desde hoje à noite, mas só se nota com as
encomendas ligadas; para os passageiros nada mudou.

**Erros que encontrei pelo caminho:** nenhum novo. Um aviso para o Bloco G (chave nova): a
função dos avisos ao estafeta no repositório leva a troca de chave e não as palavras de
encomenda — quem a publicar dali tem de aplicar primeiro o script das encomendas (testado:
aplica limpo).

**Próximo passo:** revisor → publicar nas 3 → tu decides quando ligar.

## O que foi feito, com prova

| # | O quê | Onde | Prova (saída literal) | e2e_log |
|---|---|---|---|---|
| T1 | Edge `notify-tvde-driver` **v22 → v23** (24 trocas do A1 por cima do AR) | `n2/notify-tvde-driver-no-ar/index.ts` (cópia do que está no ar) | Antes: ar v22, md5 `d6d28e6a776c40a23810daceac478baa` (extraído do resultado do MCP, sem transcrever). Ensaio da transcrição = `eb45b7af…`. Depois: version 23, `verify_jwt` true, md5 no ar `eb45b7afa48365e14835cca4d03e232d` = ficheiro (cmp). Arranque: `POST {}` → `HTTP 400 {"ok":false,"error":"driverId and rideId are required"}`. Simulação Deno (base e Firebase falsos, 15 kinds): passageiros = v22; encomenda "📦 Nova encomenda!"; contraprova com a v22 → `FAILED`. | 4265, 4266, 4270, 4283 |
| T2a | Edge `notify-tvde-client` **v7 → v8** (avisos ao cliente; reservas) | `n2/notify-tvde-client/` + repo `supabase/functions/notify-tvde-client/index.ts` | Base = v7 do ar (`74b41b31`, já com a chave nova). Depois: version 8, index `523f0db0…`, `_shared/keys.ts` `0e1aa8f8…`, `_shared/chaves.ts` `21b57f55…` = locais (cmp). Arranque: `HTTP 401 unauthorized` (portão próprio). Simulação: passageiros v8 = v7 em 10 estados × com/sem estafeta + título próprio; contraprova v7 → `FAILED`. O varrimento das reservas (despacho, `c2eb13c9`) não foi tocado. | 4282 |
| T2b | Edge `tvde-recibo-viagem` **v5 → v6** (e-mail do recibo) | `n2/tvde-recibo-viagem/` + repo | Base = v5 do ar (= repo, `dc78c9d2`). Depois: version 6, index `daa6fcd5…`, shared iguais (cmp). Arranque: `HTTP 400 rideId_invalido`. Simulação: passageiros v6 = v5 byte a byte (servidor e cliente); encomenda sem viagem/motorista, números `4,00 € \| 1,00 € \| 5,00 € \| 5,00 €` iguais; contraprova v5 → `FAILED`. O recibo SQL (`_tvde_recibo`, `ee884c6d`) já tinha as palavras desde o A1 — **não houve SQL novo de recibo**. | 4286 |
| T2c | Histórico do cliente (título + etiqueta) | `tvde_rides_history_screen.dart`, `strings_en.dart`, `pt-en-25-encomendas.json` | Teste novo (abaixo). EN escrito à mão. | 4306 |
| T3a | **Mesmo acesso no servidor** — migração `20261021195814_encomendas_mesmo_acesso_do_bora_motorista` | `supabase/migrations/` (md5 ficheiro = banco `56d5743aad15ee64c9821b03181622bd`) | Prova em transacção desfeita (`n2/prova_n2_acesso_RESULT.json`): ANTES sem acesso → encomendas **passavam** (500/400/100; reserva 500/400/100; ida-e-volta 1760 855/855); DEPOIS → `no_tvde_access` nos 2 tipos e 3 caminhos; com acesso iguais ao cêntimo antes/depois; interruptor off → `encomendas_desligadas`; chamada antiga de 9 argumentos → passageiros 500/400/100. md5: `tvde_request_ride` e864711→**2273e348**, `tvde_schedule_ride` b3623e1b→**3ab9d0e5**, `tvde_schedule_roundtrip` ae675690→**590b1229**; sem as linhas do tipo = corpo de 20/10 (2a60a458/9ab25a91/15c6d850). ACL igual, anon não executa, pg_net 0. Reversão: `n2/reversao_N2_acesso.sql` (só com ordem tua). | 4277, 4278 |
| T3b | Mesmo acesso na app + painel | `client_home_screen.dart`, `tvde_entrada_screen.dart`, `admin_tvde_access_requests_screen.dart`; migração `20261021200849` (descrição do interruptor, só texto, md5 = banco `5911ab28176de2c60e1ab72a90733d91`) | Teste novo; SELECT da descrição; valor do interruptor `false`. | 4304 |
| T3c | Planos e foto | — | Nenhuma função de plano/preço lê `ride_kind` (6 funções, `le_ride_kind=false`); ecrã de pedir sem foto. Nada mudado. | 4305 |

**Dinheiro e despacho intactos (md5 no ar depois de tudo):** `tvde_calculate_fare` 4a1c99dd,
`tvde_finish_ride` 67eddac1, `compute_driver_settlement` 2510dea3, `tvde_cancel_ride` 8712208f,
`tvde_accept_ride` 88bf043c, `_tvde_exige_acesso` 98381d7a, `tvde_quote_roundtrip` 5f038a01,
`tvde_reservations_sweep` c2eb13c9, `tvde_preview_coverage` e73977b3, `_tvde_recibo` ee884c6d.
(`tvde_offer_to_next` 2c6fb898 e `tvde_dispatch_sweep` 737fc041 mudaram hoje pelo bloco A2 —
fila inteligente —, não por este bloco.)

## Qualidade (e2e_log 4307)

- RAM antes: 1405 / 1573 / 1732 / 2378 MB; nenhum `dart` a correr.
- `flutter analyze --no-pub` dos 5 ficheiros Dart → `No issues found! (ran in 22.8s)`.
- `flutter test --no-pub -j 1`: teste novo `encomendas_mesmo_acesso_e_historico_test` +
  `l10n_cobertura` + `tvde_cancel_quote` + `encomenda_sem_palavras_de_passageiro` +
  `ride_kind_textos` → `+67: All tests passed!`; `golden/grelha_categorias` +
  `motorista_ficha_legal` + `client_reservations_screen` → `+33: All tests passed!`.
  A suite inteira não foi corrida.
- `anti_trapaca.py --base e768931a (merge-base) --head HEAD` → `CLEAN`, 43 ficheiros, Δ testes +4.
  (Com `--base origin/…` dá falso "teste apagado": a origin andou 6 commits depois do meu ponto de partida.)
- `zonas_diff.py` → `Nenhuma zona protegida no diff`.
- **Origin andou** para `72ebbd1e`: 1 ficheiro em comum (`lib/l10n/strings_en.dart`),
  `git merge-tree` sem conflito → **rebase antes do push**.
- Ruído do `flutter pub get` (`analysis_options.yaml`, registos de plugins linux/macos/windows)
  **não foi adicionado**.

## Commits (ramo `encomendas-n2-21-10`, sem push)

- `4c66fa72` aviso ao estafeta "Nova encomenda" publicado (notify-tvde-driver v23)
- `5c198de4` mesma regra de acesso do Bora Motorista no servidor (migração 20261021195814)
- `239d6f7c` avisos ao cliente com palavras de entrega (notify-tvde-client v8)
- `d68ad328` e-mail do recibo com palavras de entrega (tvde-recibo-viagem v6)
- `2671fb99` mesma porta de acesso na app, histórico e painel (+ migração 20261021200849)
- (este relatório)

## Por fazer / avisos

1. **Ligar as encomendas**: decisão tua (questão legal TVDE com mercadorias). Nada liguei.
2. **Publicar a app nas 3** (só a parte Flutter deste ramo; o servidor já está no ar).
3. **Vigiar a 1.ª oferta real de passageiros** depois da v23: desde a publicação (19:48Z) não
   houve corridas (última 14:09Z), por isso ainda não há `push_enviado` real com a v23 —
   a simulação e o arranque estão provados, o real ainda não.
4. **Bloco G** (e2e_log 4283, reportado): `supabase/functions/notify-tvde-driver/index.ts` do
   repo **não foi substituído** (leva a troca de chave). No ar está a v23 (encomendas, sem a
   chave nova). Antes de o G publicar a partir do repo: `python
   a1/notify-tvde-driver/aplicar_encomendas_sobre_v22.py <repo index.ts> <saída>` (aplica
   limpo, "ok 24 trocas").
5. Ainda nascem sempre como passageiros: corridas de balcão e reservas criadas pelo admin (sem
   parâmetro de tipo) — fora deste bloco.
6. Quem não tem acesso e carrega em "Enviar Encomenda" (com o interruptor ligado) vê o ecrã de
   "pedir acesso" do Bora Motorista ("Nova categoria") — é a mesma porta, como pedido.

## PARA O DANILO

- **Acesso**: segui a tua ordem ("cópia exacta do TVDE") — encomendas só para quem tem acesso ao
  Bora Motorista. Se um dia quiseres encomendas abertas a todos, há reversão pronta
  (`n2/reversao_N2_acesso.sql`), mas isso abre o carro TVDE a toda a gente por essa porta.
- **Lei**: continua por confirmar com o contabilista/IMT se os carros TVDE podem levar
  mercadorias. Por isso o interruptor fica desligado.
