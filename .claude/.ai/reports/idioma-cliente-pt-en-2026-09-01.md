# Alternador de idioma PT/EN no app cliente

**Missão:** `idioma-cliente-2026-09-01` · **Motor:** Opus · **Modo:** Protecção Total
**Branch:** `autonomous-night-2026-04-29` · **Estado:** feito, por empurrar (ver §8)

---

## 1. O que ficou feito, em duas linhas

O app do cliente passa a falar inglês. Há um botão pequeno **"PT | EN"** e, quando se
toca nele, **todas** as telas do cliente mudam de idioma — não só a tela onde está o
botão. A escolha fica gravada no telemóvel. Estafeta, parceiro e painel admin não foram
tocados.

**Números:** 1686 frases traduzidas em 114 ficheiros · dicionário com 1303 entradas ·
`flutter analyze` **0 erros** · `flutter test` **350 verdes**.

---

## 2. Antes de começar — o que foi conferido

| Verificação | Resultado |
|---|---|
| Córtex: decisão anterior sobre idioma/i18n/tradução | **0 resultados** — confirmado, não havia nada registado |
| `pubspec.yaml`: solução de i18n já instalada | **Nenhuma**. Há `flutter_localizations`, mas está lá só para o `showDatePicker` (BUG #12, 2026-05-13) — não traduz texto da app |
| RAM disponível (portão pesado = 800 MB) | **1025 MB** — passou |
| Linha de base do `analyze`, antes de tocar em nada | **264 avisos, 0 erros** |

---

## 3. Qual solução de i18n, e porquê

Não existia nenhuma, portanto a escolha foi minha. Não usei `easy_localization` nem o
l10n oficial com ficheiros ARB. Usei um **dicionário em Dart puro, sem dependência nova**,
onde **a chave é o próprio texto em português**:

```dart
Text('Adicionar ao carrinho'.tr)   // PT: devolve-se a si próprio · EN: "Add to cart"
```

Três razões, por ordem de peso:

1. **Nunca aparece uma chave técnica no ecrã.** A verificação pedia isso explicitamente.
   Com chaves do tipo `cart.add_button`, uma tradução em falta mostra `cart.add_button`
   ao cliente. Aqui, o pior caso de uma falha é ficar em **português** — que é o
   comportamento antigo, não um defeito visível.
2. **Em português, o comportamento é o de antes, byte a byte.** `.tr` é a identidade
   quando o idioma é PT. Isso é o que torna esta mudança segura numa app que já está no
   ar: uma tela que ninguém traduziu não muda de nada.
3. **Zero dependências novas e zero geração de código.** O PC do Danilo tem 4 GB e o CI
   compila Android + web a cada push. O l10n oficial acrescentava um passo de codegen a
   todos os builds; o `easy_localization` acrescentava um pacote e carregamento de JSON
   no arranque. Nenhum dos dois pagava o seu custo aqui.

**O preço desta escolha:** não há verificação de chaves em tempo de compilação. Foi pago
com um teste — `test/l10n_cobertura_test.dart` varre o código todo por conta própria e
chumba se alguma frase estiver sem inglês. Não depende de ninguém se lembrar.

### As peças

| Peça | Ficheiro |
|---|---|
| Estado do idioma + gravação no telemóvel | `lib/l10n/bora_lang.dart` |
| `String.tr` e `String.trArgs([...])` | `lib/l10n/tr.dart` |
| Dicionário PT→EN (**gerado**, 1303 entradas) | `lib/l10n/strings_en.dart` |
| Traduções à mão (fonte, versionada) | `tool/l10n/traducoes/*.json` |
| Gerador | `tool/l10n/gerar_dicionario.py` |
| Como manter isto | `tool/l10n/README.md` |
| Botão "PT \| EN" | `lib/widgets/language_toggle.dart` |

---

## 4. Telas cobertas

**131 ficheiros no escopo do cliente — 83 ecrãs + 48 widgets.** O escopo não foi escolhido
a olho: foi traçado pelo **grafo de imports** a partir dos pontos de entrada do cliente
(`role_screen`, `client_login_screen`, `client_main_screen`, `register_client_screen`,
`qr_client_signup_screen`, `reset_password_screen`, `forgot_password_screen`).

Cobre, por família:

- **Arranque e conta** — escolha de perfil, entrar, criar conta, recuperar palavra-passe,
  redefinir palavra-passe, registo por QR, biometria, consentimento de privacidade
- **Home e navegação** — home do cliente, barra de morada, ladrilhos de categoria,
  notificações, perfil, endereços, favoritos de morada
- **Comida e lojas** — restaurantes, menu, opções de prato, detalhe de produto,
  supermercados, farmácias, lojas, categorias de loja, mercado (loja/categorias/repetir),
  sobremesas, festas
- **Carrinho e pagamento** — carrinho, formas de pagamento (cartão, MB Way, dinheiro),
  cartões guardados, carteira e histórico, dívida, códigos promocionais, gorjeta,
  saco, taxa de pedido pequeno
- **Pedido** — confirmação, acompanhar pedido, detalhe, cancelamento, avaliações,
  chat com estafeta e com loja
- **Favores e transportes** — pedir favor, levar compras, enviar encomenda, orçamento,
  talão, autorização de compra acima do orçado
- **TVDE** — pedir corrida, agendar, acompanhar, paradas, ida-e-volta, planos, histórico,
  avaliar, chat
- **Reservas** — procurar mesa, disponibilidade, checkout com pré-pagamento, detalhe,
  fila de espera, avisar-me se vagar, as minhas reservas
- **Serviços e limpeza e lavagem** — categorias, prestador, marcar, as minhas marcações,
  assistente de limpeza, acompanhar, lavagem auto, chats
- **Suporte** — ecrã de suporte, FAQ, chat com a Bora IA, email ao suporte

**Prova de completude:** uma varredura independente sobre os 131 ficheiros procurou texto
em posição de exibição (`Text(`, `label:`, `title:`, `hintText:`, …) **sem** `.tr`.
Sobraram **20**, e são todos deliberados:

- **13** rótulos dos ladrilhos da home — ficam em português de propósito, porque são a
  **chave** do mapa `semanticsIds` que dá os `resource-id` aos testes E2E. São traduzidos
  no momento de desenhar (`label: t.label.tr`), o que dá as duas coisas ao mesmo tempo.
- **7** `semanticLabel: 'BORA'` — nome da marca, não se traduz.

---

## 5. O que NÃO foi traduzido, e porquê

### 5.1 Nomes e descrições de produtos, lojas e restaurantes
Como a ordem já dizia: é dado que o parceiro escreveu na base de dados, não é texto da
app. **A moldura à volta vira inglês normalmente** — cabeçalhos, filtros, categorias,
"Add to cart", preços, taxas. Só o nome do produto fica como o parceiro o escreveu.

### 5.2 Texto que outra pessoa vai ler (achado durante o trabalho — vale a pena saber)
Apareceram dois sítios onde o **cliente escreve** e **outra pessoa lê**. Se traduzisse,
um restaurante da Guarda passava a receber rótulos em inglês:

- `reservation_checkout_screen._buildCombinedNotes()` — junta "Ocasião / Pedidos
  especiais / Notas" numa string que vai **gravada no pedido**; quem a lê é o restaurante
  (PT-PT) e o painel admin (PT-BR).
- `order_tracking_screen` — o motivo de cancelamento composto (`Outro motivo: …`) é
  **gravado na base de dados** e lido no painel admin.

Ambos ficaram em português, com o porquê escrito ao lado no código.

### 5.3 Coisas que pareciam texto e eram lógica
A ordem mandava parar e reportar se aparecesse lógica em vez de string fixa. Apareceu, e
foi tudo revertido. As que valem a pena registar:

| O que era | Onde | Se fosse traduzido |
|---|---|---|
| `'id, original_name, original_price_cents, …'` | `order_details_screen` | Lista de colunas de um `SELECT` — a consulta rebentava |
| `'https://www.google.com/maps/dir/?api=1&destination=…'` | `botao_rota` | O botão "Como chegar" deixava de abrir o mapa |
| `'receipts/{0}'`, `'menu_{0}_{1}'`, `'restaurant_{0}'` | vários | Caminhos de storage e chaves de cache |
| `'__any__'` | `booking_flow_screen` | Sentinela de "qualquer profissional" |
| `'/loja/'`, `'/servico/'` | `deep_link_store_screen` | Prefixos de deep link |
| `'áàâã…'` (tabela de acentos) | `store_products_screen` | A pesquisa sem acentos deixava de funcionar |
| `_stopWords`, `_privateBuckets` | `staff_avatar`, `private_bucket_image` | Listas de controlo |
| `[profile_screen] direct upload failed…` | `profile_screen` | Mensagens de log de diagnóstico |

### 5.4 Duas correcções que só se veem a olho
- **`'Sair'`** estava traduzido como *Sign out*. Só existe num sítio: o botão que confirma
  **sair da fila de espera** de um restaurante. Passou a *Leave*. Traduzir por "Sign out"
  ali era dizer ao cliente que ia terminar a sessão.
- **Rótulos que não cabiam em inglês** — 8 encurtados por caberem em abas, chips e linhas
  de resumo (ex.: a aba *Notify me if one frees up* passou a *Notify me*; o botão do
  banner de privacidade passou de *Manage preferences* a *Preferences*, que estava a
  partir em duas linhas e a desalinhar os botões).

---

## 6. Dinheiro: nada mexeu

**Nenhum ficheiro de dinheiro foi tocado.** `pricing_service.dart`, `finalizePurchase`,
`dispatch_engine`, `bora_tokens`, webhook Stripe e RLS ficaram intactos —
`git status` não os lista.

Duas travas específicas de tradução, para o valor nunca poder mudar:

1. **Nenhum algarismo, símbolo de moeda ou separador decimal foi alterado em nenhuma das
   1303 traduções.** Só as palavras à volta. `'6 € até 4 km · +0,50 €/km acima'` ficou
   `'6 € up to 4 km · +0,50 €/km beyond'` — os números são os mesmos caracteres.
2. **Valores interpolados passam intactos.** Uma frase com um preço lá dentro vira um
   molde com marcador posicional e o valor entra por fora:
   `'Adicionar ao carrinho · €{0}'.trArgs([total])`. O `total` nunca passa pelo dicionário.
   Há um teste que prova isto (`o valor entre marcadores passa intacto`).

Uma terceira trava, mecânica: antes de traduzir qualquer frase, cada literal foi cruzado
com **todo o `lib/`** para ver se o seu **valor** importa nalgum sítio (comparação `==`,
`case`, chave de mapa, chamada a Supabase/SharedPreferences, `MarkerId`, `RegExp`).
Quem tivesse uso de valor ficou de fora. Foi essa rede que apanhou os casos do §5.3.

---

## 7. Verificação

| O que a ordem pedia | Como foi provado | Resultado |
|---|---|---|
| Nada fica sem tradução | `test/l10n_cobertura_test.dart` varre o código por conta própria (não lê o dicionário para saber o que procurar) e compara com o mapa inglês | **0 frases sem inglês** |
| Nunca mostrar a chave em vez do texto | Por desenho — a chave **é** o português. Teste `chave desconhecida cai no português — nunca na chave crua` | verde |
| Trocar PT→EN→PT não parte nada | Teste de widget que monta a app com o mesmo mecanismo do `main.dart` e faz PT→EN→PT | verde |
| Escolha guardada no aparelho | Teste que grava, relê com `BoraLang.load()` e confirma; e ao vivo na web, com recarregamento | verde |
| Idioma padrão é sempre PT | Teste com armazenamento vazio + confirmação ao vivo em browser limpo | verde |
| Marcadores `{0}` não se perdem | Teste que compara os marcadores de PT e EN, entrada a entrada | verde |
| Nada quebra o layout em inglês | `test/golden/ingles_sem_estouro_test.dart` — reusa o harness de fotos já existente com o idioma em EN. Overflow lança `FlutterError` e o teste falha sozinho | **8 verdes**: escolha de perfil (3 tamanhos), grelha de categorias (360/390/430 px), painel de privacidade, e nenhum rótulo cortado com reticências |
| `flutter analyze` sem novos erros | Corrido do princípio ao fim | **0 erros** · 213 avisos (base: 264 — **menos 51**, nenhuma regra piorou) |
| `flutter test` | Suíte completa | **350 verdes, 0 falhas** |
| Fluxo de pagamento em dinheiro, nos dois idiomas, sem nenhum valor mudar | Ver §7.1 — **feito por leitura de código e testes, não por compra real** | ver ressalva |

### 7.1 Prova de ecrã — o que se viu e o que não se viu

Feita pela web (`PADRAO_BORA` §3.10), em viewport de telemóvel (375×812).

**Visto ao vivo, nos dois idiomas:** ecrã de escolha de perfil e painel de privacidade e
cookies — que é, na prática, a primeira coisa que qualquer pessoa vê. Layout intacto nos
dois, alternador a funcionar, e a app a arrancar em inglês depois de reabrir.

**Não visto ao vivo:** as telas depois do login. **A razão é uma trava de segurança minha,
não uma falha do trabalho** — não posso escrever palavras-passe em campos de formulário,
nem sequer as da conta de demonstração. Não contornei.

O que essas telas têm a garanti-las: a varredura de completude do §4 (0 frases por
traduzir em posição de exibição), o teste de cobertura, o teste de marcadores, e os 342
testes da suíte — que incluem os testes de checkout e de carteira já existentes, todos
verdes.

**Para fechar isto a 100%, é preciso um par de olhos com sessão iniciada:** entra na app
(web ou telemóvel), toca em EN e passa pelo carrinho → forma de pagamento → dinheiro →
confirmar. Se algum texto ficar cortado numa caixa apertada, diz-me qual e eu encurto —
o dicionário está num ficheiro só, é uma linha de mudança.

---

## 8. O que falta decidir (para o Danilo)

### 8.1 O push
Está tudo pronto mas **não empurrei**. Um push nesta branch dispara build Android **e**
deploy web, e há trabalho de outras sessões por commitar na árvore
(`analysis_options.yaml`, PNGs de golden tests, pastas `.claude/`, `.codex/`, ficheiros
`.bak`). Empurrar agora levava tudo isso à boleia. Diz "vai" e eu faço o commit só dos
ficheiros desta missão e empurro.

### 8.2 Painel admin — a suposição confirma-se
Como a ordem previa: **não é preciso nada de novo no admin**. A escolha de idioma é uma
preferência guardada no aparelho (`SharedPreferences`), não vai à base de dados, e o
painel continua em PT-BR.

Se quiseres saber **em que idioma cada cliente usa a app**, isso passa a exigir uma coluna
nova em `users` e escrita a partir do telemóvel. **Não implementei** — é decisão tua, e o
que a ordem mandava era reportar em vez de decidir. Uma linha tua e eu faço.

### 8.3 Uma decisão que tomei e convém saberes
O botão foi para a home, como pedias — **e também para o ecrã de escolha de perfil e para
o painel de privacidade**. Sem isso, a funcionalidade não cumpria o objectivo: quem
instala a app cai primeiro no painel de privacidade, que é modal e tapa tudo. Um
estrangeiro ficava a decidir sobre privacidade em português, sem forma de trocar. Com o
botão nesses dois sítios, troca antes de precisar de perceber o que quer que seja.

---

## 9. Manutenção — o que a próxima pessoa precisa de saber

Texto novo num ecrã do cliente:

```dart
Text('Encomenda entregue'.tr)                    // sem valores
'Faltam {0} minutos'.trArgs([min])               // com valores
```

Depois: põe o par em `tool/l10n/traducoes/`, corre
`python tool/l10n/gerar_dicionario.py --write` e `flutter test test/l10n_cobertura_test.dart`.

Se esqueceres o segundo passo, **o teste diz-te qual é a frase e em que ecrã está**. O
detalhe todo, incluindo o que nunca leva `.tr` e porquê, está em `tool/l10n/README.md`.

---

## 10. Ficheiros

**Novos:** `lib/l10n/{bora_lang,tr,strings_en}.dart` · `lib/widgets/language_toggle.dart`
· `test/{l10n_cobertura,language_toggle}_test.dart` ·
`test/golden/ingles_sem_estouro_test.dart` · `tool/l10n/` (gerador, README, 10 ficheiros
de tradução)

**Uma ratoeira apanhada pelo caminho:** correr `flutter run -d web-server` acrescentou
sozinho `web: any` ao `pubspec.yaml`. O próprio pubspec avisa, num comentário, que
`package:web` **parte o kernel snapshot do Android**. Foi revertido, e o `pubspec` está
limpo. Fica o aviso: quem correr a app na web tem de conferir o `pubspec` antes de
commitar.

**Alterados:** `lib/main.dart` (arranque do idioma + redesenho) e **114 ecrãs e widgets**
do cliente (78 em `lib/screens`, 36 em `lib/widgets`).

**Não tocados:** estafeta, parceiro, painel admin, e todas as zonas protegidas.
