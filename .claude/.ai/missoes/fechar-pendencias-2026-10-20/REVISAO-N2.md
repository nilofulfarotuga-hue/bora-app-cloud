# REVISÃO N2 — Encomendas (aviso, palavras, mesmo acesso)

> 21/10/2026, noite · revisor de contexto limpo (maker/checker) · não fiz este trabalho, tentei derrubá-lo.
> Alvo: ramo `encomendas-n2-21-10` (worktree `C:\BoraLocal\wt-encomendas-n2-21-10`), 7 commits por cima de
> `e768931a` (4c66fa72, 5c198de4, 239d6f7c, d68ad328, 2671fb99, 85da5901, f55a6d86).
> Só li, corri verificações e escrevi este ficheiro. Nada de commit no ramo do autor, push, migração ou deploy.
> O ramo temporário `revisor-n2-tmp` (e a pasta `C:\BoraLocal\wt-revisor-n2-tmp`) foi apagado no fim.

## Em palavras simples

O trabalho aguenta. A parte do servidor que já está no ar é igual ao que o autor guardou, ao byte. A regra
nova de acesso só mudou uma linha em cada uma das 3 funções de pedir corrida, e os passageiros recebem
exactamente o mesmo de antes (provado em transacção desfeita, com e sem acesso). O interruptor das
encomendas continua desligado. A parte da app junta-se à versão mais nova do ramo principal sem perder
frase de ninguém, compila sem erros novos e os 1585 testes passam todos. Há avisos (abaixo), nenhum
bloqueia.

---

## 1. O que viaja e a junção com o ramo principal

- `git fetch -q origin` → rc=0. Origin está em `72ebbd1e`; ponto de partida comum = `e768931a` (confirmado com `git merge-base`).
- `git diff e768931a..HEAD --stat` → **44 ficheiros, 5817 linhas a mais, 19 a menos**. Fora de `.claude/`
  só 11 ficheiros: `lib/l10n/strings_en.dart`, `admin_tvde_access_requests_screen.dart`,
  `tvde_entrada_screen.dart`, `tvde_rides_history_screen.dart`, `client_home_screen.dart`,
  `supabase/functions/notify-tvde-client/index.ts`, `supabase/functions/tvde-recibo-viagem/index.ts`,
  as 2 migrações, `test/encomendas_mesmo_acesso_e_historico_test.dart`,
  `tool/l10n/traducoes/pt-en-25-encomendas.json`. Nenhum commit tem `[skip ci]`.
- Li o código todo: na app, cada mudança é só para encomendas (título do histórico só muda se houver
  encomenda na lista; ícone e etiqueta só na linha da encomenda; o ladrilho "Enviar Encomenda" com o
  interruptor ligado passa a abrir a mesma porta de acesso). Todos os caminhos de passageiros chamam
  `TvdeEntradaScreen()` sem tipo → `RideKind.passageiros` (por omissão, como antes).
- **Junção (rebase) feita num ramo meu**, numa pasta à parte, sem tocar no ramo do autor:
  `Successfully rebased and updated refs/heads/revisor-n2-tmp` (7/7, sem conflito).
  - Ficheiro em comum `lib/l10n/strings_en.dart`: junção contra origin = **só as 3 linhas do autor**
    (`'As minhas corridas e encomendas': 'My rides and parcels'`); junção contra o ramo do autor = **só as
    frases da origin** ("separador Reservas", "It is kept in the Reservas tab"). Ninguém perdeu frase.
  - O diff completo (origin → junção) é **igual linha a linha** ao diff do autor (e768931a → HEAD):
    `SAME_STAT`, `diff` sem diferenças (rc=0).
  - O ramo do autor ficou onde estava: `f55a6d86`.

## 2. Memória, analisador e testes (na versão já juntada com a origin)

- RAM antes: **1746 MB** disponíveis; `dart-like processes: 0`. Antes do pub get 1539 MB; antes dos testes 1896 MB.
  (Portão pesado de 800 MB cumprido em todas as medições.)
- `flutter analyze --no-pub` (projeto inteiro): **0 erros**, 6 avisos, 257 infos = **263 issues**.
  O mesmo comando na origin `72ebbd1e` sozinha: **263 issues**. Nenhum aviso/info nos 6 ficheiros Dart
  mexidos por este trabalho (`grep` → nenhum). Os 6 avisos são velhos (driver_map_screen, profile_screen,
  chat_bubble_button, login_cliente_test, appbar_paint_probe_test). **Nada de novo.**
- `flutter test --no-pub -j 1` dos 18 ficheiros ligados ao que mudou (o teste novo, ride_kind_textos,
  encomenda_sem_palavras_de_passageiro, l10n_cobertura, tvde_cancel_quote, golden/grelha_categorias,
  golden/ingles_sem_estouro, motorista_ficha_legal, admin_geral_ronda_0410, …) → **`+213: All tests passed!`**
- `flutter test --no-pub -j 1 test/` (suite inteira) → **`+1585: All tests passed!`**, rc=0, **0 falhados**.

## 3. Juiz (chão anti-trapaça e zonas)

- `anti_trapaca.py --base e768931a --head HEAD` → **✅ CLEAN**, 44 ficheiros, Δ casos de teste **+4**.
  `--base e768931a` (sem head, como pedido) → também CLEAN, +4.
- O falso "teste apagado": `--base origin/… --head HEAD` (ramo do autor) → REJEITA `TEST_FILE_DELETED`
  `test/hora_de_lisboa_reservas_test.dart` e `test/separador_reservas_rotulo_test.dart`. **Não é batota**:
  esses 2 testes nasceram na origin depois do ponto de partida do autor; o ramo dele simplesmente ainda não
  os tem. Prova: na versão juntada, `--base origin/… --head HEAD` → **✅ CLEAN, +4**.
- `zonas_diff.py` (nas duas comparações) → **✅ CLEAN — Nenhuma zona protegida no diff.**

## 4. As 2 migrações: ficheiro = banco

| Migração | md5 do ficheiro (git) | md5 no banco (`statements`) |
|---|---|---|
| `20261021195814_encomendas_mesmo_acesso_do_bora_motorista` | `56d5743aad15ee64c9821b03181622bd` | `56d5743aad15ee64c9821b03181622bd` |
| `20261021200849_encomendas_descricao_do_interruptor_com_acesso` | `5911ab28176de2c60e1ab72a90733d91` | `5911ab28176de2c60e1ab72a90733d91` |

No banco cada uma tem 1 statement; o md5 dá igual com `array_to_string(statements, E';\n')`, com `E'\n'` e
com `statements[1]`. As únicas migrações deste bloco hoje são estas duas (lista de `schema_migrations` desde 20261021).

## 5. Funções no ar (Edge)

md5 tirado da resposta do `get_edge_function` (lida do registo da sessão por script, sem transcrever à mão):

| Função | Versão | verify_jwt | md5 no ar (index.ts) | Cópia do autor | Repo |
|---|---|---|---|---|---|
| notify-tvde-driver | 23 | true (v22 era true, e2e 4265) | `eb45b7afa48365e14835cca4d03e232d` | igual (`notify-tvde-driver-no-ar/index.ts` e `sim-notify/v23_nova.ts`) | **diferente** (ver aviso A) |
| notify-tvde-client | 8 | true (era true desde 16/10, e2e 3781) | `523f0db0df6d78b5aa1a42d3c347bb88` | igual (`v8/index.ts`; `_shared/keys.ts` 0e1aa8f8 e `chaves.ts` 21b57f55 iguais) | só 2 linhas de comentário diferentes (traços), já assim antes |
| tvde-recibo-viagem | 6 | true (v5 era true, e2e 3763) | `daa6fcd5ce73410efec58eb0a0d442eb` | igual (index, chaves a7161114, keys 61c62d7f) | **igual** (index e _shared) |

- **A notify-tvde-driver no ar NÃO leva a troca de chave do Bloco G**: tem 1 só ficheiro (`index.ts`, sem
  `_shared`), sem `secretKey`, sem `keys.ts`, sem `SUPABASE_SECRET_KEYS`, sem `exigirCallerOk` — usa
  `SUPABASE_SERVICE_ROLE_KEY` como a v22. A cópia da v22 guardada pelo autor dá `d6d28e6a…` (o md5 "antes"
  que ele registou).
- Diff v22 → v23 lido linha a linha: só acrescenta `ride_kind` às leituras e escolhe a frase de encomenda
  quando `ride_kind = 'encomendas'`; todas as frases de passageiros ficam iguais.
- Corri as simulações do autor (Deno, base e Firebase falsos): driver `ok | 2 passed`, cliente `ok | 2 passed`,
  recibo `ok | 2 passed`; contraprovas com as versões antigas → `FAILED | 1 passed | 1 failed` nas 3
  (a prova prova). A coluna `tvde_rides.ride_kind` existe, NOT NULL, por omissão `'passageiros'`.

## 6. Dinheiro e despacho intactos

- As 3 funções de pedir, no ar: `tvde_request_ride` **2273e348**, `tvde_schedule_ride` **3ab9d0e5**,
  `tvde_schedule_roundtrip` **590b1229**. Repondo SÓ a linha do portão
  (`PERFORM public._tvde_exige_acesso(v_uid);` → `IF v_ride_kind = 'passageiros' THEN … END IF;`) o md5 dá
  **exactamente o de antes**: e864711391be…, b3623e1b87a1…, ae675690c6b3…. Ou seja, **só a verificação de
  acesso mudou**; a linha nova aparece 1 vez em cada. A própria migração abortava se o "antes" não fosse este.
  ACL igual (`postgres, authenticated, service_role`), SECURITY DEFINER, `anon` não executa.
- **Prova minha em transacção desfeita** (DO … `RAISE EXCEPTION 'RESULT %'`; demo@bora.app sem acesso só lá
  dentro; interruptor NÃO mexido). Fase "depois" = funções no ar; fase "antes" = linha antiga reposta lá
  dentro (md5 confirmado). Resultado literal (passageiros, dinheiro, 3 km / reserva 5 km / ida-e-volta 10 km):
  - **com acesso**, antes = depois, nas 2 formas de chamar (sem tipo e `'passageiros'`):
    na hora `["passageiros","solicitada",500,400,100,"cash"]`; reserva `["passageiros","agendada",500,400,100]`;
    ida-e-volta `["passageiros",1760,1100,855,0,855,220,0]`.
  - **sem acesso**, antes = depois: `ERRO no_tvde_access` nos 3 caminhos e nas 2 formas.
  - encomendas com o interruptor como está (false), antes = depois: `ERRO encomendas_desligadas` para os dois clientes.
  - O comportamento de passageiros **não mudou para ninguém**.
- Outras funções de dinheiro/despacho no ar (iguais às que o autor listou): `tvde_calculate_fare` 4a1c99dd,
  `tvde_finish_ride` 67eddac1, `compute_driver_settlement` 2510dea3, `tvde_cancel_ride` 8712208f,
  `tvde_accept_ride` 88bf043c, `_tvde_exige_acesso` 98381d7a, `tvde_quote_roundtrip` 5f038a01,
  `tvde_reservations_sweep` c2eb13c9, `tvde_preview_coverage` e73977b3, `_tvde_recibo` ee884c6d.
  A migração deste bloco não toca em nenhuma delas.
- `platform_settings.tvde_encomendas_enabled` = **false** (updated_at 08:32Z, de manhã — antes do N2); só a
  descrição mudou (texto novo lido de volta).

## 7. Textos

- App (PT-PT): "As minhas corridas e encomendas", "📦 Encomenda" — só aparecem quando há encomenda. O ecrã de
  acesso que as encomendas passam a usar é neutro ("Nova categoria", "Há uma categoria nova à tua espera") —
  não fala de passageiros.
- Painel (PT-BR): "Este acesso vale para o Bora Motorista e também para as Encomendas (mesmo motor): quem não
  tem acesso não pede nenhum dos dois." e a descrição nova do interruptor. Sem `.tr` (o painel não traduz).
- Nenhuma frase de passageiro mudou: nem na app, nem nos 3 avisos/e-mail (diffs e simulações acima).
- Inglês escrito à mão para a única frase nova com `.tr`: `strings_en.dart` e `pt-en-25-encomendas.json`;
  `l10n_cobertura_test` passou.

## 8. Segurança

- Nenhuma função nova no banco (as 2 migrações só substituem 3 funções existentes e mudam um texto);
  `has_function_privilege('anon', …)` = **false** nas 3.
- Segredos nas 5817 linhas acrescentadas: `sk_live` 0, `sk_test` 0, `eyJ…` 0, `AIza…` 0, `ghp_…` 0,
  `github_pat_` 0, `re_` + 16 caracteres 0, `sb_secret_…` 0, `sb_publishable_…` 0, `whsec_` 0.
  As 5 linhas com `-----BEGIN PRIVATE KEY-----` são o `.replace(/-----BEGIN PRIVATE KEY-----/g, '')` do
  código do token Google (não é chave). `service_role` aparece só como nome de papel no código/comentários.
  Nas simulações só há valores falsos (`re_chave_falsa`, `chave-falsa`).

## Avisos (não bloqueiam)

- **A. Repo ≠ ar na notify-tvde-driver.** `supabase/functions/notify-tvde-driver/index.ts` do repo leva a
  troca de chave do Bloco G e não as palavras de encomenda; no ar está a v23 (com palavras, sem chave nova).
  O autor reportou (e2e 4283) e deixou o script para juntar. Quem publicar esta função a partir do repo antes
  disso apaga as palavras de encomenda (sem efeito enquanto o interruptor estiver desligado).
- **B. Ainda sem prova real da v23 com passageiros**: desde a publicação (19:48Z) não houve corridas
  (`corridas_novas = 0`, última 14:09Z). Está provado por simulação e arranque; falta a 1.ª oferta real.
- **C. Antigo, não deste bloco**: a notify-tvde-driver no ar (v22 e v23) só tem o `verify_jwt` da
  plataforma, sem portão próprio — é o que o Bloco G vem fechar. `tvde_calculate_fare` e
  `tvde_quote_roundtrip` são chamáveis por `anon` (não foram tocadas aqui).
- **D. Pequeno**: na oferta a passageiros o aviso leva mais uma chave escondida (`rideKind: 'passageiros'`);
  não é frase, a app velha ignora-a. Numa encomenda, "⏰ Reserva daqui a uma hora" e "🚗 A tua reserva começa
  em 10 minutos" ficam como estão (só passageiros contam para esta revisão).
- **E. Na minha prova desfeita** a fila do pg_net contou +1 entre o início e o fim; a transacção foi toda
  desfeita (nada dela pode sair) e `users` não tem gatilho que chame a rede — deve ser um pedido de outra
  sessão no mesmo intervalo.

VEREDICTO: SIM
