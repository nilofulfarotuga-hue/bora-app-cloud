# Morada automática + o botão que falava sozinho

**Data:** 2026-08-27 · **Branch:** `autonomous-night-2026-04-29` · **Motor:** Opus

---

## 🚀 PARA ANUNCIAR

| | |
|---|---|
| **versionCode novo** | **554** |
| Build Android | terminou **17:29 UTC (18:29 em Lisboa)**, com sucesso |
| Onde foi | internal + alpha + **produção** (o CI publica nas três) |
| Web | publicada e confirmada |
| Categoria | aberta (`carwash_enabled=true`, `carwash_stripe_enabled=true`) |

O envio para a Play correu bem. O tempo até ficar visível às pessoas é da
Google — costuma ser de minutos a poucas horas na produção. **Antes de
anunciares, confirma na Play Console que o 554 aparece como disponível.**

---

## O BUG Nº 1 — o botão que não dizia nada

Tinhas razão em desconfiar, e a causa não era o pagamento.

**O que se passava:** carregaste em "Pedir lavagem · 20.00 €" com campos por
preencher. O código fazia `Form.validate()` e, se falhasse, **voltava atrás em
silêncio**. Os erros até apareciam — mas nos campos *acima* do botão, fora do
que se via no ecrã. Da tua posição, o botão simplesmente não fazia nada.

Bate certo com o que viste no servidor: **zero chamadas** ao
`create_carwash_booking`. O pedido nunca saiu do telemóvel.

**Agora:** o ecrã rola até ao primeiro campo em falta, realça-o, e diz o que
falta — "Falta a matrícula do carro", "Falta dizer onde está o carro", "Falta o
seu telemóvel, para o lavador o contactar".

Um botão que parece funcionar e não faz nada é pior do que um erro.

---

## MORADA AUTOMÁTICA — a varredura completa

Criei o `AutoAddress`, **extraído do que a home já fazia bem** (`_detectLocation`
do `client_home_screen`) em vez de cada ecrã inventar o seu. Reutiliza o mesmo
`LocationService` que o lado do motorista usa — não há mecanismo novo.

Cascata, igual em todo o lado: **morada guardada → casa → GPS + reverse geocoding**.

### Todos os ecrãs onde o cliente escreve uma morada

| Ecrã | Ficheiro | Antes | Agora |
|---|---|---|---|
| Lavagem Auto | `client/carwash/carwash_request_screen.dart` | só botão manual | **automático** |
| Levar Compras | `carry_groceries_form_screen.dart` | não obtinha posição | **automático** |
| Favores | `errand_form_screen.dart` | só botão manual | **automático** |
| Primeira morada (após registo) | `welcome_address_screen.dart` | não obtinha posição | **automático** |
| Home do cliente | `client_home_screen.dart` | já era automático | intacto — é a origem do padrão |
| Enviar Encomenda | `send_package_form_screen.dart` | já era automático | intacto |
| TVDE (pedir viagem) | `client/tvde/tvde_request_ride_screen.dart` | já era automático | intacto |

**Checkout de delivery:** o `cart_screen.dart` não tem campo de morada próprio —
usa a que vem do `CartStore`, definida na home. Como a home já preenchia
sozinha, o checkout herda-a. Não havia nada a corrigir ali.

**Não toquei** nos ecrãs de registo de parceiro, estafeta e profissional de
limpeza. Também pedem morada, mas não são o cliente a pedir — ali a morada é
cadastro, não entrega, e preencher com o GPS de quem regista seria errado.

### A regra de 24/08 continua de pé

O `AutoAddress` **nunca lança e nunca bloqueia**. GPS negado, desligado, sem
sinal ou lento → devolve `null`, o campo fica vazio e escrevível, sem erro e sem
pop-up. E se começares a escrever enquanto ele resolve, ganhas tu: o texto não
é substituído.

Enquanto procura, mostra uma linha discreta — "A obter a sua localização..." —
nunca um ecrã bloqueado.

---

## A PROVA

**Não consegui provar no telemóvel.** `adb devices` devolveu lista vazia em
todas as tentativas, incluindo depois de reiniciar o servidor adb. O Windows
mostra os drivers Samsung com estado `Unknown` — registados de sessões
anteriores, nenhum ligado agora. O Browser pane também não compõe imagem nesta
sessão, por isso não há capturas. **Não digo que está provado no aparelho,
porque não está.**

O que **está** provado:

**1. Dez testes verdes** (`test/carwash_form_check_test.dart`), a correr de
facto:

```
00:00 +10: All tests passed!
```

Cobrem: formulário vazio aponta a morada · só-morada pede a matrícula ·
telemóvel curto não passa · telemóvel com espaços conta dígitos e não símbolos ·
brancos não contam como preenchido · tudo preenchido deixa passar · e a morada
que deixou de repetir a cidade.

Para isto ser testável, a regra saiu de dentro do ecrã para `CarwashFormCheck`,
no modelo. Se algum destes ficar vermelho, o botão voltou a poder falhar calado.

**2. O código novo está publicado na web** — procurado no JS ao vivo:

| marca | ocorrências |
|---|---|
| "A obter a sua localização" | 1 |
| "Falta a matrícula" | 2 |
| "Falta dizer onde está" | 1 |

**3. `flutter analyze`: 0 erros** em tudo o que mexi. Os 6 avisos que restam são
deprecações do `RadioListTile` do Flutter novo, iguais às do resto do projeto.

**Para fechar a prova:** liga o telemóvel por USB com a depuração activa e diz —
abro a Lavagem Auto, mostro a morada a aparecer sozinha, repito noutros dois
ecrãs e faço um pedido completo em dinheiro.

---

## O QUE NÃO ESTÁ FEITO

**O ladrilho continua com ícone.** Tentei outra vez a via Gemini do PC: **429 em
todos os quatro modelos** de imagem. A quota do projeto ainda não renovou. Como
disseste, digo e sigo — não é bloqueador.

---

## NOTAS

- `git add` caminho a caminho. Não se tocou no versionCode (o CI incrementou).
- Commits: `1809427` (morada + validação) e `b2f2783` (testes), ambos
  confirmados no GitHub por API.
- Nada de `finalizePurchase`, `pricing_service`, `dispatch_engine`,
  `create-payment-intent`, `stripe-webhook`, tokens ou `cleaning_*` foi tocado.
