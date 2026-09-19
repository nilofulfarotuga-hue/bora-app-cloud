---
id: central-corridas-balcao-2026-09-18
tipo: relatorio
origem: Claude Code (motor Sonnet 5, sessão headless — MOTOR pedido era glm-5.2/OpenCode, mas
  a "porta única" (regra global do Danilo, 16/09) diz que o Claude Code executa e reparte por
  dentro; não abri sessão OpenCode separada, executei tudo aqui)
data: 2026-09-18
zona: verde (Flutter + admin) — nada de dispatch_engine/pricing/tvde_finish_ride tocado
estado: parcial — Blocos 1 e a parte possível dos Blocos 2/3 feitos; Bloco 3 tem 2 itens
  bloqueados no servidor (documentados abaixo); prova visual em emulador NÃO foi feita
---

# Corridas de Balcão — parte Flutter (missão `central-corridas-balcao-2026-09-18`)

## Pré-voo (Bloco 0)

- Branch confirmada: `autonomous-night-2026-04-29` (era a pedida). Árvore tinha dezenas de
  ficheiros modificados/não rastreados de OUTRAS sessões (provas, backups, inbox) — não toquei
  em nenhum, não fiz `git add -A`; o commit desta missão só leva os 12 ficheiros que eu editei.
- RAM disponível ao longo da sessão: 1780 MB → 2349 MB → 2880 MB (medido antes de cada
  `flutter analyze`/`flutter test`) — sempre acima do portão de 800 MB, sem precisar de exceção.
- Confirmado por SQL direto no Supabase (`ojykpzwqrtusfeakzrna`) ANTES de codificar: as colunas
  `tvde_rides.source` / `agreed_fare_cents` / `agreed_driver_earn_cents`, a tabela
  `tvde_client_places`, a coluna `users.is_counter_client` e a RPC
  `admin_tvde_create_counter_ride` já existiam e estavam corretas (li o `pg_get_functiondef`
  inteiro da RPC antes de a usar). Não escrevi SQL nenhum — só SELECT de investigação.

## O que ficou feito

### Bloco 1 — lado do motorista (PT-PT) — COMPLETO

Ficheiros: `lib/models/tvde_ride.dart`, `lib/models/tvde_fare_view.dart`,
`lib/widgets/tvde/tvde_counter_ride_badge.dart` (novo),
`lib/screens/driver/tvde/tvde_offer_screen.dart`,
`lib/screens/driver/tvde/tvde_ride_active_screen.dart`,
`lib/screens/driver/tvde/tvde_driver_rate_screen.dart`.

- `TvdeRide` ganhou `source`, `agreedFareCents`, `agreedDriverEarnCents` + dois getters:
  `isCounterRide` e `netDriverEarnCents` (o combinado manda sempre que existe).
- **Regra de ouro**: troquei as 6 leituras diretas de `driverEarnCents` nos 6 pontos onde o
  motorista vê o "ganho em grande" (oferta, painel da corrida ativa, cartão da próxima em fila,
  banner da oferta em fila, snackbar de fim em back-to-back, lembrete de cobrança) por
  `netDriverEarnCents` — encontrei 2 destes 6 pontos só ao correr os testes (não estavam no
  mapeamento inicial da exploração): a linha 1409 (snackbar de back-to-back) e a 1440 (lembrete
  de cobrança) de `tvde_ride_active_screen.dart`.
- `TvdeFareView.of()` passou a checar `agreedFareCents` PRIMEIRO — antes do pacote ida-e-volta,
  do plano e do `final_fare_cents` — para nunca recalcular o valor combinado.
- Selo "Cliente sem aplicação — liga-lhe" (`TvdeCounterRideBadge`, cor `AppColors.info`, azul —
  **nunca laranja**: a oferta e a corrida ativa já estão no limiar `[!]` de 2 usos de
  `AppColors.accent` pela regra "1 laranja/ecrã", medi com o `audit-orange-rule` antes de decidir
  a cor) aparece desde a oferta até ao fim da corrida, sempre dentro de
  `if (ride.isCounterRide)`.
- Botão de ligar: já existia (`_callPassenger`, `tel:`) e já lê o telefone certo — a RPC
  `tvde_ride_passenger_card` (que o motorista usa) lê de `public.users`, não de `auth.users`, por
  isso o cliente de balcão (que não tem conta) aparece certinho. **Não precisei mexer aqui.**
- Nada bloqueia à espera do cliente: confirmei que `tvde_driver_rate_screen.dart` não lê
  `ratedByClient` nem nada do género (teste de regressão trava isto).

### Bloco 2 — Admin "Corridas de Balcão" (PT-BR) — COMPLETO

Ficheiro novo: `lib/screens/admin/admin_tvde_balcao_screen.dart`.

- Criar corrida (RPC `admin_tvde_create_counter_ride`, nunca INSERT direto): telefone com busca
  de cliente existente em tempo real (evita duplicar — o aviso "cliente existente" cumpre o item
  4 do Bloco 3 também, já que a criação de cliente real só acontece aqui), moradas guardadas do
  cliente como atalho (chip), `AddressAutocompleteField` para morada nova, valores de
  cobrar/ganhar pré-preenchidos das definições da plataforma (editável).
- Ao vivo + histórico, com filtro automático a `source='balcao'` (ver nota de gap abaixo).
- Reatribuir (RPC `admin_tvde_reassign_ride`, mesma RPC do ecrã geral de Corridas) e Cancelar
  (RPC `tvde_cancel_ride` com `p_actor='cliente'` — decisão: representa "o cliente pediu para
  cancelar", que é a fee-logic certa para um admin a cancelar em nome de quem ligou; `p_actor`
  só aceita `cliente|motorista|no_show`, nunca `'admin'` — o ator real fica registado sozinho
  porque a RPC detecta `is_admin()` e grava `'admin'` no evento de qualquer forma).
- O admin não precisa de saber o estado por dentro — os botões só aparecem quando o estado
  permite (mesma lista de estados "reatribuível"/"cancelável" da corrida geral).

**Gap real encontrado (documentado, NÃO corrigido — é SQL, fora do meu âmbito):**
`admin_tvde_rides_list` (RPC já existente) faz `LEFT JOIN auth.users` para `client_name`/
`client_phone`, e NÃO devolve `source`/`agreed_fare_cents`/`agreed_driver_earn_cents`. Um
cliente de balcão nunca tem conta em `auth.users` (não faz login) — por isso essa RPC sozinha
não consegue nem filtrar corridas de balcão nem mostrar o nome/telefone delas. Contornei do lado
Flutter com DUAS leituras extra, diretas e só-leitura, autorizadas pela mesma RLS
(`is_admin()` em `tvde_rides_select` e `users_select_admin`): uma para `source`/`agreed_*`
(junta por `id`), outra para nome/telefone em `public.users` quando a RPC vem vazia. Funciona,
mas é mais lento que se a RPC soubesse disto de raiz. Proposta para outra sessão (MCP/SQL):
estender `admin_tvde_rides_list` para devolver `source`/`agreed_*` e trocar o join de
`auth.users` por `public.users` (o mesmo que já corrigi que `tvde_ride_passenger_card` já faz
certo).

### Bloco 3 — Admin "Agenda de Clientes de Balcão" (PT-BR) — PARCIAL

Ficheiro novo: `lib/screens/admin/admin_tvde_balcao_agenda_screen.dart`.

- **Item 1 (lista clientes) — só LEITURA, funcional.** Criar/editar/apagar cliente **não dá** a
  partir daqui: a RLS de `public.users` só tem `INSERT`/`UPDATE` para o dono
  (`auth.uid() = id`) — não há política de admin para escrever nessa tabela, e a única RPC que
  cria um cliente de balcão (`admin_tvde_create_counter_ride`) fá-lo como EFEITO SECUNDÁRIO de
  criar uma corrida (não dá para chamar só para registar um contacto sem criar uma corrida
  fantasma). O botão "Novo cliente" explica isto e manda para "Corridas de Balcão" (o cliente
  nasce sozinho na primeira corrida). **Proposta para outra sessão:** RPCs
  `admin_create_counter_client(p_name, p_phone)` / `admin_update_counter_client(...)` /
  `admin_delete_counter_client(...)`, `SECURITY DEFINER` + `is_admin()`, no mesmo padrão de
  `admin_tvde_create_counter_ride`.
- **Item 2 (moradas por apelido) — COMPLETO.** `tvde_client_places` já tem política de admin
  total (`tvde_client_places_admin_all`, `is_admin()`) — CRUD a sério, direto na tabela (criar,
  editar, apagar, dentro do cartão de cada cliente).
- **Item 3 (importar por print/OCR) — BLOQUEADO, não implementado.** Precisa de uma Edge
  Function nova (ou adaptar a `ocr-receipt` dos Favores) que aceite a foto do contacto
  diretamente e devolva `{name, phone}` pelo Gemini Vision — a `ocr-receipt` de hoje só lê um
  talão já guardado numa `order_receipts_v2` existente, está acoplada a uma encomenda. Deploy de
  Edge Function não é meu (fora do âmbito desta missão). O botão no ecrã explica isto ao Danilo
  em vez de fingir que funciona.
- **Item 4 (avisar duplicado por telefone) — coberto no fluxo certo.** Fica no diálogo "Nova
  corrida" (Bloco 2), que é onde a RPC de fato cria/reaproveita o cliente — mostra "cliente
  existente: NOME" assim que o telefone bate com alguém.
- **Item 5 (definições editáveis) — parcial, por decisão de segurança, não de código.** As 3
  definições (`tvde_balcao_default_fare_cents`, `tvde_balcao_default_driver_cents`,
  `tvde_fila_justa_balcao_enabled`) já existem no servidor com descrição PT-BR e JÁ aparecem no
  ecrã de definições (a lista mostra tudo, sempre). Só liguei o lápis (editável) na
  `tvde_fila_justa_balcao_enabled` (é comportamento — quem se chama primeiro — não dinheiro). As
  duas em cêntimos ficaram só-leitura: são o preço/ganho por omissão de um produto novo, a mesma
  categoria de `appointment_booking_fee_cents`/`tvde_roundtrip_discount_pct` no mesmo ficheiro —
  mas essas só foram destrancadas com uma decisão explícita e já registada do Danilo; esta ainda
  não tem. Ficou o comentário no código a apontar para lá.
  ⚠️ **PARA O DANILO:** se quiseres editar `tvde_balcao_default_fare_cents`/
  `_driver_cents` direto no painel (sem precisar de mim), diz "desbloqueia os preços do balcão
  nas definições" — é uma linha a acrescentar na whitelist de
  `admin_platform_settings_screen.dart`.

### Bloco 4 — Provas e fecho

- ✅ `flutter analyze --no-fatal-infos`: **0 erros** no projeto inteiro (só avisos `info`
  pré-existentes, nenhum nos ficheiros que toquei além de estilo menor: `RadioListTile`
  deprecado — o mesmo padrão já usado no ecrã geral de Corridas, copiado de propósito para não
  duplicar UI).
- ✅ `flutter test` — toda a suite TVDE (14 ficheiros, 165 testes): **165/165 verdes**. Dois
  ficheiros novos/ampliados:
  - `test/tvde_fare_view_test.dart` — 4 casos novos: valor combinado manda mesmo com
    `est`/`final`/paradas diferentes; nunca é "estimativa" (`approx=false`); dinheiro (regra do
    balcão); corrida normal não é afetada.
  - `test/tvde_corrida_balcao_test.dart` (novo) — parsing do modelo + `netDriverEarnCents` +
    regressão mecânica sobre o código-fonte dos 3 ecrãs (garante que ninguém volta a ler
    `driverEarnCents` cru, que o selo está sempre dentro de `if (...isCounterRide)`, e que o
    selo não usa laranja). Foi este teste que apanhou os 2 pontos que eu tinha esquecido no
    `tvde_ride_active_screen.dart` (linhas 1409/1440) — ficaram corrigidos.
  - `python .claude/juiz/anti_trapaca.py --base HEAD`: **CLEAN** (18 ficheiros no diff contra
    HEAD — inclui ruído de outras sessões já na árvore; os meus são 12; 0 trapaça: sem
    asserção trivial, sem teste desativado, sem valor esperado trocado).
- ❌ **Prova visual em emulador — NÃO FEITA, dito claramente.** O PC é um Celeron N4500 de 4 GB
  (regra do portão de RAM); um emulador Android AVD é ordens de grandeza mais pesado que
  `flutter analyze`/`test` e tentei evitar o risco de OOM a meio de uma missão já longa, sem
  device físico ligado por USB nesta sessão. Cobri a correção com testes (analyze limpo + 165
  testes verdes, incluindo regressão sobre o texto-fonte dos ecrãs) em vez de screenshot. Se
  quiseres a prova visual mesmo, digo qual comando correr com o emulador ligado (ou uso o Chrome
  headless para as duas telas do admin, que não dependem de Google Maps para renderizar).
- ✅ Ficheiros tocados (só estes, nenhum outro — a árvore tinha dezenas de outras mudanças de
  outras sessões que NÃO entraram neste commit):
  - `lib/models/tvde_ride.dart`, `lib/models/tvde_fare_view.dart`
  - `lib/widgets/tvde/tvde_counter_ride_badge.dart` (novo)
  - `lib/screens/driver/tvde/tvde_offer_screen.dart`
  - `lib/screens/driver/tvde/tvde_ride_active_screen.dart`
  - `lib/screens/driver/tvde/tvde_driver_rate_screen.dart`
  - `lib/screens/admin/admin_tvde_balcao_screen.dart` (novo)
  - `lib/screens/admin/admin_tvde_balcao_agenda_screen.dart` (novo)
  - `lib/screens/admin/admin_menu_registry.dart`, `lib/screens/admin/admin_platform_settings_screen.dart`
  - `test/tvde_fare_view_test.dart`, `test/tvde_corrida_balcao_test.dart` (novo)

## Achados fora do âmbito (reportados, não corrigidos)

1. `admin_tvde_rides_list` não devolve `source`/`agreed_*` e junta `client_name`/`client_phone`
   por `auth.users` (cliente de balcão nunca tem conta lá) — ver detalhe no Bloco 2 acima.
2. Falta RPC de admin para criar/editar/apagar um "cliente de balcão" sem passar por criar uma
   corrida — ver detalhe no Bloco 3 item 1.
3. Falta Edge Function para OCR de contacto solto (a `ocr-receipt` está acoplada a uma
   encomenda) — ver Bloco 3 item 3.

## PARA O DANILO

⚠️ Já pronto a usar sem precisares de nada: as duas telas novas estão no menu "Bora Motorista"
→ "Corridas de Balcão" e "Agenda de Clientes de Balcão". Cria uma corrida de teste em DINHEIRO
(nunca cartão) e confirma que o motorista vê o selo azul "Cliente sem aplicação" e o ganho certo
em grande — eu não consegui testar isso ao vivo no telemóvel/emulador nesta sessão (ver Bloco 4).

Três coisas que ficam à tua decisão (nenhuma é urgente):
1. Queres que eu (ou outra sessão) escreva as 3 RPCs que faltam no servidor (client CRUD +
   estender `admin_tvde_rides_list`)? É trabalho de SQL/MCP, fora do que esta missão me deixou
   tocar.
2. Queres desbloquear `tvde_balcao_default_fare_cents`/`_driver_cents` para edição direta no
   painel (ver Bloco 3 item 5)?
3. Vale a pena adaptar a `ocr-receipt` dos Favores para aceitar foto solta de contacto (Bloco 3
   item 3), ou preferes que a Agenda continue só a nascer via "Corridas de Balcão"?
