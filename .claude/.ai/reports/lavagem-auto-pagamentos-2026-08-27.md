# LAVAGEM AUTO — cartão, MB WAY e teste no telemóvel

**Data:** 2026-08-27 · **Branch:** `autonomous-night-2026-04-29` · **Motor:** Opus

---

## 🔑 CREDENCIAIS

| | |
|---|---|
| **Lavador "Lava & Leva"** | `lava.leva@bora.app` · `LavaLeva!2026` |
| Cliente de teste | `teste.lavagem@bora.app` · mesma palavra-passe |

---

## RESPOSTA DIRETA: porque não vias a categoria

**Não era o build.** Em números:

- O build `9c9b8f2` correu e **passou nos três workflows** (Android, Web, golden).
- O teu telemóvel **já tinha o versionCode 550 instalado** — o build com a Lavagem Auto.
- A web também já tinha o código publicado (25 ocorrências de "Lavagem" e 48 de "carwash" no JS ao vivo).

Não a vias porque, quando olhaste, **`carwash_enabled` estava `false`** — e o meu próprio
código esconde o ladrilho quando a categoria está fechada. Assim que ligaste,
apareceu. **Está agora visível e provado no teu telemóvel** (captura 04).

Estado agora: **Android versionCode 551** publicado (internal + alpha + production),
web publicada, categoria aberta e cartão/MB WAY ligados.

---

## O QUE FICOU FEITO

### Cartão e MB WAY a sério

Edge **`carwash-checkout`** criada e deployada, no molde do `cleaning-checkout` v5
lido com `get_edge_function` (não do repo). Faz `create` (cartão), `create_mbway`,
`mark_held` e `reverse`.

**A diferença deliberada para o molde — o portão.** O `cleaning-checkout` lê o total e
cobra. Aqui, **antes de qualquer chamada à Stripe**, corre a RPC
`carwash_payment_precheck`, que valida num sítio só: categoria aberta, cartão ligado,
pedido existe e é teu, ainda por pagar, pedido vivo, serviço ligado, **preço igual ao
`carwash_quote` de agora**, morada dentro do raio e mínimo da Stripe.

A lição de 31/07 foi o PaymentIntent nascer antes da order. Aqui é ao contrário: o
pedido existe sempre primeiro, e o valor cobrado vem **sempre do servidor** — o Dart só
manda o id.

**Provado (9 de 10):** o cartão cria o PaymentIntent com o valor certo, e o portão recusa
pedido inexistente, PaymentIntent falso, **preço adulterado** e **categoria fechada** —
todos antes de tocar na Stripe.

Não se tocou em `stripe-webhook`, `create-payment-intent`, `finalizePurchase`,
`pricing_service`, `dispatch_engine` nem em `add_tokens`.

### Uma guarda que não estava prevista, e que era precisa

A app publicada (550) mostra os botões de cartão mas **não traz o código que cobra** —
esse entrou no 551. Ligar o cartão sem mais nada significava: cliente com versão antiga
escolhe cartão, o pedido nasce por pagar, e **o lavador vai buscar o carro de graça**.

Em vez de depender de quem tem que versão, resolvi no servidor: um pedido de
cartão/MB WAY **por pagar não é oferecido a lavador nenhum**. Quando o pagamento fecha,
procura-se lavador nessa altura. Dinheiro segue como sempre.

Provado: pedido a cartão por pagar → sem oferta; pedido a dinheiro → oferecido de imediato.

---

## O TESTE NO TELEMÓVEL (capturas em `provas/capturas-2026-08-27/`)

Fi-lo no **browser do teu telemóvel**, e não na app nativa, por uma razão: a app estava
no perfil de **motorista TVDE e online, à espera de corridas**. Trocar para cliente exigia
logout — não te ia fazer perder trabalho real sem tu decidires.

Percurso completo, com o teu telemóvel:

| # | O quê | Resultado |
|---|---|---|
| 04 | Ladrilho "Lavagem Auto" na grelha | aparece |
| 05 | Os dois serviços, 12 € e 20 € | textos e preços do servidor; "Só interior" escondido |
| 06 | Formulário | morada em primeiro plano, GPS como atalho |
| 09 | Autocomplete da morada | "Rua do Torreão 14, Guarda" com coordenadas reais |
| 12 | **Dinheiro · Cartão · MB WAY lado a lado** | como no delivery |
| 13 | Pedido criado | `AA-11-BB`, 12,00 €, oferta foi ao Lava & Leva |
| 15 | **ETA** | "Aceite — chega daqui a ~15 min (por volta das 13:51)" |
| 18 | **Realtime** | ecrã mudou sozinho para "A lavar · com Lava & Leva" |
| 19 | Ciclo completo | todos os sete estados até "Entregue" |
| 21-22 | Avaliação e fecho | 5 ★, pedido fechado |

**Prova no servidor:** `completed` · 12,00 € = 10,20 € lavador + 1,80 € Bora ·
ETA 15 min · 4 fotos antes + 1 depois · todos os carimbos preenchidos ·
lavador a 5.0. Pedido de teste apagado no fim.

### Dois defeitos que só o teste no aparelho apanhou

**1. O realtime não funcionava de todo.** O lavador aceitava, o servidor gravava
`accepted` com ETA, e o teu ecrã continuava em "À procura de lavador". Nada no Dart
estava errado. A causa: as tabelas novas **nunca foram acrescentadas à publicação
`supabase_realtime`** — o Postgres não emitia um único evento. As da Limpeza estavam lá
desde que nasceram; estas não. Sem isto, o cliente não veria estados, o lavador não
receberia ofertas ao vivo e o chat não entregaria mensagens. Corrigido e provado: o ecrã
passou a mudar sozinho (captura 18).

**2. Fotos em roda-viva eterna.** Quando a foto não existia no bucket, o slot ficava a
carregar para sempre em vez de mostrar que não deu. Corrigido.

Também corrigi a morada duplicada ("…Portugal, Guarda").

---

## ⚠️ O QUE NÃO ESTÁ FEITO

### 1. Tokens — a Trava bloqueou, e não a contornei

Tentei aplicar, com a tua autorização. A Trava recusou, e a mensagem dela diz:
**"Desativar só à mão pelo Danilo, fora do agente."**

Não a contornei — nem por outra via, nem ofuscando o texto. Uma trava que se contorna
deixa de ser trava, e a próxima vez que ela disparar a sério eu já não saberia a diferença.

O código está pronto e é uma linha de diferença:
`supabase/migrations/20260827102000_PROPOSTA_carwash_tokens.sql`.
Chama `add_tokens` (não a altera), com a regra que já vigora: cliente `ROUND(preço×3)`
mínimo 1, lavador +40.

**Provado que não estão a ser dados:** no pedido de teste, `tokens_creditados = 0`.

**Como aplicar:** tu tens acesso MCP ao Supabase sem essa trava — foi assim que ligaste
o `carwash_enabled`. Corre o ficheiro por aí, ou desliga a trava um minuto e eu aplico.

### 2. Pagamento real com o teu cartão — não o fiz

Não introduzo dados de cartão em formulário nenhum. É um limite meu que não abro, e o
teu próprio CLAUDE.md prevê exatamente isto ("ações que as travas de segurança exigem
que sejam humanas... abre-lhe a página e deixa só o clique").

O caminho está pronto e provado até ao PaymentIntent. Para fechar com dinheiro real:
atualiza a app para o 551, faz um pedido a cartão, e o PaymentSheet aparece — os dados
do cartão escreves tu. Fico a acompanhar e verifico tudo no servidor a seguir.

### 3. MB WAY — recusado pelo provedor

O meu código é **idêntico** ao da `create-mbway-payment-intent` que funciona em produção
desde abril (mesmo `payment_method_data`, mesmo `billing_details.phone`, mesmo `confirm`).
Mesmo assim a Stripe devolve *"The PaymentIntent was declined by the provider"* nas duas
tentativas, com o `937501673`.

Isto não se resolve com código. A causa mais provável é esse número não ter MB WAY
associado. Diz-me qual é o número com MB WAY e testo em dois minutos.

### 4. O ladrilho continua com ícone

Tentei a via Gemini do PC: a chave existe, mas está com **quota esgotada (429)** — provei
em seis modelos (`gemini-2.5-flash-image`, `gemini-3-pro-image`, `gemini-3.1-flash-image`,
e mais três). Não fui gastar créditos teus noutro serviço por iniciativa própria.

O ladrilho funciona e está na grelha; só não tem o cartoon dos outros. Quando a quota
renovar, é um comando.

---

## NOTAS

- `git add` caminho a caminho, nunca `-A`. Não se tocou no versionCode.
- Trabalho na worktree `_wt-prod`, para nada alheio apanhar boleia.
- Commits: `f1b3e6c` (pagamentos) e o desta ronda.
