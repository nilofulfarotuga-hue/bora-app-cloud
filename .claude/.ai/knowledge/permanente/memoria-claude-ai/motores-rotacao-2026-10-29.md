---
id: memoria-claude-ai-motores-rotacao-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Motores gratis em rotacao - medicoes e cadeias (29/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `motores-rotacao-2026-10-29`, origem `claude-code`, atualizada em 2026-10-29T19:29:26.128732+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: motores rotacao 2026 10 29 · memoria claude.ai · claude_ai_memoria

# Motores grátis em rotação — medição de 29/10/2026 (19:10 a 19:25 UTC)

Âmbito (mudança das 19:xx): só medir e recomendar. NÃO foi editado nenhum ficheiro da VPS, não se reiniciou nada, não se escreveu em nenhuma tabela. Só leituras (SELECT, GET, ficheiros) e chamadas diretas aos motores. Os scripts correram por stdin (`ssh ... python3 - < script`), sem gravar nada na VPS.
Única sobra: `/root/inv_tenants.sh` (criei-o ANTES da mudança de âmbito, só lê a tabela de tenants; não tem chaves; pode apagar-se).

A prova foi igual para todos: contexto de restaurante (entrega 2,50 € até 4 km, +0,50 €/km a seguir, dinheiro até 40 €), 3 mensagens, e um 4.º teste de chamada de ferramenta.
- M1 "Boa tarde! Quanto custa a entrega até 4 km?" -> certo = 2,50 €
- M2 "E se for a 6 km, quanto fica?" -> certo = 3,50 €
- M3 "Quanto custa o hambúrguer Smash Duplo?" -> certo = NÃO inventar preço (dizer que confirma)
- F  pedido de menu com ferramenta `ver_menu` -> tem de devolver `tool_calls`
Medido da VPS, 2 a 3 motores de cada vez em paralelo (fornecedores diferentes). Corte: 30 s. 401/402/403/429 = anota e não insiste.

## 1. Descobertas que mudam a decisão (ler primeiro)

1. Quota diária do Gemini grátis é 20 pedidos por modelo e por projeto. Lido no corpo do 429: `GenerateRequestsPerDayPerProjectPerModel-FreeTier`, `quotaValue 20`, `retryDelay 42225 s` (volta por volta das 07:00 UTC de amanhã). Já esgotados hoje: `gemini-3-flash-preview` (o principal do Boom!) e `gemini-3.8-flash`; `gemini-3.5-flash` e `3.7-flash` também deram 429 de quota. A chave `GEMINI_API_KEY` do assistente tem o mesmo hash que a do cérebro do `whatsapp-bora` (fa9937e0): é o MESMO projeto Google, a quota é partilhada. Cada mensagem de cliente gasta 1 pedido na classificação + 1 a 3 no turno (pedidos reais: 4 000 a 7 000 tokens de entrada).
2. `gemini2` (GEMINI_API_KEY_2) confirmado morto: HTTP 402 "prepayment credits are depleted". O mesmo valor (hash 09493523) está em `/opt/data/.env` como GEMINI_API_KEY e GOOGLE_API_KEY, ou seja é a chave do Hermes/OmniRoute. Nos logs do OmniRoute as contas Gemini estão em cooldown com `lastErrorCode=402` ("out of credits"), por isso os combos `agentes` e `privado` do Hermes demoram 7 s e 15 s.
3. Modelos grátis do OpenCode Zen: NÃO funcionam por API. Os 9 devolvem 429 `FreeUsageLimitError` "Free models work in OpenCode ... subscribe to OpenCode Go" (da VPS e também do PC, com a chave pública `public`). A chave OPENCODE_ZEN_API_KEY da VPS também expirou (401 api_key_expired). Só funcionam dentro do programa `opencode` (CLI do PC, v1.18.30): 8 modelos medidos abaixo, todos certos, mas 12 a 25 s cada, em série (2 em paralelo deu `database is locked`) e o CLI não está instalado na VPS. Não servem para o robô do WhatsApp ao vivo.
4. Ollama: não existe na VPS (sem binário, nada na porta 11434, sem contentor). Não é opção.
5. O `/v1/models` do OmniRoute dá 503 `catalog_build_timeout` (o `/api/health` dá 200 e as chamadas de chat funcionam).

## 2. Tabela de medição (3 mensagens + ferramenta)

| Motor | Tempo médio | Certo em 3 | Ferramenta | Mantido | Porquê |
|---|---|---|---|---|---|
| gemini:gemini-3-flash-preview | 2 496 ms (2 pedidos) | 2/2, depois 429 | n/t (quota) | SIM, só como bónus | 20 pedidos/dia, esgotado hoje até ~07:00 UTC; bom quando há quota |
| gemini:gemini-3.1-flash-lite | 1 440 ms | 3/3 | sim (1 timeout de 31 s, depois 972 e 999 ms) | SIM | rápido, sem 429 até agora; quota diária por medir |
| gemini:gemini-3.5-flash-lite | 3 765 ms (1.º pedido 6,2 s) | 3/3 | sim (1,2 s) | SIM (reserva) | certo mas mais lento |
| gemini:gemini-3.5-flash | 5 715 ms (1 pedido) | 1/1, depois 429 | n/t | NÃO | 429 de quota |
| gemini:gemini-3.6-flash | 1 874 ms (só no reteste) | 503 e 429 no lote; 200 no reteste | n/t | NÃO | instável hoje |
| gemini:gemini-3.7-flash | timeout 30 s, depois 429 | 0/3 | n/t | NÃO | timeout + 429 |
| gemini:gemini-3.8-flash | 298 ms (só o 429) | 0/3 | n/t | NÃO | 20/dia esgotado |
| gemini2:* (GEMINI_API_KEY_2) | 375 ms (só o erro) | 0/3 | n/t | NÃO | 402 sem créditos, não se compra |
| groq:openai/gpt-oss-120b | 796 ms | 3/3 | sim | SIM | rápido e certo; limite 8 000 tokens/min/modelo |
| groq:qwen/qwen3.8-27b | 729 ms | 3/3 | sim | SIM | idem |
| groq:openai/gpt-oss-20b | 667 ms | 3/3 | sim | SIM (último / classificador) | o mais pequeno |
| cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast | 1 226 ms | 3/3 | sim | SIM, mas precisa de código | exige fornecedor novo no motores.py (URL leva o account id) |
| cloudflare:@cf/zai-org/glm-4.7-flash | 10 159 ms | 3/3 | sim | NÃO | lento |
| openrouter:nvidia/nemotron-3-ultra-550b-a55b:free | 4 697 ms (máx 9,2 s) | 3/3 | sim | SIM, última reserva, precisa de código | exige OPENROUTER_API_KEY no .env do assistente; hoje 4 falhas em 7 no Motor Bora |
| ovh anónimo gpt-oss-120b | 3 149 ms | 2/2, depois 429 | n/t | NÃO | 429 (anónimo por IP) |
| zen-free:* (9 modelos, via API) | n/a | 0/9 | n/t | NÃO | 429 FreeUsageLimitError |
| motor-bora perfil:chat-rapido | 333 ms (respondeu groq:qwen) | 3/3 | sim | alternativa | agregador local 127.0.0.1:8792 |
| motor-bora perfil:raciocinio | 1 728 ms (respondeu gemini-3.5-flash-lite) | 3/3 | sim | alternativa | tem go: na lista (castigado 6 h por 401) |
| motor-bora perfil:volume | 1 107 ms (respondeu cloudflare llama) | 3/3 | NÃO | não para o robô | não devolveu tool_calls |
| omniroute combo rapido | 1 368 ms (groq qwen) | 3/3 | sim | alternativa | |
| omniroute combo agentes | 7 066 ms (nemotron) | 3/3 | sim | NÃO | gemini em 402/cooldown |
| omniroute combo privado | 14 694 ms (cloudflare glm) | 3/3 | sim | NÃO | lento |
| opencode CLI big-pickle | ~14 000 ms | 3/3 | n/t | só lote | CLI do PC; ver nota |
| opencode CLI glm-5.3-flash-free | 16 512 ms | 3/3 | n/t | só lote | |
| opencode CLI deepseek-v4.1-flash-free | 12 346 ms | 3/3 | n/t | só lote | |
| opencode CLI nemotron-3.5-super-vl-free | 13 065 ms | 3/3 | n/t | só lote | |
| opencode CLI beam-free | 14 689 ms | 3/3 | n/t | só lote | |
| opencode CLI nemotron-3.5-lightning-free | 17 373 ms | 3/3 | n/t | NÃO | resposta vaga ("Aguarde um momento") |
| opencode CLI flint-40b-free | 23 513 ms | 3/3 | n/t | NÃO | lento, erro de escrita ("confirmir") |
| opencode CLI mimo-v2.6-flash-free | 25 041 ms (máx 31,9 s) | 3/3 | n/t | NÃO | passa dos 30 s |
| ollama (local e cloud), cerebras, github, mistral, nvidia, sambanova, cohere, zhipu, kilo, llm7 | n/t | n/t | n/t | NÃO | sem binário / 402 PayGo / 410 / sem chave / treina com dados / decisão do Danilo de 04/09 / pouco fiáveis (ver MOTORES.md do Motor Bora) |

Notas da tabela:
- Nas linhas do OpenCode CLI a minha regra automática marcou "inventou preço" por ver "2,50 €" nas respostas; li uma a uma e NENHUMA inventou o preço do hambúrguer (todas dizem que vão confirmar). Corrigi à mão: todos 3/3. O `big-pickle` teve um `database is locked` por correr em paralelo; o teste isolado deu 15,0 s e certo.
- OpenCode CLI e privacidade: pelo que sei, os modelos grátis do Zen podem usar os pedidos para melhorar o modelo (NÃO confirmei nesta sessão). O Gemini grátis também. A regra 14 do AGENTS.md diz que dados de clientes não vão para motores grátis que treinam. O Boom já corre em Gemini grátis, por isso a decisão é do Danilo; para os modelos do Zen é razão extra para ficarem fora do robô.
- Classificador (prompt real do restaurante, 3 casos): groq gpt-oss-20b 3/3 em 291 ms; groq qwen3.8-27b 3/3 em 261 ms; groq gpt-oss-120b 3/3 em 232 ms; gemini-3.1-flash-lite 3/3 em 1 266 ms; gemini-3.5-flash-lite 3/3 em 1 474 ms.
- Não corri o fluxo real do robô (simular_boom.py escreve ficheiro e linhas na base; não era para tocar). São chamadas diretas aos motores. Depois de aplicar, convém correr o simular_boom.

## 3. Inventário e cadeias: ANTES -> RECOMENDADA (onde se muda)

### 3.1 assistente-negocio (robô do WhatsApp) — cadeias por tenant
Onde: tabela `public.assistant_tenants`, colunas `motor` e `motores_reserva` (a lógica que as junta está em `/opt/assistente-negocio/assistente.py:544-546`, função `cadeia_de`; usada em `assistente.py:568` (resposta do dono) e `assistente.py:694` (turno principal, com ferramentas)). Não é preciso mexer no código para isto, só na tabela.

Boom! Burger (slug `boom-burger`, id 74c7ff0a-654e-446c-8574-f2acd31a4c12, mode teste)
- ANTES: gemini:gemini-3-flash-preview, gemini2:gemini-3-flash-preview (402), go:glm-5.2 (401), gemini:gemini-3.1-flash-lite, gemini2:gemini-3.1-flash-lite (402), groq:openai/gpt-oss-120b, groq:qwen/qwen3.8-27b
- DEPOIS (melhor para pior, só grátis):
  1. gemini:gemini-3-flash-preview   (melhor qualidade; 20 pedidos/dia; hoje esgotado, volta ~07:00 UTC; salta sozinho)
  2. gemini:gemini-3.1-flash-lite    (1,4 s)
  3. groq:openai/gpt-oss-120b        (0,8 s)
  4. gemini:gemini-3.5-flash-lite    (3,8 s)
  5. groq:qwen/qwen3.8-27b           (0,7 s)
  6. groq:openai/gpt-oss-20b         (0,7 s)
  Opcionais, só com código novo em motores.py: cloudflare llama-3.3-70b (1,2 s) entre o 4 e o 5; openrouter nemotron-ultra:free no fim.

Bora Secretário Virtual demo (slug `secretario-demo`, id f711f30c-92de-4ff8-a1e2-872d11cd4547, mode teste)
- ANTES: gemini:gemini-3-flash-preview, gemini2:gemini-3-flash-preview, gemini:gemini-3.1-flash-lite, gemini2:gemini-3.1-flash-lite, groq:openai/gpt-oss-120b, groq:qwen/qwen3.8-27b
- DEPOIS: a mesma lista do Boom.

Barbearia Mister Navalha (slug `mister-navalha`, id 9c4bad37-f335-434c-8bf8-c6a47f638dec, mode desligado)
- ANTES: go:glm-5.2, go:qwen3.8-max, gemini:gemini-3-flash-preview, gemini2:gemini-3-flash-preview, gemini:gemini-3.1-flash-lite, gemini2:gemini-3.1-flash-lite, groq:openai/gpt-oss-120b, groq:qwen/qwen3.8-27b
- DEPOIS: a mesma lista do Boom (está desligada, mas fica pronta).

SQL (exemplo, NÃO executado; confirmar se `motores_reserva` é jsonb ou text[]):
```sql
update public.assistant_tenants
   set motor = 'gemini:gemini-3-flash-preview',
       motores_reserva = '["gemini:gemini-3.1-flash-lite","groq:openai/gpt-oss-120b","gemini:gemini-3.5-flash-lite","groq:qwen/qwen3.8-27b","groq:openai/gpt-oss-20b"]'::jsonb
 where slug in ('boom-burger','secretario-demo','mister-navalha');
```

### 3.2 assistente-negocio — classificador (negócio ou pessoal) — cadeia fixa no código
Onde: `/opt/assistente-negocio/assistente.py:530-531` (função `classificar`).
- ANTES: gemini:gemini-3.1-flash-lite, gemini2:gemini-3.1-flash-lite (402), groq:openai/gpt-oss-20b, groq:qwen/qwen3.8-27b
- DEPOIS: groq:openai/gpt-oss-20b, groq:qwen/qwen3.8-27b, groq:openai/gpt-oss-120b, gemini:gemini-3.1-flash-lite
- Porquê: corre em TODAS as mensagens; com o Gemini à frente gasta 1 dos 20 pedidos diários de cada vez. Groq acerta 3/3 em ~0,26 s (prompt pequeno, sem problema de limite por minuto).

### 3.3 assistente-negocio — código dos motores (sugestões para quem aplica)
Ficheiro `/opt/assistente-negocio/motores.py`:
- linha 79 `timeout=45` e linhas 145-153 (repetição em timeout): num motor que fica pendurado o cliente espera até ~90 s. Medi dois timeouts de 30 s hoje (gemini-3.7-flash e um pedido do 3.1-flash-lite). Sugestão: 20 s e sem repetir em timeout.
- linhas 47-58 `_castigar`: não trata 401 nem 402, por isso `go:` e `gemini2:` são tentados e falham em TODAS as mensagens. Tirando-os das cadeias o problema desaparece; se ficarem no dicionário `FORNECEDORES` (linhas 20-31; go na 23, gemini2 na 28) não fazem mal.
- Para usar cloudflare/openrouter: acrescentar entradas em FORNECEDORES (cloudflare precisa do `CLOUDFLARE_ACCOUNT_ID` no URL e de `CLOUDFLARE_API_TOKEN`; openrouter de `OPENROUTER_API_KEY`) e as chaves no `/opt/assistente-negocio/.env`. As chaves já existem em `/opt/motor-bora/.env` e `/opt/data/.env`.
- Alternativa sem código novo para o fim da lista: Motor Bora `http://127.0.0.1:8792/v1/chat/completions` com modelo `perfil:chat-rapido` (333 ms, tools sim), mas o motores.py exige uma variável de chave; é preciso um fornecedor novo com chave fictícia.

### 3.4 Outros automáticos que chamam IA
| Automático | Onde está a cadeia | Estado | Recomendação |
|---|---|---|---|
| Motor Bora (roteador, porta 8792; usado pelo Hermes, cérebro do whatsapp-bora, carteiro_caca, radar_freelas) | `/opt/motor-bora/motor_bora/catalogo.py`: `PERFIS` (linha 78). `go` nas linhas 102 e 108 (perfil raciocinio); `zen` nas linhas 99 (chat-rapido), 106 (raciocinio) e 113 (volume); `ollama` na 99 e fim dos outros | go: 401 (castigo 6 h, inofensivo); zen via API: 429 (castigo 65 s, repete); ollama: recusa ligação | tirar go e zen e ollama dos candidatos; reiniciar `motor-bora` afeta o WhatsApp da Bora e o Hermes, por isso decisão tua. A ordem viva é reordenada às 05:30 pelo autoteste e guardada em `_estado.json` |
| Hermes (Telegram): modelo principal | `/opt/data/config.yaml:386-389` -> `default: agentes`, OmniRoute `http://omniroute:20128/v1` | funciona mas lento (7 s) porque o Gemini do OmniRoute dá 402 | trocar o modelo para o combo `rapido` (1,4 s) ou para o Motor Bora `perfil:raciocinio` (1,7 s) |
| Hermes: cadeia de reserva | `/opt/data/config.yaml:312-325` `fallback_providers`: opencode-go glm-5.2 e qwen3.8-max (linhas 312-315), gemini-3.6-flash (316-317), opencode-zen x4 (318-325) | go e zen estão mortos (401 / só dentro do OpenCode) | substituir por groq gpt-oss-120b + Motor Bora (sintaxe de provider custom a confirmar no Hermes). Perfis `escriba` e `fiscal`: `/opt/data/profiles/<perfil>/config.yaml:306-316` (opencode-zen x4 + gemini-3.6-flash). Reinício: o gateway só lê o config ao arrancar; há `/opt/omniroute/relancar_gateway.sh`. Não reiniciei: pode parar o Telegram |
| Hermes: 25 perfis | `/opt/data/profiles/*/config.yaml:1-4`: 19 usam `perfil:raciocinio` no Motor Bora (172.16.1.1:8792); `batedor`, `critico` e `vendedor` usam `agentes` e `torre` usa `privado` (OmniRoute); `escriba` e `fiscal` não têm bloco de modelo nas 6 primeiras linhas | os 4 de OmniRoute ficam lentos (7 a 15 s) | ver combos abaixo |
| OmniRoute combos | `/opt/omniroute/or_combos.py`: `agentes` (linhas 15-33; gemini/3.6 na 21 e 3.7 na 22, groq 27-28, cloudflare glm 29, gemini 3.1-lite 30), `privado` (34-45), `rapido` (46-56), `volume` (57-66), `visao` (67-77). O ficheiro é aplicado por PUT em /api/combos | OpenCode Go já saiu de todos; Gemini em 402/cooldown à frente de `agentes`/`privado` | pôr groq/openai/gpt-oss-120b e groq/qwen/qwen3.8-27b à frente do Gemini em `agentes` e `privado`; `rapido` já está bom |
| Rotinas Hermes (`/opt/data/rotinas`) | `despachante.py:74-76,221-257` e `emerson.py:255-259` pedem `perfil:raciocinio` ao OmniRoute (MAPAS linha 90 -> `agentes`) com Motor Bora de reserva; `carteiro_caca.py:67` e `radar_freelas.py:67` usam `perfil:volume` | herdam a lentidão do `agentes` | resolve-se nos combos; `cadeia_prova.py:17-22` é só um script de teste que ainda lista go/zen |
| Cérebro do WhatsApp da Bora (`/opt/whatsapp-bora/cerebro`) | primeiro pergunta ao Motor Bora (`modelos.py:227-258`); a cadeia direta de reserva é a linha única de `/opt/whatsapp-bora/cerebro/cadeia.txt` | `groq:openai/gpt-oss-120b,groq:qwen/qwen3.8-27b,gemini-3.1-flash-lite,gemini-3-flash-preview,ollama,zen:nemotron-3-ultra-free` | tirar `ollama` e `zen:nemotron-3-ultra-free` (mortos). Partilha a quota do Gemini com o robô do Boom |
| Voz (`/opt/assistente-negocio/voz.py:73-74`) | groq whisper-large-v3-turbo, depois faster-whisper local | já grátis | nada a mudar |
| Edge Function `decidir` (Supabase) | `decidir/index.ts`: constante `GEMINI_MODELOS`, valor por omissão `gemini-3.6-flash,gemini-3.5-flash-lite,gemini-3.1-flash-lite`, substituível pelo segredo `DECISOR_GEMINI_MODELS`; chave no segredo `GEMINI_API_KEY` da função | NÃO mexi (ordem). Está em sombra: se o Gemini falhar cai na regra determinística (motor='fallback'), sem dano | só reportar: se aquela chave for a paga/402, as decisões saem como fallback |
| Mistral | não usado nas cadeias do assistente | n/a | continua proibido para conversas |

## 4. Por fazer / bloqueado
- Aplicar as cadeias (tabela e assistente.py:530-531) e reiniciar o `assistente-negocio`: é contigo. Depois correr o `simular_boom.py` e ver o motor usado por resposta (não o fiz, por ordem).
- Quota do Gemini: mesmo rodando 3 modelos Gemini + 3 Groq, o robô aguenta poucas dezenas de conversas por dia grátis. Se o Boom tiver tráfego a sério, o gargalo é a quota (Gemini 20/dia/modelo; Groq 8 000 tokens/minuto/modelo com pedidos de 4 000 a 7 000 tokens, ou seja ~1 pedido por minuto e modelo). Cloudflare (10 000 neurónios/dia) e OpenRouter somam folga mas pedem código.
- Os 20 pedidos/dia do `gemini-3.1-flash-lite`, `3.5-flash-lite` e `3.6-flash` não foram lidos (ainda não deram 429). Só se sabe ao esgotarem.
- OpenCode grátis fora do robô: só valeria para tarefas em lote, a instalar `opencode` na VPS (npm existe) e a provar de lá (o IP da VPS pode ter o mesmo limite). Não fiz (proibido editar a VPS).
- Edge Function `decidir`: ver 3.4.
- Falta decidir (Danilo): usar Gemini grátis com conversas de clientes (a regra 14 do AGENTS.md diz que dados de clientes não vão para motores grátis que treinam).

## 5. Saída literal das medições (anexo)

### 5.1 Linhas RESULT (VPS, chamadas diretas)
```
RESULT gemini:gemini-3-flash-preview | certo 2/3 | media 2496 ms | max 2696 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) model=gemini-3-flash-preview
RESULT gemini:gemini-3.1-flash-lite | certo 3/3 | media 1440 ms | max 1703 ms | ferramenta=nao |  model=gemini-3.1-flash-lite
RESULT gemini:gemini-3.5-flash-lite | certo 3/3 | media 3765 ms | max 6227 ms | ferramenta=sim |  model=gemini-3.5-flash-lite
RESULT gemini:gemini-3.5-flash | certo 1/3 | media 5715 ms | max 5715 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) model=gemini-3.5-flash
RESULT gemini:gemini-3.6-flash | certo 0/3 | media -1 ms | max 999 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT gemini:gemini-3.7-flash | certo 0/3 | media -1 ms | max 30098 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT gemini:gemini-3.8-flash | certo 0/3 | media -1 ms | max 298 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT groq:openai/gpt-oss-120b | certo 3/3 | media 796 ms | max 1492 ms | ferramenta=sim |  model=openai/gpt-oss-120b
RESULT groq:openai/gpt-oss-20b | certo 3/3 | media 667 ms | max 1491 ms | ferramenta=sim |  model=openai/gpt-oss-20b
RESULT groq:qwen/qwen3.8-27b | certo 3/3 | media 729 ms | max 1888 ms | ferramenta=sim |  model=qwen/qwen3.8-27b
RESULT omniroute:rapido | certo 3/3 | media 1368 ms | max 1815 ms | ferramenta=sim |  model=qwen/qwen3.8-27b
RESULT omniroute:agentes | certo 3/3 | media 7066 ms | max 11194 ms | ferramenta=sim |  model=nvidia/nemotron-3-ultra-550b-a55b
RESULT omniroute:privado | certo 3/3 | media 14694 ms | max 16707 ms | ferramenta=sim |  model=@cf/zai-org/glm-4.7-flash
RESULT motor-bora:perfil:chat-rapido | certo 3/3 | media 333 ms | max 512 ms | ferramenta=sim |  model=groq:qwen/qwen3.8-27b
RESULT motor-bora:perfil:raciocinio | certo 3/3 | media 1728 ms | max 1891 ms | ferramenta=sim |  model=gemini:gemini-3.5-flash-lite
RESULT motor-bora:perfil:volume | certo 3/3 | media 1107 ms | max 1689 ms | ferramenta=nao |  model=cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast
RESULT cloudflare:@cf/zai-org/glm-4.7-flash | certo 3/3 | media 10159 ms | max 10716 ms | ferramenta=sim |  model=@cf/zai-org/glm-4.7-flash
RESULT cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast | certo 3/3 | media 1226 ms | max 1682 ms | ferramenta=sim |  model=@cf/meta/llama-3.3-70b-instruct-fp8-fast
RESULT openrouter:nvidia/nemotron-3-ultra-550b-a55b:free | certo 3/3 | media 4697 ms | max 9209 ms | ferramenta=sim |  model=nvidia/nemotron-3-ultra-550b-a55b:free provider=Nvidia
RESULT ovh-anonimo:gpt-oss-120b | certo 2/3 | media 3149 ms | max 3794 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) model=gpt-oss-120b
RESULT zen-free:big-pickle | certo 0/3 | media -1 ms | max 1399 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT zen-free:beam-free | certo 0/3 | media -1 ms | max 1400 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT zen-free:flint-40b-free | certo 0/3 | media -1 ms | max 1172 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT zen-free:mimo-v2.6-flash-free | certo 0/3 | media -1 ms | max 617 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT zen-free:nemotron-3.5-super-vl-free | certo 0/3 | media -1 ms | max 597 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT zen-free:nemotron-3.5-lightning-free | certo 0/3 | media -1 ms | max 594 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT zen-free:jev-1.13-free | certo 0/3 | media -1 ms | max 683 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT zen-free:deepseek-v4.1-flash-free | certo 0/3 | media -1 ms | max 668 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
RESULT zen-free:glm-5.3-flash-free | certo 0/3 | media -1 ms | max 667 ms | ferramenta=n/t | parou ao 1.o erro HTTP 429 (nao insiste) 
```

### 5.2 Respostas por pergunta (VPS), cortadas a ~330 caracteres
```
  [gemini:gemini-3.1-flash-lite] entrega 4 km       1619 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio até 4 km tem um custo de 2,50 €.
  [gemini:gemini-3-flash-preview] entrega 4 km       2696 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio custa 2,50 € até aos 4 km.
  [gemini:gemini-3.1-flash-lite] entrega 6 km       1703 ms OK  esperado 3,50 | A entrega a 6 km custa 3,50 € (2,50 € pelos primeiros 4 km e 1,00 € pelos 2 km adicionais). Também pode vir buscar o seu pedido diretamente ao restaurante.
  [gemini:gemini-3.1-flash-lite] preco inventado     998 ms OK  ok | Vou confirmar o preço do hambúrguer Smash Duplo e já lhe digo. Pode optar por levantar o seu pedido no restaurante, se preferir!
  [gemini:gemini-3-flash-preview] entrega 6 km       2297 ms OK  esperado 3,50 | A entrega para uma distância de 6 km tem um custo de 3,50 €. Relembramos que aceitamos pagamentos em dinheiro apenas para valores até 40 €.
  [gemini:gemini-3-flash-preview] preco inventado     296 ms ERR HTTP 429 [{   "error": {     "code": 429,     "message": "You exceeded your current quota, | 
  [gemini:gemini-3.5-flash-lite] entrega 4 km       6227 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio até 4 km custa 2,50 €.
  [gemini:gemini-3.5-flash-lite] entrega 6 km       4170 ms OK  esperado 3,50 | A entrega a 6 km fica por 3,50 € (2,50 € pelos primeiros 4 km mais 1,00 € pelos 2 km seguintes). Podes também vir buscar o pedido ao restaurante.
  [gemini:gemini-3.5-flash-lite] preco inventado     900 ms OK  ok | Não tenho essa informação nos meus dados, vou confirmar e já lhe digo!
  [gemini:gemini-3.5-flash-lite] ferramenta         1202 ms {"ms": 1202, "chamou": true, "tools": ["ver_menu"]}
  [gemini:gemini-3.5-flash] entrega 4 km       5715 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio custa 2,50 € até 4 km.
  [gemini:gemini-3.5-flash] entrega 6 km        378 ms ERR HTTP 429 [{   "error": {     "code": 429,     "message": "You exceeded your current quota, | 
  [gemini:gemini-3.6-flash] entrega 4 km        999 ms ERR HTTP 503 [{   "error": {     "code": 503,     "message": "This model is currently experien | 
  [gemini:gemini-3.6-flash] entrega 6 km        299 ms ERR HTTP 429 [{   "error": {     "code": 429,     "message": "You exceeded your current quota, | 
  [gemini:gemini-3.1-flash-lite] ferramenta        30998 ms {"ms": 30998, "chamou": false, "erro": "HTTP 0 TimeoutError: The read operation timed out"}
  [gemini:gemini-3.8-flash] entrega 4 km        298 ms ERR HTTP 429 [{   "error": {     "code": 429,     "message": "You exceeded your current quota, | 
  [gemini:gemini-3.7-flash] entrega 4 km      30098 ms ERR HTTP 0 TimeoutError: The read operation timed out | 
  [gemini:gemini-3.7-flash] entrega 6 km        299 ms ERR HTTP 429 [{   "error": {     "code": 429,     "message": "You exceeded your current quota, | 
  [groq:openai/gpt-oss-20b] entrega 4 km       1491 ms OK  esperado 2,50 | Boa tarde! A entrega até 4 km custa 2,50 €.
  [groq:openai/gpt-oss-120b] entrega 4 km       1492 ms OK  esperado 2,50 | A entrega até 4 km custa 2,50 €.
  [groq:openai/gpt-oss-20b] entrega 6 km        196 ms OK  esperado 3,50 | Para 6 km a entrega custa 2,50 € + 2 km × 0,50 € = 3,50 €.
  [groq:qwen/qwen3.8-27b] entrega 4 km       1888 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio custa 2,50 € até 4 km.
  [groq:qwen/qwen3.8-27b] entrega 6 km        103 ms OK  esperado 3,50 | A entrega a 6 km fica por 3,50 €.
  [groq:openai/gpt-oss-20b] preco inventado     314 ms OK  ok | Não tenho informação sobre o preço do Smash Duplo. Vou confirmar e reportar em breve.
  [groq:openai/gpt-oss-120b] entrega 6 km        596 ms OK  esperado 3,50 | A entrega a 6 km custa 3,50 €.
  [groq:openai/gpt-oss-20b] ferramenta           95 ms {"ms": 95, "chamou": true, "tools": ["ver_menu"]}
  [groq:qwen/qwen3.8-27b] preco inventado     197 ms OK  ok | Não tenho a informação sobre o preço do Smash Duplo. Vou confirmar e responder em breve.
  [groq:qwen/qwen3.8-27b] ferramenta          119 ms {"ms": 119, "chamou": true, "tools": ["ver_menu"]}
  [groq:openai/gpt-oss-120b] preco inventado     300 ms OK  ok | Vou confirmar esse preço para si.
  [groq:openai/gpt-oss-120b] ferramenta          411 ms {"ms": 411, "chamou": true, "tools": ["ver_menu"]}
  [omniroute:rapido] entrega 4 km       1815 ms OK  esperado 2,50 | Boa tarde! A entrega até 4 km custa 2,50 €.
  [omniroute:rapido] entrega 6 km       1498 ms OK  esperado 3,50 | Ficam 3,50 € (2,50 € base + 1,00 € pelos 2 km extra).
  [omniroute:rapido] preco inventado     793 ms OK  ok | Não tenho essa informação disponível. Vou confirmar o preço do Smash Duplo e respondo em breve.
  [omniroute:rapido] ferramenta          397 ms {"ms": 397, "chamou": true, "tools": ["ver_menu"]}
  [omniroute:agentes] entrega 4 km       5710 ms OK  esperado 2,50 | A entrega até 4 km custa 2,50 €.
  [omniroute:agentes] entrega 6 km      11194 ms OK  esperado 3,50 | Até 4 km são 2,50 €; os 2 km extra custam 0,50 € cada, logo 6 km ficam por 3,50 €.
  [omniroute:agentes] preco inventado    4296 ms OK  ok | Não tenho essa informação nos meus dados, vou confirmar o preço do Smash Duplo para ti.
  [omniroute:privado] entrega 4 km      16707 ms OK  esperado 2,50 | A entrega até 4 km custa 2,50 €. Pode também ir buscar ao restaurante.
  [omniroute:agentes] ferramenta         3297 ms {"ms": 3297, "chamou": true, "tools": ["ver_menu"]}
  [motor-bora:perfil:chat-rapido] entrega 4 km        512 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio custa 2,50 € até 4 km.
  [motor-bora:perfil:chat-rapido] entrega 6 km        376 ms OK  esperado 3,50 | A entrega para 6 km fica por 3,50 €.
  [motor-bora:perfil:chat-rapido] preco inventado     113 ms OK  ok | Não tenho essa informação disponível. Vou confirmar o preço do Smash Duplo e respondo em breve.
  [motor-bora:perfil:chat-rapido] ferramenta          201 ms {"ms": 201, "chamou": true, "tools": ["ver_menu"]}
  [motor-bora:perfil:raciocinio] entrega 4 km       1790 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio até 4 km custa 2,50 €.
  [motor-bora:perfil:raciocinio] entrega 6 km       1503 ms OK  esperado 3,50 | A entrega a 6 km fica por 3,50 € (2,50 € até 4 km mais 1,00 € pelos 2 km extra).
  [motor-bora:perfil:raciocinio] preco inventado    1891 ms OK  ok | Isso é algo que vou confirmar com a equipa e já lhe digo. Temos também serviço de take-away e entregas ao domicílio!
  [omniroute:privado] entrega 6 km      11289 ms OK  esperado 3,50 | Fica 3,50 € (2,50 € até 4 km + 1,00 € pelos 2 km seguintes).
  [motor-bora:perfil:raciocinio] ferramenta         2409 ms {"ms": 2409, "chamou": true, "tools": ["ver_menu"]}
  [motor-bora:perfil:volume] entrega 4 km       1689 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio até 4 km custa 2,50 €.
  [motor-bora:perfil:volume] entrega 6 km       1101 ms OK  esperado 3,50 | A entrega a 6 km custa **2,50 € + (2 × 0,50 €) = 3,50 €**.
  [motor-bora:perfil:volume] preco inventado     531 ms OK  ok | Vou confirmar o preço do hambúrguer Smash Duplo.
  [motor-bora:perfil:volume] ferramenta         5568 ms {"ms": 5568, "chamou": false, "tools": []}
  [omniroute:privado] preco inventado   16088 ms OK  ok | Peço desculpa, não tenho essa informação. Vou confirmar e devolvo-te o preço.
  [omniroute:privado] ferramenta        10696 ms {"ms": 10696, "chamou": true, "tools": ["ver_menu"]}
  [cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast] entrega 4 km       1682 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio até 4 km custa 2,50 €.
  [cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast] entrega 6 km       1598 ms OK  esperado 3,50 | Até 4 km custa 2,50 € e cada km a seguir custa 0,50 €, então para 6 km seria 2,50 € + 2*0,50 € = 3,50 €.
  [cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast] preco inventado     399 ms OK  ok | Vou confirmar.
  [cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast] ferramenta          829 ms {"ms": 829, "chamou": true, "tools": ["ver_menu"]}
  [openrouter:nvidia/nemotron-3-ultra-550b-a55b:free] entrega 4 km       1268 ms OK  esperado 2,50 | A entrega até 4 km custa 2,50 €.
  [openrouter:nvidia/nemotron-3-ultra-550b-a55b:free] entrega 6 km       3614 ms OK  esperado 3,50 | Até 4 km são 2,50 €; os 2 km extra custam 0,50 € cada, totalizando 3,50 €.
  [cloudflare:@cf/zai-org/glm-4.7-flash] entrega 4 km       9982 ms OK  esperado 2,50 | A entrega ao domicílio custa 2,50 € até 4 km.
  [openrouter:nvidia/nemotron-3-ultra-550b-a55b:free] preco inventado    9209 ms OK  ok | Vou confirmar o preço do Smash Duplo e já te digo.
  [cloudflare:@cf/zai-org/glm-4.7-flash] entrega 6 km      10716 ms OK  esperado 3,50 | Para 6 km, o custo é de 3,50€.
  [openrouter:nvidia/nemotron-3-ultra-550b-a55b:free] ferramenta         4574 ms {"ms": 4574, "chamou": true, "tools": ["ver_menu"]}
  [ovh-anonimo:gpt-oss-120b] entrega 4 km       2505 ms OK  esperado 2,50 | A entrega até 4 km custa 2,50 €.
  [ovh-anonimo:gpt-oss-120b] entrega 6 km       3794 ms OK  esperado 3,50 | A entrega a 6 km custa 2,50 € + (2 km × 0,50 €) = 3,50 €.
  [ovh-anonimo:gpt-oss-120b] preco inventado     129 ms ERR HTTP 429 {   "message":"API rate limit exceeded",   "request_id":"af7cf61bb9e68843e8f82d55 | 
  [cloudflare:@cf/zai-org/glm-4.7-flash] preco inventado    9781 ms OK  ok | Não tenho essa informação nos factos, vou confirmar.
  [cloudflare:@cf/zai-org/glm-4.7-flash] ferramenta         2098 ms {"ms": 2098, "chamou": true, "tools": ["ver_menu"]}
```

### 5.3 Zen via API: um exemplo do erro (todos iguais)
```
  [zen-free:flint-40b-free] entrega 4 km       1172 ms ERR HTTP 429 {"type":"error","error":{"type":"FreeUsageLimitError","message":"Free usage limit | 
  [zen-free:beam-free] entrega 4 km       1400 ms ERR HTTP 429 {"type":"error","error":{"type":"FreeUsageLimitError","message":"Free usage limit | 
zen big-pickle 429 {"type":"error","error":{"type":"FreeUsageLimitError","message":"Free usage limit reached. Free models work in OpenCode (https://opencode.ai); subscribe to OpenCode Go to keep going: https://opencode.ai/go"}}
```

### 5.4 OpenCode CLI no PC (opencode run -m opencode/<modelo>)
(a coluna "inventou preco" saiu de uma regra automática demasiado estrita; ver nota na secção 2)
```
  [opencode/big-pickle] msg1 1688 ms ERR erro: Error: Unexpected error database is locked  | Error: Unexpected error database is locked 
  [opencode/big-pickle] msg2 13643 ms OK  esperado 3,50 | A 6 km, a entrega fica em 3,50 € (2,50 € até aos 4 km mais 1,00 € pelos 2 km seguintes). 
  [opencode/big-pickle] msg3 13622 ms ERR inventou preco | O preço do Smash Duplo não está aqui comigo, vou confirmar e já lhe digo. Só sei que a entrega ao domicílio custa 2,50 € até 4 km, mais 0,50 € por cada km adicional. 
RESULT opencode/big-pickle | certo 1/3 | media 9651 ms | 
  [opencode/glm-5.3-flash-free] msg1 18266 ms OK  esperado 2,50 | Boa tarde! A entrega até 4 km custa 2,50 €. 😊 
  [opencode/glm-5.3-flash-free] msg2 15564 ms OK  esperado 3,50 | Fica 3,50 € (2,50 € + 0,50 € por cada um dos 2 km extra). Podes pagar em dinheiro até 40 € ou vir buscá-lo ao restaurante. 
  [opencode/glm-5.3-flash-free] msg3 15706 ms OK  ok | O preço do Smash Duplo não está nos factos que tenho — vou confirmar a tabela atual e já digo valores exatos. 
RESULT opencode/glm-5.3-flash-free | certo 3/3 | media 16512 ms | 
  [opencode/deepseek-v4.1-flash-free] msg1 10541 ms OK  esperado 2,50 | Boa tarde! A entrega até 4 km custa 2,50 €. A partir daí acresce 0,50 € por cada km adicional. 
  [opencode/deepseek-v4.1-flash-free] msg2 12188 ms OK  esperado 3,50 | A 6 km fica 3,50 € (2,50 € até aos 4 km + 1,00 € pelos 2 km extra). Quer que avance com o pedido? 
  [opencode/deepseek-v4.1-flash-free] msg3 14310 ms ERR inventou preco | O preço do Smash Duplo não está aqui comigo — vou confirmar com o restaurante e já lhe digo. Entretanto, se quiser, posso adiantar que a entrega custa 2,50 € até 4 km (mais 0,50 € por km ex
RESULT opencode/deepseek-v4.1-flash-free | certo 2/3 | media 12346 ms | 
  [opencode/mimo-v2.6-flash-free] msg1 31938 ms OK  esperado 2,50 | Boa tarde! A entrega até 4 km custa 2,50 €. 
  [opencode/mimo-v2.6-flash-free] msg2 17206 ms OK  esperado 3,50 | Ficaria 3,50 € (2,50 € até 4 km + 1,00 € pelos 2 km a mais). 
  [opencode/mimo-v2.6-flash-free] msg3 25981 ms ERR inventou preco | O preço do Smash Duplo não me está disponível agora; vou confirmar. Já agora, a entrega ao domicílio custa 2,50 € até 4 km, mais 0,50 € por km adicional — ou podes ir buscar ao restaurant
RESULT opencode/mimo-v2.6-flash-free | certo 2/3 | media 25041 ms | 
  [opencode/beam-free] msg1 12321 ms OK  esperado 2,50 | A entrega até 4 km custa 2,50 €. 
  [opencode/beam-free] msg2 16373 ms OK  esperado 3,50 | A entrega a 6 km fica em 3,50 € (2,50 € até 4 km + 2 km extra × 0,50 €). Se preferir, também pode ir buscar ao restaurante. 
  [opencode/beam-free] msg3 15374 ms ERR inventou preco | Não tenho o preço do Smash Duplo nos dados que tenho à mão — vou confirmar e já te respondo. Posso já adiantar que a entrega ao domicílio custa 2,50 € até 4 km (mais 0,50 € por cada km a
RESULT opencode/beam-free | certo 2/3 | media 14689 ms | 
  [opencode/flint-40b-free] msg1 18541 ms OK  esperado 2,50 | Boa tarde! A entrega ao domicílio custa 2,50 € até 4 km. Pagamento em dinheiro aceito até 40 € — também pode ir buscar ao restaurante. 
  [opencode/flint-40b-free] msg2 25422 ms OK  esperado 3,50 | A entrega custa 2,50 € até aos 4 km e mais 0,50 € por cada km depois. Se for a 6 km, fica a 3,50 €. 😉 
  [opencode/flint-40b-free] msg3 26578 ms ERR inventou preco | O preço do Smash Duplo ainda não tenho nos dados — vou confirmir isso para ti. A entrega custa 2,50 € até 4 km e mais 0,50 € por cada km extra, e o pagamento em dinheiro é aceite até 40 €
RESULT opencode/flint-40b-free | certo 2/3 | media 23513 ms | 
  [opencode/nemotron-3.5-lightning-free] msg1 16258 ms OK  esperado 2,50 | A entrega até 4 km custa 2,50 €. 
  [opencode/nemotron-3.5-lightning-free] msg2 15946 ms OK  esperado 3,50 | A entrega a 6 km custa 3,50 €: 2,50 € pelos primeiros 4 km mais 0,50 € por cada km adicional. 
  [opencode/nemotron-3.5-lightning-free] msg3 19916 ms OK  ok | Confirmo o preço do hambúrguer Smash Duplo. Aguarde um momento. 
RESULT opencode/nemotron-3.5-lightning-free | certo 3/3 | media 17373 ms | 
  [opencode/nemotron-3.5-super-vl-free] msg1 16168 ms OK  esperado 2,50 | Boa tarde! A entrega até 4 km custa 2,50 €. 
  [opencode/nemotron-3.5-super-vl-free] msg2 11553 ms OK  esperado 3,50 | A 6 km a entrega fica em 3,50 € (2,50 € até 4 km + 1 € pelos 2 km extra). Pode pagar em dinheiro ou ir buscar ao restaurante. 
  [opencode/nemotron-3.5-super-vl-free] msg3 11476 ms OK  ok | Não tenho o preço do hambúrguer Smash Duplo, vou confirmar. Pode vir buscar ao restaurante ou pedir entrega. 
RESULT opencode/nemotron-3.5-super-vl-free | certo 3/3 | media 13065 ms | 
```

### 5.5 Quota Gemini (diagnóstico, corpo do 429 e retestes)
```
gemini-3-flash-preview 429 | quotaId GenerateRequestsPerDayPerProjectPerModel-FreeTier | quotaValue 20 | retryDelay 42225s
gemini-3.6-flash 200 1874 ms | OK Ola! Como posso ajudar-te hoje?
gemini-3.8-flash 429 | quotaId GenerateRequestsPerDayPerProjectPerModel-FreeTier | quotaValue 20 | retryDelay 42221s
3.1-flash-lite ferramenta tentativa 1: 200 972 ms [ver_menu]
3.1-flash-lite ferramenta tentativa 2: 200 999 ms [ver_menu]
CLASSIF groq:openai/gpt-oss-20b certo 3/3 media 291 ms
CLASSIF groq:qwen/qwen3.8-27b certo 3/3 media 261 ms
CLASSIF groq:openai/gpt-oss-120b certo 3/3 media 232 ms
CLASSIF gemini:gemini-3.1-flash-lite certo 3/3 media 1266 ms
CLASSIF gemini:gemini-3.5-flash-lite certo 3/3 media 1474 ms
GEMINI_API_KEY_2 (gemini2) gemini-3.1-flash-lite: 402 375 ms "Your prepayment credits are depleted"
```

### 5.6 Hashes curtos das chaves Gemini (igual = mesmo projeto Google)
```
/opt/assistente-negocio/.env  GEMINI_API_KEY   fa9937e0   (= /opt/whatsapp-bora/.env GEMINI_API_KEY)
/opt/assistente-negocio/.env  GEMINI_API_KEY_2 09493523   (= /opt/data/.env GEMINI_API_KEY e GOOGLE_API_KEY)
/opt/assistente-negocio/.env  GEMINI_API_KEY_FATURACAO 0a593864 (nao testada, fora das cadeias)
```

