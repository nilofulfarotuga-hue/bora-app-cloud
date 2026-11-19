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
