# Bora Assistente — UI Flutter (agente `flutter-ui`, 07/10/2026)

Missão autorizada pelo Danilo (07/10 21:18, "faça tudo"). Sem commit nem push. Não toquei em
dispatch_engine, pricing_service.dart, finalizePurchase, bora_tokens, Stripe nem na lógica de
preço do CartStore (só li `PricingService.applyMarkup`, que é o que os ecrãs de produto já usam).

## Ficheiros criados

| Ficheiro | O que é |
|---|---|
| `lib/services/assistant_service.dart` | Modelos da resposta estruturada (`AssistantReply`, `AssistantProposal`, `AssistantItem`, divisão, favores, acções), chamada à Edge Function `client-assistant` (`functions.invoke`, erros 429/503/401 → `AssistantException`), histórico de `assistant_messages` (coluna `structured` redesenha os cartões), `assistant_mark_proposal`, stats/memória do cliente, `AssistantFlags` (`platform_settings.assistant_enabled`, lido uma vez com sessão; linha vazia ≠ desligado), `pedidoCriado()` (proposta pendente → `ordered`). |
| `lib/screens/client/assistant/assistant_chat_screen.dart` | Ecrã "Bora Assistente": AppBar verde `#16A34A` (gradiente da casa), balões, "a pensar…", faixa de estado (poupança acumulada · mensagens restantes), banner de erro/handoff, composer com foto (câmara/galeria; web só galeria; 1280 px / JPEG q80 / base64, re-encode em isolate se >1,2 MB), microfone (`speech_to_text` 7.4.0, `pt_PT`, inicializa só ao tocar; se não suportado esconde o botão), enviar. Persistência em `bora_assistant.conversation_id`; "Nova conversa"; `mensagemInicial` (faixa da home) e `propostaInicial` (`/#/assistente?proposta=<uuid>` → lê `assistant_cart_proposals` e enche logo). |
| `lib/screens/client/assistant/assistant_cards.dart` | `AssistantProposalCard` (loja, badge Parceiro/Mercado, "Fechada agora", cobertura %, artigos com foto/qtd/linha, "Parecido — confirma", artigos em falta riscados, subtotal/entrega/serviço/pedido pequeno/sacos, TOTAL grande, "Poupas €X face à loja mais cara", aviso +18, botão laranja "Encher o carrinho"), `AssistantDivisaoCard` (2 partes, cada uma com o seu botão), `AssistantFavoresCard` (lista, normal/expresso, adiantamento, "Pedir como Favor"), `AssistantListaExtraidaCard` (chips editáveis + "Confirmar lista"), `AssistantAcoesChips`, `AssistantEmptyState` (3 sugestões). |
| `lib/screens/client/assistant/assistant_encher_carrinho.dart` | "Encher o carrinho": marca `opened` → `lojaPorId` → `abrirLoja` (mesmo caminho das listas: diálogo "Carrinho activo" se for outra loja, `configureSession`, ecrã da loja por baixo) → se loja fechada avisa e pára → `CartItem(productId, name, price: PricingService.applyMarkup(base_price, isPartner), basePrice: base_price, quantity)` (igual aos call-sites actuais; sem base_price usa `unit_price`) → guarda `bora_assistant.pending_proposal` → abre `CartScreen`. |
| `lib/screens/client/assistant/assistant_memory_screen.dart` | "A minha memória": "Já poupaste €X" (`assistant_client_stats`), lista de `assistant_client_memory` (kind legível + key + value), apagar linha e "Apagar tudo". |
| `lib/widgets/bora_assistant_fab.dart` | `BoraAssistantFab` (verde, ícone sparkles) e `BoraClientFabs` (assistente em cima, `BoraSupportFab` laranja em baixo, intocado). Some quando `assistant_enabled=false`. |
| `lib/screens/admin/admin_assistente_screen.dart` | Painel admin PT-BR, 6 separadores: Visão geral (interruptor via `admin_update_setting('assistant_enabled')` + KPIs de `admin_assistant_overview(p_days)` com 7/30/90 dias), Conversas (drill-down nas mensagens com modelo/tokens/latência), Propostas, Conhecimento (criar/editar/ativar), Lacunas (resolver), Correspondências (`product_matches` + `canonical_products` + `products`, "Marcar revista"). |
| `test/assistente_cartao_proposta_test.dart` | 4 testes: cartão (total, poupança, +18, parecido, em falta, botão chama `onEncher`), cartão sem poupança/+18 e fechada, ecrã vazio (3 sugestões clicáveis), desserialização da resposta inteira. |
| `tool/l10n/traducoes/pt-en-11-assistente.json` | Inglês das 75 frases novas (fonte para o gerador). |

## Ficheiros alterados

- `pubspec.yaml` — `speech_to_text: 7.4.0` (fixo: a 7.5.0 exige Flutter ≥3.44 e o CI é 3.41; a 7.4.0 corre em ambos). `flutter pub get` OK ("Changed 3 dependencies"). O `pubspec.lock` é gitignored.
- `android/app/src/main/AndroidManifest.xml` — `RECORD_AUDIO` + `<queries>` `android.speech.RecognitionService` (Android 11+).
- `ios/Runner/Info.plist` — `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` (PT-PT).
- `lib/utils/home_destino.dart` — `lojaPorId()` público; `_ecraCategoria` case `'assistente'` (faixa com `tipo_destino='categoria'`, pedido do coordenador); `abrirDestino` case `'assistente'` (destino = primeira mensagem; `'lista'` abre vazio).
- `lib/main.dart` — rotas `/assistente` (com `propostaDaUrl(Uri.base)`: `?proposta=` antes ou depois do `#`) e `/admin/assistente`; imports.
- `lib/screens/admin/admin_menu_registry.dart` — item `robos_bora_assistente_cliente` na secção "Robôs e Autonomia".
- `lib/screens/profile_screen.dart` — `_AssistenteTile` nos atalhos do cliente ("Bora Assistente" · "Já poupaste €X") → `AssistantMemoryScreen`; escondido com o interruptor desligado.
- `lib/stores/cart_store.dart` — só um hook em `finishOrder`, depois do pedido nascer: `unawaited(AssistantService.pedidoCriado(newOrderId))` (fire-and-forget, nunca trava o checkout) + import. Nada de preço.
- `lib/screens/client_home_screen.dart`, `store_products_screen.dart`, `restaurant_menu_screen.dart`, `stores_screen.dart`, `restaurants_screen.dart` — `floatingActionButton: const BoraClientFabs()` (antes `BoraSupportFab()`); imports sem uso removidos.
- `lib/l10n/strings_en.dart` — bloco "07/10/2026: Bora Assistente" com as 75 entradas (escrito à mão, **não** corri `gerar_dicionario.py --write` porque apaga entradas feitas à mão — cicatriz de 31/08). Inclui 5 frases **pré-existentes** de `lib/widgets/partilhar_localizacao_card.dart` que já faziam o teste de l10n chumbar antes desta missão (outro agente desta noite).

## Provas

- `flutter test test/l10n_cobertura_test.dart test/assistente_cartao_proposta_test.dart` → `00:02 +17: All tests passed!` (13 do l10n + 4 meus). Antes das traduções o l10n chumbava com 75 frases sem inglês (70 minhas + 5 do cartão de partilha de localização).
- `flutter analyze --no-pub` → 271 issues no projeto, **0 erros nos ficheiros que toquei**. Os 2 `error` que existem são de outro agente, em `lib/screens/client/tvde/tvde_ride_tracking_screen.dart:840` e `:881` (LatLng de `latlong2` passado a `google_maps_flutter`) — reportado, não corrigido. Avisos em `profile_screen.dart:182/389/457` são pré-existentes (não são as minhas linhas).
- RAM antes dos comandos Flutter: 1631 MB disponíveis (portão pesado 800 MB cumprido).
- Regra "1 laranja por ecrã": no chat o único laranja é o botão "Encher o carrinho" (um por cartão de proposta; é a acção principal). O FAB do assistente é verde para não duplicar o laranja do FAB de suporte.

## O que não fiz / limites

- Não testei contra a Edge Function real (estava a ser escrita em paralelo); o contrato seguido é o do pedido. Se o servidor mudar nomes de campos, é só o `fromJson` em `assistant_service.dart`.
- O teste "ecrã vazio" prova o `AssistantEmptyState` (o widget que o ecrã mostra sem mensagens), não o `AssistantChatScreen` inteiro — este precisa de `Supabase.instance` e `SharedPreferences` no arranque.
- `speech_to_text` no web depende do navegador (Chrome sim, Safari parcial): o botão aparece e, se `initialize()` falhar, esconde-se com aviso.
- Foto: o `image_picker` já reduz para 1280 px/q80 na maioria dos aparelhos; o re-encode com o pacote `image` só corre em isolate quando o ficheiro passa 1,2 MB.
- `'{0}× {1}'` traduziu para `'{0} × {1}'` (espaço) para não ficar igual por engano.
- Não corri golden tests nem `audit-orange-rule`; não há capturas (sem emulador nesta sessão).
