# Diagnóstico — WhatsApp da loja, 02/09/2026 (Bloco 0)
> Escrito ANTES de corrigir. Causas reais, lidas no código e nos logs, em texto simples.
> Código lido: `ferramentas\whatsapp-loja\{servidor_cerebro.py, atendimento.py, recolha.py, transcrever.py}`
> e `vigia-whatsapp-bora\{content.js, background.js}`. Log lido: `atendimento-log.jsonl` (88 entradas,
> 31/08 12:30 → 02/09 06:34). A conversa real da parceira está em `conversa-parceira.md`.

## Como o bot está montado hoje (para se perceber onde parte)
A extensão do Chrome (`content.js`) lê a lista de conversas do WhatsApp Web, abre as que têm
mensagem nova, lê a **última** mensagem e pergunta ao cérebro local (`servidor_cerebro.py`,
porta 8790) o que fazer. O cérebro (`atendimento.py`) classifica a mensagem com **expressões
regulares** e devolve uma de três coisas: um texto fixo, um texto escrito pelo modelo local
(qwen 7b, com um pedaço do manual), ou "rascunho para o Danilo". A extensão **só envia** quando a
ação é `responder-sozinho` ou `estafeta-lista`; tudo o resto é silêncio. Não há ferramentas: o
modelo nunca vê o Supabase, nunca vê a ficha da pessoa, nunca cria uma tarefa.

## Falha A — "vou verificar" e nunca mais volta
**Onde o bot decide dizer isso** — três sítios, e nenhum deles cria continuação:
1. `atendimento.py`, `tom_base()`: o prompt ao modelo local manda, à letra, *"Se te perguntarem
   algo que o manual nao diz, responde so: 'Deixe-me confirmar isso e ja lhe digo, o senhor.'"*.
   E o modelo só recebe **os primeiros 2.200 caracteres** do manual (`m[:2200]` — o manual tem
   13.000). Quase tudo é "algo que o manual não diz". Resultado no log, ao número de teste:
   "Recarreguei" → *Deixe-me confirmar…*; "Beleza vou mandar as foto" → *Deixe-me confirmar…*;
   "Vou te mandar as foto tá" → *Deixe-me confirmar…*; e a #86, às 16:51 de 31/08:
   **"Você disse que vai confirmar e não confirma nada meu" → "Deixe-me confirmar isso e já lhe
   digo, o senhor."** O bot respondeu à queixa de não confirmar com a mesma promessa.
2. `atendimento.py`, `responde()`: dentro de uma ficha de parceiro, se a pessoa fala de dinheiro,
   pedido ou reclamação, o bot envia *"Deixe-me ver isso e já lhe digo."* — e segue para a
   pergunta seguinte da ficha. Nada fica agendado.
3. `atendimento.py`, categoria `pedido`: devolve *"Vou já ver o seu pedido, um momento."* como
   `rascunho-danilo`. A extensão **não envia rascunhos** — o cliente não recebe nem isto. O aviso
   ao Danilo diz "ver estado no Supabase" mas é um texto para um humano; a máquina nunca vê nada.

**Porque a verificação nunca correu:** não existe verificação. O ciclo é RESPOSTA → (nunca)
ferramenta. Não há tool calling, não há tarefa com prazo, não há vigia. A promessa é uma frase.

## Falha B — "senhor" às cegas
"O senhor" está escrito **doze vezes em textos fixos** (`SAUDACAO_FIXA`, `POSITIVO_FIXA`,
`CORRECAO_FIXA`, `COMO_PEDIR_FIXA`, `RESERVA_FIXA`, `LAVAGEM_FIXA`, `LIMPEZA_FIXA`, `TVDE_FIXA`,
`FAVORES_FIXA`, `HORARIO_FIXA`, `DISPONIBILIDADE_FIXA`, `PARCEIRO_FIXA`), no prompt do modelo
(`tom_base`: *"tratamento por 'o senhor'"*), no manual (§1: *"Tratamento por 'o senhor'"*) e na
limpeza da resposta: `reduz_senhor()` **garante que fica pelo menos um** "o senhor" em cada
resposta. Não há ficha de contacto, não há nome, não há sinal de género em lado nenhum.
Caso real, log #87, 31/08 22:50: **+351 9** *** 120** escreve "Boa noite danilo" → bot: *"Boa
noite, o senhor. Como posso ajudar hoje?"*. Esse número é, no Supabase, o da parceira
**"Sabores do Brasil - Keli Barbosa"** (`restaurants.phone`). O bot tinha como saber — e não olhou.

## Falha C — não sabe tudo
- O modelo vê **16% do manual** (2.200 de 13.000 caracteres) e mais nada.
- O manual cobre uma fracção da app: não tem TVDE a sério, tokens, como baixar a app, como se cria
  conta, pagamentos, cancelamentos, festas, sobremesas, farmácia; nem uma linha sobre o Danilo.
- Sem Supabase: não sabe se quem fala é cliente, estafeta ou parceiro, nem se tem pedido.
- O qwen 7b **inventa** quando não sabe — log #39 *"O senhor pode fechar a porta às 21:00"*,
  #40 e #64 sobre medicamentos, #45 *"sim, entregamos aos domingos, a nossa operação é diária"*
  (antes de o Danilo dar o facto). Foi por isso que se multiplicaram os textos fixos por regex.

## Falha D — áudio
`content.js`, `ultimaMensagem()`: lê o `innerText` da última mensagem. Um áudio **não tem
texto** → `if (!um.texto) { log('ultima msg nao e do cliente (propria/estado), salto') }`. O
áudio é saltado em silêncio, o cérebro nunca o vê, e a conversa fica sem resposta. O
`transcrever.py` (faster-whisper, PT) existe e funciona — mas nada o chama a partir da vigia.

## Falha E — a "trava de não responder" (há mais do que uma)
1. **`rascunho-danilo` = silêncio.** Pedido, dinheiro, reclamação, estafeta/parceiro em falta:
   a extensão não envia nada. E o aviso ao Danilo pelo Telegram **também falhou** — log
   `telegram-falhou` ×4 (31/08 12:30 e 12:58, `ssh` a expirar a partir do cérebro). Silêncio
   para o cliente e silêncio para o Danilo, ao mesmo tempo.
2. **Ollama em baixo = silêncio.** `if not vivo(): rascunho-danilo` — qualquer pergunta
   "geral" fica muda se o modelo local não responder.
3. **A porta era uma janela do Chrome que alguém tinha de deixar aberta.** Não existe tarefa
   de arranque. O Chrome esteve fechado de 31/08 22:50 até 02/09 07:53 (0 processos ao começar a
   missão): **~33 horas sem uma única resposta a ninguém.** Esta é a trava maior.
4. **Contactos guardados com nome são ignorados para sempre.** A vigia só abre conversas cujo
   título é um **número** (`ehNumero(titulo)`, "portão anti-grupo"). Um parceiro guardado como
   "Mr Kebab" nunca é lido. E é exactamente o contacto guardado que prova o nome (Falha B).
5. Filosofia "modo rascunho até o Danilo dizer solta" (`COMO-FUNCIONA.md`, memória 31/08),
   entretanto meio-substituída pela vigia, mas que ainda manda em tudo o que é pedido/dinheiro.
6. `ignorar-ack` ("ok/obrigado" → nada) está **certo** pelas regras novas e fica.

## O que se mantém (não é trava, é regra)
Grupos ignorados por completo · dinheiro/reembolso/desconto/reclamação/falta escalam ao Danilo
(mas passam a **acusar recepção** em vez de calar) · "obrigado" não leva parágrafo.

## A conversa real (02/09, lida no WhatsApp Web) — ver `conversa-parceira.md`
A parceira **"Sabores do Brasil - Keli Barbosa"** (+351 9** *** 120) escreveu "Boa noite danilo"
às 22:50 de 31/08 **e mandou um áudio de 23 segundos com a pergunta**. O bot respondeu "Boa
noite, **o senhor**" (Falha B) e **nunca ouviu o áudio** (Falha D): a pergunta dela ficou sem
resposta até o Danilo entrar à mão às 23:05 e lhe resolver o acesso à loja. O "vou verificar"
que nunca volta (Falha A) está provado seis vezes no log do número de teste (#56, #59, #83,
#86). O bot tinha como saber quem ela era — o número está em `restaurants.phone` — e não olhou.

## Lista de quem ficou sem resposta — ver `sem-resposta.md` (ninguém foi respondido)
