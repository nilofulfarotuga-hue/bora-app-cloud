# Motor Bora — Kilo sem chave, rodízio, vigia de modelos mortos e custo simulado · e o facto do iPhone
**04/09/2026, 04:30–06:30 (Lisboa).** Tudo medido; saídas literais.

## 1. O facto do iPhone (ordem do Danilo)

O Bora **não tem app para iPhone**. Quem tem iPhone pede pela web, em https://app.boraguarda.com.
Entrou em três sítios, porque o manual sozinho não chega — a 02/09 o modelo respondeu "Sim, temos!
Podes descarregar na App Store":

| onde | o que faz |
|---|---|
| manual (`MANUAL-ATENDIMENTO-BORA.md` §5 e FAQ 4) | a resposta escrita, e a pergunta saiu da lista "PERGUNTAR AO DANILO" |
| `agente.FACTOS_OPERACAO` | o facto vai em todos os pedidos ao modelo |
| `agente.RE_IPHONE` → `IPHONE_FIXO` | a pergunta responde-se por **texto fixo**, sem modelo |
| `agente.RE_IPHONE_MENTIRA` no pós-processamento | rede de segurança: se o modelo escrever "App Store"/"app para iPhone", a frase é substituída |

Testes da rede de segurança (4 respostas más trocadas, 3 boas deixadas passar) e ao vivo:
```
1.6s facto-fixo  "Tem app para iPhone?"          -> App para iPhone não temos. No iPhone é pela web, em https://app.boraguarda.com…
1.3s facto-fixo  "Vocês têm aplicativo para iOS?" -> (o mesmo texto)
1.7s groq:qwen   "Como baixo a app?"              -> Se tens Android, baixa na Play Store… Se tens iPhone, não há app, mas…
```

## 2. Serviço nosso negado — trava nova (apanhada nesta mesma noite)

Na rajada, o Gemini respondeu a **"Vocês fazem limpezas?"** com *"Não, nós somos uma plataforma de
entrega de comida"*. Isso perde clientes. `agente._corrigir_negacao_de_vertical` verifica: se a
pergunta é sobre uma vertical nossa (limpeza, lavagem, TVDE, reservas, farmácia, compras, encomendas)
e a resposta começa por negar, sai o texto certo. 7 de 7 casos certos em teste; e ao vivo:
```
4.2s gemini-3-flash-preview  "Fazem lavagem de carro?"  [corrigido: lavagem]
     -> Fazemos sim: lavagem auto (por agora só exterior). Está na app, em Lavagem.
```

## 3. Kilo Gateway — o fornecedor que não depende de ninguém

`https://api.kilo.ai/api/gateway`, compatível OpenAI, **sem chave e sem conta**. Provado:
```
GET /models  -> 200 sem Authorization: 369 modelos, 16 deles ":free"
POST /chat/completions (sem chave), pelo roteador:
  stepfun/step-3.7-flash:free            5.9s -> KILO-NO-MOTOR-OK
  dots-studio/dots-3-note-preview:free   3.9s -> KILO-NO-MOTOR-OK
  liquid/lfm-2.5-2.6b:free               1.7s -> KILO-NO-MOTOR-OK
```
Os modelos pagos devolvem `PAID_MODEL_AUTH_REQUIRED`, por isso a descoberta filtra só os `:free`
(bandeira `so_free`, a mesma do OpenRouter). Tecto assumido: 12/min e 180/hora por IP. Armadilha
encontrada: são modelos que "pensam" antes de escrever e com tecto curto devolvem **200 com texto
vazio** — o roteador passou a pedir-lhes no mínimo 500 tokens e a ler também o campo do raciocínio.

## 4. Rodízio por perfil — era isto que faltava para a prova 4

`chat-rapido` e `volume` passam a **rodízio** (roda entre os 4 melhores a cada pedido); `raciocínio`
fica em **cadeia** (o melhor primeiro). Teste da rotação, cinco pedidos seguidos:
```
pedido 1 -> groq, groq, cerebras, gemini      pedido 4 -> gemini, groq, groq, cerebras
pedido 2 -> groq, cerebras, gemini, groq      pedido 5 -> groq, groq, cerebras, gemini
pedido 3 -> cerebras, gemini, groq, groq      (raciocínio: igual nos 3 pedidos — não roda)
```

### Prova 4 repetida (20 mensagens em 2 minutos, 5 números de prova)
```
             02/09 (cadeia)      04/09 (rodízio)
mediana        2,0 s               2,3 s
p95           19,5 s               6,0 s
máximo        19,6 s               6,9 s
acima de 5 s   5                   3
```
Coluna `modelo` no banco, uma linha por resposta (`whatsapp_messages`, números 351 90* *** 40x):
```
06:15:12 401 groq:openai/gpt-oss-120b       3500 ms  O Bora é uma app de entregas e serviços locais…
06:15:17 402 facto-fixo                     2000 ms  Olá! Funcionamos todos os dias, incluindo domingos…
06:15:23 403 groq:qwen/qwen3.8-27b          2800 ms  Pomos a sua loja na app, os clientes da Guarda…
06:15:32 404 gemini:gemini-3.1-flash-lite   5600 ms  Para avançarmos com o seu processo de integração…
06:15:39 405 gemini:gemini-3-flash-preview  6500 ms  Sim, podes pagar em dinheiro até 40 € por pedido…
06:15:40 401 groq:openai/gpt-oss-120b       1500 ms  Sim, fazemos entregas de farmácia…
06:16:09 401 facto-fixo                      500 ms  O Bora não tem horário próprio…
06:16:51 403 facto-fixo                      500 ms  App para iPhone não temos. No iPhone é pela web…
```
Distribuição (o rodízio a espalhar): `groq:qwen3.8` 4 · `groq:gpt-oss-120b` 4 ·
`gemini-3-flash-preview` 3 · `gemini-3.1-flash-lite` 3 · `facto-fixo` 3 · `cumprimento-fixo` 1.
Nenhum 429 chegou ao cliente. As 3 acima de 5 s são as do Gemini; fecham quando o Cerebras e o
OpenRouter tiverem chave (esperam o clique do Danilo).

## 5. Vigia de modelo descontinuado

404/410 ou mensagem de "não existe/descontinuado" **duas vezes** → o modelo sai da lista de todos os
perfis, fica em `retirados` (persistido), o Danilo é avisado e a linha entra no `MOTORES.md`. Um 404
pontual não chega, para não apagar um modelo por um soluço. Teste: 1.ª vez `retirado=False`, 2.ª
`retirado=True`. **Caso real hoje:** o GitHub Models devolve `410 github_models_retirement_brownout`
— *"GitHub Models is temporarily unavailable as part of a scheduled retirement brownout"*. O token
está guardado, mas o fornecedor está a ser desligado pela própria GitHub.

## 6. Custo simulado

Não se paga nada; é o que isto custaria ao preço de tabela do modelo pago equivalente
(`catalogo.PRECO_POR_MILHAO`, € por milhão de tokens). Está no `/motores`, no `MOTORES.md` e no ecrã
admin. Estado às 06:20 de hoje: **0,0098 € no dia inteiro** (groq 0,0087 · gemini 0,0008 · kilo 0,0003).

## 7. Gemini — o WhatsApp deixou de partilhar a quota com o juiz

A chave que o cérebro usava (`…FfBA`) é a **mesma do juiz e do backend**, no projeto `bora-juiz`, e a
quota grátis do Gemini é **por projeto**: uma rajada do WhatsApp deixava o juiz sem nada, e ao
contrário. Passei o WhatsApp para uma chave que estava parada no outro projeto (`…fjRA`, Default
Gemini Project). O juiz e o backend ficaram com a FfBA. Provado: `GEMINI-NOVO-OK` em 1,9 s.

## 8. Ollama Cloud

Entrou no catálogo como `ollama-cloud` (`https://ollama.com/v1`, chave `OLLAMA_API_KEY`), ao lado do
Ollama local. Sem chave ainda — salta em 0 ms.

## 9. Estado dos fornecedores (06:20 de 04/09)

| fornecedor | estado |
|---|---|
| groq | a trabalhar (9 pedidos hoje, 9 ok) |
| gemini | a trabalhar, agora em projeto próprio (8/8) |
| kilo | **a trabalhar sem chave nenhuma** (4 pedidos, 3 ok) |
| github | token guardado, mas a GitHub está a desligar o serviço (410) |
| zen, ollama, ovh, llm7 | reserva |
| cerebras, openrouter, nvidia, mistral, sambanova, cloudflare | à espera do clique do Danilo (criação de conta) |

**Não foram criadas contas múltiplas em nenhum fornecedor** — o risco de banir a conta principal do
Bora não compensa o que se ganharia.

---

# Segunda volta (06:30–07:00) — as duas colunas que faltavam no banco

O Danilo apanhou duas coisas: `entrega_estado` vazio em todas as saídas do dia, e o Kilo sem uma única
resposta real. Ambas verdadeiras. Aqui está a causa de cada uma e a prova com linhas reais.

## Porque é que `entrega_estado` estava vazio

Duas razões, e a segunda é grave:
1. **Todas as saídas do dia eram `porta='prova'`.** O `/prova` decide e regista, mas nunca põe nada na
   fila de saída — logo nunca há `/enviado` e a coluna fica vazia. É o comportamento certo para um
   teste, mas significa que eu nunca tinha provado o caminho de SUCESSO, só o de falha (02/09).
2. **A porta estava muda desde as 05:30:07.** O separador do WhatsApp Web fechou-se quando abri os 8
   separadores dos fornecedores, e o *content script* morre com ele. O cérebro continuou a decidir; a
   fila continuou a encher; ninguém a foi buscar. É o mesmo buraco da falha F visto do outro lado.

**Correcção:** o cérebro passou a vigiar a própria porta (`porta_muda`): se há mensagens na fila e
ninguém pede `/pendentes` há mais de 90 s, marca as linhas com `entrega_estado='porta-muda'`, avisa o
Danilo no Telegram e passa-as à VPS se ela estiver emparelhada. **Segunda tentativa:** uma entrega que
falha volta UMA vez à fila 30 s depois, antes de se desistir.

## As linhas reais (número de teste do Danilo, porta `pc-extensao`)

```
id   hora      modelo                                    ms  enviada  entrega   tent
467  06:35:32  groq:qwen/qwen3.8-27b                   2000  true     visto     2
469  06:35:49  gemini:gemini-3.1-flash-lite            2900  true     visto     1
471  06:36:11  kilo:stepfun/step-3.7-flash:free        7700  true     visto     1
473  06:36:27  kilo:dots-studio/dots-3-note-preview    5800  true     visto     1
477  06:36:40  groq:openai/gpt-oss-120b                2900  true     visto     1
479  06:36:55  groq:qwen/qwen3.8-27b                   1900  true     visto     1
481  06:39:18  gemini:gemini-3.1-flash-lite            3300  false    falhou    3   <- corrigida, ver abaixo
483  06:39:39  kilo:stepfun/step-3.7-flash:free        8000  true     visto     1
485  06:39:49  facto-fixo                              1100  true     visto     1
487  06:42:50  groq:openai/gpt-oss-120b               11700  true     visto     1
489  06:42:57  groq:openai/gpt-oss-120b                1800  true     visto     1
491  06:43:15  groq:openai/gpt-oss-120b                1800  false    falhou    3   <- reenviada
493  06:43:32  groq:qwen/qwen3.8-27b                   1500  true     visto     1
494  06:43:54  reenvio                                    —  true     visto     1   <- a 491 entregue à segunda
```
Resumo do banco: **15 saídas reais, todas com `entrega_estado` preenchido** — 13 `visto`, 2 `falhou`
(uma delas entregue à segunda). **4 servidas pelo Kilo**, todas entregues.

## Porque é que o Kilo não servia nada

O Kilo estava no fim da lista e o rodízio só rodava os 4 primeiros — nunca lá chegava. Subiu para o
topo do catálogo e o rodízio passou a 6. Havia ainda uma armadilha: **a ordem guardada pelo auto-teste
esmagava a posição nova do catálogo**, por isso um candidato novo ficava sempre no fim. Agora o estado
guarda a assinatura da lista do catálogo: se o catálogo mudar, a ordem guardada é deitada fora nesse
perfil e o auto-teste da noite re-ordena.

## Dois erros meus, apanhados nesta volta

1. **Raciocínio cru enviado a um cliente.** Eu tinha posto o roteador a ler `reasoning_content` quando
   o `content` vinha vazio. Resultado: a linha 475 mandou *"The user wants to be an estafeta
   (courier/delivery)…"* para o WhatsApp do Danilo. Tirei essa leitura (campo vazio = falha, passa ao
   motor seguinte) e pus uma trava no cérebro (`_parece_raciocinio`) que bloqueia qualquer resposta que
   comece a falar do utilizador na terceira pessoa ou que seja claramente inglês. 7 de 7 em teste.
2. **Vagas de estafeta inventadas.** A linha 481 dizia *"Sim, temos vagas abertas"* — a regra é que
   **não há vagas**, é lista de espera. Trava nova (`RE_DIZ_QUE_HA_VAGAS`): se a pergunta é sobre ser
   estafeta e a resposta promete vaga, sai o texto certo. Provado ao vivo: o modelo escreveu "Ainda
   temos vagas" e o que chegou ao WhatsApp foi *"De momento não há vagas para estafeta…"* (linha 487).

---

# Terceira volta (07:00–07:45) — a folha de verdades

## Os seis cliques: só um estava mesmo feito

Fui aos seis separadores e recarreguei cada um na página de chaves (se a conta estivesse criada, a
sessão é partilhada e a página abre). Estado real:

| fornecedor | estado verificado |
|---|---|
| **Mistral** | **conta pronta** → chave criada, gravada no PC e na VPS, a responder em 0,4–0,5 s |
| Cloudflare | sessão iniciada, mas sem token; a página de criar token não abre (SPA fica presa) |
| Cerebras | continua em "Enter details → Continue" |
| OpenRouter | continua em "How will you be using OpenRouter? → Next" |
| NVIDIA | continua em "Create an NVIDIA Cloud Account" |
| SambaNova | continua no formulário de perfil (nome, função, empresa) |

O `mistral-small-latest` não existe neste plano; ficou o `ministral-8b-latest` (0,5 s, PT-PT correcto).
O Mistral fica marcado `sensivel_ok: False` — o plano grátis treina com os dados, por isso **nunca**
serve conversas de clientes, só os perfis `raciocínio` e `volume`.

## A folha de verdades (`cerebro/verdades.py`)

Uma folha única: 21 serviços com **SIM** ou **NÃO** ao lado, e 10 factos. Vai inteira em **todas** as
chamadas ao modelo (é a primeira coisa que ele lê) **e** é verificada à saída, dentro de
`_pos_processar` — por onde passam todos os caminhos (facto fixo, fio, rápido, escalar). Não são
travas caso a caso: é uma porta só, no fim.

O que a porta faz, por ordem:
1. **Nome do dono** — se a resposta trouxer "Danilo", "dono", "patrão", "chefe", "fundador" ou
   "proprietário", a resposta **inteira** é trocada (não se remenda a frase, que dava frankensteins).
   Se a pergunta era sobre quem manda: *"Sou o atendimento do Bora e é comigo que trata."*
2. **Negou um serviço que a folha diz SIM** → sai o texto certo da folha.
3. **Afirmou um serviço que a folha diz NÃO** → sai o texto certo da folha.
4. **Negou algo que não está na folha** → *"Vou confirmar isso com o meu superior e volto já com a
   resposta."* + tarefa de 30 minutos + a vigia atrás dela + aviso no Telegram.

**Urgência** (pedido a decorrer, dinheiro, cobrança errada, reembolso): não se manda esperar. Sai
*"ligue-nos para +351 937 501 673"* numa frase curta, e o Telegram sai ao mesmo tempo.

## Prova 1 — 30 perguntas de sim ou não contra a folha

**28 de 30**, e **0 respostas com o nome do dono**. As duas que a régua marcou como falha:
- *"Fazem entregas na Covilhã?"* → *"Não, só fazemos entregas na Guarda e arredores, até 15 km."* —
  a resposta está certa; foi o meu classificador que leu "fazemos" como um sim.
- *"Entregam em Lisboa?"* → saiu *"Vou confirmar com o meu superior"* em vez do não directo. Não é
  mentira nem fuga, é a porta a ser conservadora.

Antes desta volta eram 26/30: a resposta *"Não, o Bora não vende seguros de carro"* passava, porque o
padrão de negação não apanhava "não vende". Passou a apanhar também qualquer resposta que **comece**
por "Não".

## Prova 2 — as três ao vivo, entregues no WhatsApp

```
id   hora      entrega  modelo                    resposta
628  07:41:32  visto    groq:qwen/qwen3.8-27b     Vou confirmar isso com o meu superior e volto já com a resposta.
630  07:41:51  visto    (escalar)                 Recebi. Isto é de valores, e resolve-se mais depressa ao telefone:
                                                  ligue-nos para +351 937 501 673. Já avisei a equipa também.
632  07:42:19  visto    kilo:stepfun/step-3.7...  Sou o atendimento do Bora e estou aqui para resolver o que precisar.
                                                  Pode dizer-me qual é a questão para eu ajudar já?
```
- A) serviço fora da folha ("mudanças de casa com camião") → a frase do superior, com tarefa aberta.
- B) dinheiro ("fui cobrado duas vezes") → manda ligar para a loja, e o Telegram saiu ao mesmo tempo.
- C) quem é o dono → não diz o nome, fecha o assunto. **Servida pelo Kilo**, entregue.

**Zero respostas com o nome do dono** em todas as provas desta volta.

## Uma limitação real que encontrei

O envio precisa que o separador do WhatsApp Web esteja **visível** na sua janela. Com ele em segundo
plano, o Chrome trava o desenho da página e o "abrir a conversa" falha ("não consegui abrir a
conversa"). Pus o WhatsApp Web numa **janela só dele** — assim continua visível mesmo quando o Danilo
usa outra janela. Enquanto isso não estava assim, a vigia da porta e o reenvio fizeram o seu papel:
marcaram `falhou`, avisaram, e a segunda tentativa entregou.
