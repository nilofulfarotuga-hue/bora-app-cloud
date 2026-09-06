# Alternador PT/EN do app cliente

> Escrito na missão `idioma-cliente-2026-09-01`.

O app do cliente fala português e inglês. Estafeta, parceiro e painel admin
**não** mudam — o alternador só existe no lado do cliente.

## Como está montado

| Peça | Onde |
|---|---|
| Estado do idioma (+ gravação no aparelho) | `lib/l10n/bora_lang.dart` |
| A função que traduz | `lib/l10n/tr.dart` — `String.tr` e `String.trArgs([...])` |
| Dicionário PT→EN (**gerado**) | `lib/l10n/strings_en.dart` |
| Traduções, à mão | `tool/l10n/traducoes/*.json` |
| Botão "PT \| EN" | `lib/widgets/language_toggle.dart` |
| Onde o botão aparece | `client_home_screen.dart` (header) e `role_screen.dart` (1.º ecrã) |
| Rede que faz o ecrã redesenhar | `main.dart` — listener + `KeyedSubtree` com a chave do idioma |

## A decisão que explica tudo o resto: **a chave é o português**

```dart
Text('Adicionar ao carrinho'.tr)      // PT: devolve-se a si próprio · EN: "Add to cart"
```

Não há chaves do tipo `cart.add_button`. Isso dá três coisas de graça:

1. **Nunca aparece uma chave técnica no ecrã.** Se faltar a tradução, sai o
   português. O pior caso é ficar por traduzir — nunca é ficar ilegível.
2. **Em português o comportamento é o de antes**, byte a byte: `.tr` é a
   identidade. Um ecrã que não muda de idioma não muda de nada.
3. Lê-se o código e vê-se o texto, sem saltar para um ficheiro de chaves.

## Acrescentar texto novo a um ecrã

1. Escreve normalmente e acrescenta `.tr`:
   ```dart
   Text('Encomenda entregue'.tr)
   ```
   Com valores lá dentro, usa marcadores posicionais em vez de interpolação:
   ```dart
   // em vez de 'Faltam ${min} minutos'
   'Faltam {0} minutos'.trArgs([min])
   ```
   Os valores passam intactos — preços, distâncias e nomes de loja não são
   traduzidos, só a moldura de texto à volta.
2. Põe o par em `tool/l10n/traducoes/` (qualquer um dos ficheiros serve).
3. Gera:
   ```bash
   python tool/l10n/gerar_dicionario.py --write
   ```
4. `flutter test test/l10n_cobertura_test.dart`

O teste varre o código outra vez, por conta própria, e chumba se alguma frase
ficar sem inglês. Não é preciso lembrar-se de nada: se te esqueceres do passo 2,
o teste diz-te qual é a frase e em que ecrã está.

## O que NÃO leva `.tr`

Isto não é preferência, é o que parte a app se for traduzido:

- **Nomes e descrições de produtos, lojas e restaurantes.** Vêm da base de
  dados, escritos pelo parceiro. Traduzi-los era outro projecto — dezenas de
  milhares de linhas — e não é texto da app.
- **Valores comparados ou gravados**: `status == 'delivered'`, chaves de mapa,
  chaves de SharedPreferences, ids de marcador do mapa, nomes de coluna.
- **Texto que outra pessoa vai ler.** Se o cliente compõe uma nota que vai
  gravada no pedido e quem a lê é o restaurante (PT-PT) ou o painel admin
  (PT-BR), essa fica em português. Já acontece em
  `reservation_checkout_screen._buildCombinedNotes()` e no motivo de
  cancelamento em `order_tracking_screen`, ambos com o porquê escrito ao lado.
- **Logs, URLs, caminhos de storage e listas de colunas SQL.**

## Rótulos que também são chaves

Os ladrilhos da home (`client_home_screen`) usam o rótulo **em português** como
chave do mapa `semanticsIds`, que dá os `resource-id` aos testes E2E. Por isso
o rótulo guardado é sempre PT e a tradução acontece só no momento de desenhar
(`label: t.label.tr`). Se traduzires o rótulo na origem, os testes E2E deixam
de encontrar os ladrilhos.

## Idioma por omissão

**Sempre português**, mesmo que o telemóvel esteja em inglês. Só muda quando
alguém toca no botão, e a escolha fica gravada em `SharedPreferences`
(`bora_app.language`). Está assim de propósito — a app é da Guarda.
