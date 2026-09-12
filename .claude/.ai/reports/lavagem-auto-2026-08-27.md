# LAVAGEM AUTO — relatório da missão

**Data:** 2026-08-27 · **Branch:** `autonomous-night-2026-04-29` · **Motor:** Opus

---

## 🔑 CREDENCIAIS (guarda isto)

| | |
|---|---|
| **Lavador — "Lava & Leva"** | `lava.leva@bora.app` |
| **Palavra-passe** | `LavaLeva!2026` |
| Conta de cliente (só para testar) | `teste.lavagem@bora.app` · mesma palavra-passe |

O perfil do lavador já está **aprovado e activo**, com base na Guarda
(40.5373, -7.2676) e raio de 8 km. Dono: tu — não há loja fictícia nem dono falso.

---

## O ESTADO EM UMA LINHA

Está tudo construído e **provado no servidor** (33 verificações, 0 falhas).
O serviço está **fechado ao público** à espera do teu "libera".
Duas coisas ficaram por fazer e estão explicadas no fim — **não estão feitas e não digo que estão**.

---

## PARA LIBERAR (quando disseres "libera")

Um único interruptor, no painel: **Lavagem Auto → Configurações → `carwash_enabled` → ligar**.
É só isso. Está tudo o resto pronto por trás.

---

## O QUE FICOU FEITO

### 1. Base de dados — motor clonado, Limpeza intacta

Seis tabelas novas, **todas com RLS** (verificado: 6 de 6):
`washers` · `washer_availability` · `carwash_bookings` · `carwash_messages` ·
`washer_weekly_settlements` · `washer_cancel_events`

- **42 funções** e **13 policies** criadas.
- **Não se tocou em nada `cleaning_*`** — as 39 funções da Limpeza continuam
  exactamente como estavam (verificado antes e depois).
- **A lição do Valdemir foi aplicada desde o primeiro minuto:** a chave do
  lavador é sempre o `user_id`. Há uma função única (`_carwash_my_washer_id()`)
  usada por TODAS as policies, de leitura e de escrita — não podem divergir,
  porque são literalmente a mesma linha de código. O teste confirmou que o
  lavador vê o pedido **e** consegue avançá-lo.
- Fotos em bucket **privado** `carwash-photos` (verificado: `public = false`).

### 2. Preços — no painel, não no código

14 definições novas, todas editáveis por ti. Preço final ao cliente, sem taxas por cima:

| Serviço | Preço | Bora (15%) | Lavador | Duração |
|---|---|---|---|---|
| Lavagem exterior | 12,00 € | 1,80 € | 10,20 € | 60 min |
| Lavagem completa | 20,00 € | 3,00 € | 17,00 € | 110 min |
| Só interior | 12,00 € | — | — | 50 min |

O **"Só interior" nasceu desligado**, como pediste. Ligas num toque no painel.

### 3. App do cliente (PT-PT)

Ladrilho novo na grelha inicial → escolher serviço → onde está o carro →
dados do carro → quando → pagamento → acompanhamento.

- **A localização NUNCA trava** (regra de 24/08): o campo de escrever a morada
  está em primeiro plano, "Usar a minha localização" é só um atalho, e GPS
  negado ou desligado não impede nada.
- **Foto do carro: opcional de verdade.** Convite leve com a frase que pediste.
  Se não juntar, o pedido segue igual — sem alerta, sem asterisco, sem repetir.
- Chips: Agora · Daqui a 30 min · Daqui a 1 h · Escolher dia e hora.
- Barra de estados igual à da entrega, chat e telefone dos dois lados,
  fotos antes/depois e avaliação por estrelas.
- **ETA:** ao aceitar, o servidor mede a distância, assume 25 km/h de trânsito
  urbano, soma 10 min de folga e arredonda para cima em blocos de 5.
  Promete a mais, nunca a menos. Testado: deu 10 min.

### 4. App do lavador

Oferta rotativa com 10 min para responder, botões de estado, chat, ganhos.

**As 4 fotos da recolha são mesmo obrigatórias** — e não só porque o botão fica
cinzento. **O servidor recusa** a recolha se faltar qualquer ângulo. Foi testado
a sério: com 0 fotos recusa, com 2 fotos recusa, com as 4 passa. Só câmara,
na hora — a galeria não é opção. As fotos da entrega são opcionais, com convite.

### 5. Painel admin (PT-BR)

Cinco separadores: **Pedidos** (filtros, detalhe com fotos, criar à mão, editar,
reagendar, cancelar, **reatribuir a outro lavador**) · **Lavadores** (aprovar,
editar raio, activar, banir — com trava se tiver pedido em curso) ·
**Agrupar idas** (carros perto uns dos outros numa janela de horas) ·
**Acertos** (recalcular, marcar pago) · **Configurações** (todos os preços).
Mais exportação CSV e auditoria de quem mexeu no quê.

A **reatribuição nasceu feita** — é a que faltava nos pedidos normais e obrigou
a SQL à mão em 16/08.

### 6. Notificações — a armadilha evitada

Edge Function `notify-washer` **deployada e DATA-ONLY**. O molde que copiei
(`notify-cleaner`) ainda tem o bloco `notification` — essa parte foi
deliberadamente **não** copiada, porque é exactamente o que faz o Android
desenhar pelo tray e o handler do Flutter não correr.
Verificado no corpo **deployado** (não no local): não tem bloco `notification`,
e o title/body viajam dentro do `data`. Testada ao vivo: responde.

### 7. Um buraco de segurança que eu próprio abri — e fechei

O Postgres dá permissão de execução a `PUBLIC` por omissão. Isso deixou funções
internas (`_carwash_notify_user`, os crons, as transições) **chamáveis por
qualquer anónimo** — alguém podia mandar push a qualquer utilizador.

A primeira correcção (`REVOKE ... FROM anon, authenticated`) **não funcionou**,
porque não remove o que vem herdado de `PUBLIC`. Só vi isso porque fui
verificar em vez de assumir. A correcção certa é `REVOKE ... FROM PUBLIC`.

Estado agora, verificado: das 42 funções, **só 1 está aberta a anónimos** —
a `carwash_quote`, de propósito, para o preço aparecer antes de haver sessão.

---

## A PROVA

Teste ponta-a-ponta contra **produção**, com JWT reais de cada utilizador
(passa pela RLS e pelas RPCs como a app faz).
Ficheiro: `.claude/.ai/reports/provas/carwash-e2e-2026-08-27.txt`
Script (repetível): `.claude/testes-e2e/e2e_carwash.py`

**33 verificações passaram, 0 falharam.** Entre elas:

- preço 20,00 € = 17,00 € lavador + 3,00 € Bora — **as contas fecham**
- cartão recusado **antes** de tocar no Stripe (lição de 31/07)
- morada fora dos 8 km recusada
- o lavador **vê** a oferta e **consegue** avançá-la (lição do Valdemir)
- ETA calculado, múltiplo de 5, com a folga de 10 min
- recolha sem as 4 fotos **recusada pelo servidor**
- ciclo completo até `completed`, com todos os carimbos de tempo gravados
- avaliação de 5 estrelas gravada, contador do lavador subiu

O pedido de teste foi apagado no fim (0 pedidos na base) e o serviço ficou fechado.

---

## ⚠️ O QUE **NÃO** ESTÁ FEITO

### 1. O teste no telemóvel — NÃO foi feito

`adb devices` devolveu **lista vazia**: não há nenhum aparelho ligado por USB.
Como mandaste, **não digo que está feito**. Falta validar no aparelho: os ecrãs,
a câmara nas 4 fotos, e o push a chegar de facto. O motor por trás está provado;
o que falta é a camada de vidro.

**Para fechar isto:** liga o telemóvel por USB e diz — corro o build e faço o
percurso todo no aparelho.

### 2. ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO — confirma que eu aplico

Duas peças ficaram preparadas mas **não aplicadas**, porque mexem em dinheiro:

**(a) Tokens ao cliente e ao lavador.**
A Trava de segurança bloqueou — ela recusa qualquer alteração cujo texto
contenha `add_tokens`, e não distingue "chamar" de "alterar". Eu só chamo a
função que já existe; não lhe toco. Não contornei a Trava.
O Bloco E da tua ordem previa exactamente este caso ("se não conseguires sem
mexer na zona `bora_tokens`, não mexas").
Está pronto em `supabase/migrations/20260827102000_PROPOSTA_carwash_tokens.sql`.
Regra: cliente `ROUND(preço×3)` mínimo 1, lavador +40 — igual ao resto da app.

**(b) Cartão e MB WAY.**
A Limpeza cobra por uma Edge Function isolada (`cleaning-checkout`). Fazer a
equivalente para a lavagem significa criar uma função que **gera cobranças
reais** — Lista Vermelha. Deixei o portão fechado do lado certo:
`carwash_stripe_enabled = false`, e o servidor **recusa cartão/MB WAY antes de
tocar no Stripe**. Dinheiro funciona a 100%, que era o que o teste pedia.

Diz **"vai"** e aplico as duas.

### 3. O desenho do ladrilho

O ladrilho está lá e funciona, mas com um ícone em vez do cartoon no estilo dos
outros. O gerador de imagens (nano-banana/Gemini) não estava ligado nesta sessão
e não fui gastar créditos teus por iniciativa própria. Está marcado no código;
quando o gerador estiver ligado, é trocar o ícone pelo PNG.

---

## NOTAS DE EXECUÇÃO

- Trabalhei numa **worktree separada** (`_wt-prod`) porque o repo principal
  tinha 4 ficheiros por committar de outra sessão. Assim nada alheio apanhou
  boleia no commit — a lição de 14/07.
- `git add` foi feito **caminho a caminho**, nunca `-A`.
- Não se tocou no `versionCode`.
- Zonas protegidas intactas: `dispatch_engine`, `pricing_service.dart`,
  `finalizePurchase`, `bora_tokens`, webhook Stripe, RLS de `orders`/`wallets`/`ledger`.
- Os ficheiros de migration no repo são o **espelho fiel** do que está aplicado:
  o `20260827103000_carwash_ddl_efetivo.sql` foi extraído da própria base de
  produção, não escrito à mão.
