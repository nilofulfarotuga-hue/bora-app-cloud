# Missão limpeza-longe-e-equipa-2026-11-19 — registo

Fluxo no e2e_log: `limpeza-longe-equipa`. Sessão: Claude Code na nuvem (PC desligado).
Por ordem do Danilo (19/11), o Supabase só se usa no mínimo: o registo dos passos fica aqui
e vai 1 linha ao e2e_log no fim de cada bloco.

## Arranque
- e2e_log `arranque/arrancou` gravado no início.
- Adendo do Danilo 16:35: a distância é por ESTRADA (cleaning_road_km + grelha de 811
  pontos), máximo 32 km de estrada, a app não calcula distâncias — só manda as coordenadas
  e mostra `travel_distance_km` como "X km de estrada"; a mensagem usa sempre o
  `max_distance_km` do servidor.

## Bloco A — a app do cliente aceita a morada longe e mostra a taxa

O que travava (lido no código, 19/11):
- Nada no fluxo da limpeza recusava uma morada fora da Guarda. Não há validação por cidade,
  código postal 6300 nem uso de `delivery_max_distance_km` no assistente da limpeza.
- O autocomplete não trava: `kGuardaStrictBounds = false` (`lib/config/maps_config.dart:22`);
  o viés da Guarda (`location`+`radius` 25 km, `bounds` ~30 km no geocoding) é só
  preferência, e `escolherMelhorNaGuarda` (`lib/services/place_autocomplete_service.dart:94`)
  devolve o melhor resultado mesmo fora dos 30 km.
- O erro real era o que a Claude.ai achou: em
  `lib/screens/client/cleaning/cleaning_wizard_screen.dart` (antes linhas 219-226 e 243-258)
  as coordenadas mandadas a `cleaning_list_available_cleaners` e a `create_cleaning_booking`
  eram `cart.deliveryLocation` (a morada de ENTREGAS do carrinho), não a morada da limpeza.
  E o preço vinha de `cleaning_quote` (sem morada), por isso a taxa nunca aparecia antes de
  pagar.

O que mudou:
- `lib/screens/client/cleaning/cleaning_wizard_screen.dart`
  - Campo "Rua e número" passou a `AddressAutocompleteField` (sugestões como no TVDE). Sugestão
    tocada → coordenadas dessa casa + cidade e código postal preenchidos + preço recalculado.
  - Morada escrita à mão → ao carregar em Continuar procura as coordenadas com
    "rua, código postal cidade" (`procurarMoradaEscrita`, a mesma do TVDE/Favores). Se não
    achar, segue sem coordenadas (taxa 0 no servidor) — nunca trava.
  - Mexer na rua, cidade ou código postal apaga as coordenadas antigas.
  - As coordenadas do carrinho só se usam enquanto a morada pré-preenchida for a do carrinho;
    "Marcar de novo" usa as coordenadas da limpeza antiga.
  - Preço com morada vem de `cleaning_quote_at` (via `CleaningStore.quote`). Resumo mostra
    "Taxa de deslocação (28,6 km de estrada) + €29,00" e o total com ela. Menos de 10 km:
    sem linha. O cartão do preço diz "inclui €X de deslocação".
  - Fora da área (`out_of_area=true`): aviso vermelho "Ainda não fazemos limpezas a mais de
    32 km da Guarda." (número do servidor), não passa ao passo de pagar e o botão de
    reservar fica desligado. O erro `fora_da_area_limpeza` do servidor aparece com a mesma
    frase, nunca o texto técnico.
  - Só a resposta do pedido de preço mais recente conta (morada a mudar com pedido a caminho).
- `lib/stores/cleaning_store.dart` — `quote()` recebe `lat/lng` e chama `cleaning_quote_at`.
  Sem morada, se falhar, cai na `cleaning_quote` antiga (mesmo resultado). Com morada não cai
  (seria mostrar menos do que se cobra).
- `lib/models/cleaning_models.dart` — `CleaningQuote` com `travelFeeCents`,
  `travelDistanceKm`, `outOfArea`, `maxDistanceKm`; `CleaningBooking` com `travelFeeCents`,
  `travelDistanceKm`, `lat`, `lng`; textos `travelFeeLabel` e `outOfAreaMessage`.
- `lib/screens/client/cleaning/cleaning_tracking_screen.dart` — detalhe da reserva (é também
  o recibo do cliente na app; a limpeza não tem PDF próprio) mostra a linha da taxa.
- Migrações aplicadas pela Claude.ai hoje copiadas fielmente para `supabase/migrations/`
  (20261119161344, 20261119161433, 20261119163735, 20261119163857, 20261119163927).
  Nota: os km de estrada da grelha (`road_km`) são DADOS preenchidos em produção pela Google;
  não estão nos ficheiros.

Provas (sem Supabase, por ordem do Danilo — testes de ecrã com o servidor de mentira a
devolver o que a `cleaning_quote_at` devolveu em produção):
- `test/limpeza_taxa_deslocacao_wizard_test.dart`
  - Celorico (40.6363, -7.3929), T4+ Standard, carrinho com morada na Guarda: o preço, a
    lista de profissionais e a reserva vão com as coordenadas de Celorico; ecrã mostra
    "Taxa de deslocação (28,6 km de estrada)", "+ €29,00" e total €99,00.
  - Guarda centro: sem linha da taxa, total €70,00.
  - Pinhel: "Ainda não fazemos limpezas a mais de 32 km da Guarda." e não chega ao pagamento.
  - A reserva lê `travel_fee_cents`/`travel_distance_km` e uma reserva antiga fica com taxa 0.
- `flutter analyze`: 0 erros. Juiz anti-trapaça: limpo (+4 casos de teste).
- Falta (precisa de Supabase/telemóvel): reserva real de teste `is_test_order=true` em
  Celorico a gravar `total_cents=9900, travel_fee_cents=2900`, e confirmar o ecrã nas 3 lojas
  depois do CI.

## Reportes (não corrigidos, fora do scope do bloco)
- `create_cleaning_booking` (servidor): o aviso por push diz "A tua morada fica a X km do
  centro da Guarda" — desde o adendo os km são de ESTRADA; devia dizer "X km de estrada".
- Por verificar no Bloco B (ainda não li o corpo): se `cleaning_list_available_cleaners` e
  `_cleaning_next_offer` comparam o raio da profissional em linha reta, enquanto a taxa
  agora é por estrada.

## Bloco A — envio
- Enviado para a branch a 19/11: commits `ef8d022` e `3a2f627`. CI: Android run 602, iOS run 377,
  web a seguir (os três disparam com o envio). e2e_log `bloco A enviado` (id 11585).

## Bloco B — equipa de várias profissionais

Desenho escolhido (o recomendado, confirmado ao ler o servidor): UMA reserva por profissional,
ligadas por `team_group_id`.
- Vaga 1 (principal) guarda em `total_cents` o TOTAL DA EQUIPA: é o que o cliente paga uma vez.
  Assim o cartão/MB Way (`cleaning-checkout`), o webhook (`confirm_cleaning_payment_webhook`,
  confere o valor com `total_cents`), o estorno e a taxa de cancelamento funcionam sem mexer em
  nenhuma função da Stripe.
- Vagas 2..N (irmãs): `total_cents = 0`. Todas as vagas guardam a parte da sua profissional:
  `share_cents` (trabalho + a sua deslocação + parte igual dos produtos), `cleaner_earnings_cents`
  e `bora_fee_cents` (15% só do trabalho). O acerto semanal (`compute_cleaner_weekly_settlement`)
  já soma ganho/taxa por linha e por meio de pagamento: não precisou de mudar.
- Colunas novas: `team_group_id`, `team_size`, `team_slot`, `team_total_cents`, `share_cents`;
  índice único (equipa, vaga) contra toque duplo. Setting `cleaning_max_professionals = 3`.

Migração `supabase/migrations/20261119200000_limpeza_equipa_2026_11_19.sql` (gerada a partir das
funções que estão no ar, com trocas cirúrgicas):
- `cleaning_quote_team` (nova): preço da equipa no servidor; só "Por hora"; 1 a 3 profissionais.
- `create_cleaning_booking`: parâmetro novo `p_team_size` (por defeito 1; a app antiga continua a
  funcionar); cria a vaga 1 e as irmãs; cada vaga toca à parte.
- `_cleaning_next_offer`: a mesma profissional nunca fica com duas vagas da mesma equipa; o alerta
  "Limpeza sem profissional" diz qual vaga falta; a oferta diz "equipa de 2 — tu e mais 1".
- `_trg_cleaning_team_paid` (novo gatilho): a vaga 1 paga → as irmãs ficam pagas e começam a tocar
  (regra de 19/10: MB Way/cartão só toca depois de pago; dinheiro toca logo).
- `cancel_cleaning_booking`: o cliente cancela sempre a equipa toda (pela vaga 1, taxa sobre o total
  da equipa); uma profissional que desiste só liberta a sua vaga (já era assim por linha).
- `cleaner_accept_booking`: o cliente recebe "Maria confirmou… (equipa: 1 de 2 confirmadas)".
- `_cleaning_complete`: tokens do cliente uma vez por equipa (vaga 1).
- `_trg_cleaning_notify_admin_new`: um só alerta de limpeza nova por equipa, com "EQUIPA DE 2".
- `_cleaning_cron_expire_no_cleaner`: vaga sem ninguém à hora → alerta diz a vaga e quanto devolver.
- `generate_recurring_bookings`: a série repete a equipa, as mesmas profissionais primeiro.
- `cancel_cleaning_series`: cancela pela vaga 1 (a devolução à Carteira é sobre o total, uma vez).
- `cleaning_request_payment`: não pede MB Way nas irmãs.
- `admin_assign_cleaning_cleaner` (nova): painel atribui/troca a profissional de uma vaga à mão.
- Robôs: `supabase/migrations/20261119200100_robos_limpeza_equipa_2026_11_19.sql` (CLEANING_INFO e
  assistant_learned explicam a opção; sai a frase do WhatsApp).

App:
- Cliente: "Quantas profissionais?" 1/2/3 no modo Por hora; aviso clicável em T3/T4+ no modo por
  tamanho; resumo "2 profissionais × 4 h", "2 × €48,00", "+ 2 × €29,00", total €154,00 e "Em
  dinheiro: entregas €77,00 a cada profissional"; acompanhamento com "A tua equipa · 1 de 2
  confirmadas", cada vaga com o seu estado e o seu chat; as irmãs não aparecem repetidas nas listas.
- Profissional (Bloco C): "Equipa de 2 — tu e mais 1", "inclui €29,00 de deslocação (28,6 km de
  estrada)"; em dinheiro "RECEBER" mostra só a parte dela.
- Painel (Bloco D, PT-BR): cartão da limpeza com distância, taxa e "Equipa: vaga 1 de 2 · parte desta
  profissional · total da equipa"; botão "Atribuir profissional à mão"/"Trocar profissional" por
  vaga; exportação CSV com as colunas novas; definições novas editáveis com etiqueta (as de preço e
  de km pelo caminho com motivo e auditoria); o raio da profissional já se editava (5 a 50 km).

Provas na app (testes): `test/limpeza_taxa_deslocacao_wizard_test.dart` — equipa Celorico 4 h × 2 =
€154,00 com 2 × €29,00 e €77,00 a cada uma; aviso de T4+ passa a 2 profissionais × 3 h; modelo da
equipa (vaga 1 com o total, cada uma a sua parte, ganho €69,80).

## Reportes (não corrigidos, fora do scope)
- Lembretes de 24 h e 2 h (`_cleaning_cron_reminders_*`) são por reserva: numa equipa o cliente pode
  receber um lembrete por vaga. Não li o corpo; fica para ver.
- Compensação de cancelamento tardio às profissionais não entra no acerto semanal (só conta
  `completed`); com equipa a mensagem já divide pelo nº de profissionais, mas o pagamento continua
  manual, como antes.
- Se a vaga 1 ficar sem profissional à hora e outra vaga tiver, a vaga 1 é cancelada pelo cron e o
  cliente vê a limpeza principal como cancelada, embora a equipa trabalhe; o alerta ao Danilo diz o
  que devolver. Caso raro; melhoria possível: promover a vaga com profissional a principal.
- `admin_cancel_cleaning` não foi tocada: cancelar a vaga 1 pelo painel não arrasta as irmãs.
