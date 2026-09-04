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
