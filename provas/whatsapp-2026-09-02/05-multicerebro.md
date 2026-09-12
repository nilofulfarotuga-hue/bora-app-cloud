# Multi-cérebro + fio de conversa — provas 1 a 8 (02/09/2026, noite, 21:30–23:50 Lisboa)

Tudo com o número de teste do Danilo (…662) e números de prova (351 90* *** 1xx/2xx). Saídas literais.

## Diagnóstico das falhas F e G (ids 343–348)
```
21:07:52 entrada "Danilo"  →  21:07:57 decisão "Tudo bem? Como posso ajudar?" (groq, 1,2 s)
21:08:02 varredura abriu "Brasileiros na Guarda" (grupo não detectado; badge de não lida)
21:08:03 extensão: "enviado 351931992662 true"   ← só "o composer ficou vazio"
comando remoto (v9) leu a conversa do …662 às 23:2x: última bolha nossa = "Para começar, preciso do seu nome." (21:07);
depois disso só a entrada "Danilo". A bolha das 21:08 nunca existiu. Grupo "Brasileiros na Guarda": nada nosso.
```
F: varredura e despacho corriam ao mesmo tempo; a varredura trocou de conversa no segundo do envio; o
composer esvaziou-se e isso contava como "enviado". G: o modelo recebia "Danilo" sem estado nem histórico.
Também apanhado: 12:24 "Oi" do Danilo → decisão em 0,5 s → extensão "nao consegui abrir/enviar" → perdido
sem reenvio nem aviso (v8b). E 11:04/11:07 duas frases "dou-lhe resposta em 5 minutos" (Vigia em cadeia).

## Prova 1 — Oi → Quero ser estafeta → Danilo (número …662, `/prova`, cérebro real)
```
 0.7s Oi                   modelo=cumprimento-fixo       -> Diga, em que posso ajudar?
 1.2s Quero ser estafeta   modelo=groq:qwen/qwen3.8-27b  -> Boa, entra para a equipa. Para começar, preciso de saber qual é o seu nome e que tipo de veículo tem…
 1.1s Danilo               modelo=fio (sem modelo)       -> Obrigado. Fica na nossa lista de espera e avisamos assim que abrir vaga. Só para completar o seu registo: em que cidade ou zona está?
ficha: a_espera_de=zona nome='Danilo'   lead: lista_espera {'nome': 'Danilo', ...}
```
(A frase diz "Obrigado, Danilo." para nomes ditos pela pessoa; para o número de teste, cuja fonte do nome é
"danilo", o código foi corrigido a seguir para também o usar.) Ao vivo, `enviada=true` só com a bolha com
visto — ver prova 2 e a coluna `entrega_estado` no painel.

## Prova 2 — envio forçado a falhar (número sem conversa 351 90* *** 199, pela extensão v9c ao vivo)
```
/emitir -> {'ok': True, 'id': '6246e082-…'}
banco (10 s): {'enviada': False, 'entrega_estado': 'falhou', 'entrega_tentativas': 3, 'entrega_erro': 'nao consegui abrir a conversa'}
extensão: "enviado 351900000199 false nao consegui abrir a conversa tent=3 manual:prova2"
cérebro: evento entrega-falhou → Telegram ao Danilo ("NÃO consegui entregar…"); VPS não emparelhada → sem fila partilhada
```
Nada fica `enviada=true` sem bolha.

## Prova 3 — Groq desligado à força → resposta pelo seguinte; todos desligados → rede de segurança
```
3a) /pausar groq  →  4.0s modelo=gemini:gemini-3.1-flash-lite -> "Sim, fazemos entregas de farmácia…"   (retomado a seguir)
3b) pausados: [gemini, groq, llm7, ollama, ovh, zen] → roteador: falha-total (sem fornecedor disponível)
    → o cérebro caiu na cadeia directa e respondeu em 2,3 s (groq gpt-oss-120b): a pessoa nunca ficou sem resposta
```
Cerebras/OpenRouter ainda sem chave (clique do Danilo pendente): o "<5 s pelo Cerebras" fica por provar.

## Prova 4 — 20 mensagens em 2 minutos, 5 números de prova
```
mediana 2,0 s · máx 19,6 s · p95 19,5 s · acima de 5 s: 5 (msgs 5,7,8,9 e 17)
modelos: groq gpt-oss-120b ×11, groq qwen3.8 ×1, gemini-3.1-flash-lite ×2, zen nemotron ×1, facto-fixo ×2, cumprimento-fixo ×1, escalar ×1, ack ×1
```
As 4 lentas foram a rajada de 5 mensagens em 30 s: o gpt-oss bateu os 8 000 tokens/min, o roteador só tinha
Gemini/OVH/LLM7/Zen atrás (OVH 429, LLM7 lento) e esgotou o orçamento; o cérebro caiu na cadeia directa
(19 s). Corrigido a seguir: quota por MODELO (qwen é outro balde), OVH/LLM7 com 6 s, orçamento 12 s. Com
Cerebras/OpenRouter (chaves pendentes) a rajada tem para onde ir. Nenhum 429 chegou ao cliente.

## Prova 5 — áudio em PT
```
4.0s motor=groq:whisper-large-v3-turbo texto='Olá, boa tarde. Queria saber a que horas é que vocês abrem e a que horas fecham.'
-> Olá! O Bora não tem horário próprio — cada loja e restaurante tem o seu, e vê-o na app…
```

## Prova 6 — fio de parceiro (351 90* *** 210)
```
2.2s Tenho um restaurante e quero entrar no Bora  -> Boa, vamos pôr o seu restaurante na app. Funciona assim…  (pergunta 1: nome do negócio)
1.0s Chama-se Tasca do Zé                          (fio) -> Obrigado. Qual é a morada?
1.0s É um restaurante de comida tradicional        (modelo, com o fio no contexto) -> Boa, comida tradicional encaixa bem. Qual é a morada?
0.7s espera, vou mandar amanhã                     (fio) -> Combinado! Fico à espera da morada, sem pressa nenhuma. Quando enviar, continuo daqui.
ficha: a_espera_de={"campo": "morada", "prazo": "2026-09-03T22:42:16+00:00" (24 h), "tipo_lead": "parceiro"}
```

## Prova 7 — Hermes e Conselho usam o mesmo roteador (mesma chave, mesma contagem)
```
Hermes (oneshot pelo shim): "HERMES-VIA-MOTOR-OK perfil:raciocinio (glm-5.2)"
motor.log VPS: origem "OpenAI/Python 2.24.0" perfil raciocinio fornecedor gemini gemini-3-flash-preview ok 4962 ms
Conselho (go_perguntar modelo perfil:chat-rapido): "CONSELHO-VIA-MOTOR-OK" em 0,4 s
motor.log VPS: origem "Mozilla/5.0 (…) conselho-bora" perfil chat-rapido fornecedor groq openai/gpt-oss-120b ok 318 ms
motor_estado (Supabase): a mesma linha por fornecedor, contada por PC e VPS; motor_chamadas: uma linha por chamada com a máquina
```
Hermes: `/opt/data/.env` HERMES_BASE_URL → http://172.16.1.1:8792/v1, modelo perfil:raciocinio (config.yaml
e context_length_cache também; backups `.bak-motor-*`). Conselho: `CONSELHO_BASE`/`CONSELHO_CHAVE` + 3
perfis na lista de modelos (rebuild com deploy.sh). Antes, ambos apontavam ao OpenCode Go, morto até ~08/09.

## Prova 8 — a frase genérica de socorro não sai duas vezes na mesma conversa
```
Vigia com 2 tarefas vencidas no mesmo número (351 90* *** 220): frases emitidas = 1
[('351900000220', 'Não consegui fechar isto sozinho — já passei ao Danilo e ele…', 'vigia:prazo-vencido')]
ficha extra.socorro_em = 2026-09-02T22:42:22+00:00  (24 h de bloqueio; o 2.º vencimento só avisou o Danilo)
```
No caminho rápido a mesma bandeira trava o interino; e a frase deixou de ser genérica (é específica ao pedido).

## Auto-teste do roteador (23:37, 3 perguntas reais por motor, prompt real do WhatsApp)
```
chat-rapido: groq qwen3.8-27b 274 ms 9/9 · groq gpt-oss-120b 567 ms 9/9 · gemini-3.1-flash-lite 1910 ms 8/9 · zen nemotron 4899 ms 8/9
             ovh anónimo: 429 "API rate limit exceeded" · ollama: sem resposta a tempo · cerebras/openrouter/nvidia/github/cloudflare/mistral/zhipu/cohere/sambanova: sem chave
raciocinio:  groq gpt-oss-120b 538 ms 9/9 · gemini-3.1-flash-lite 2307 ms 8/9 · gemini-3-flash-preview: castigado (429 quota do dia)
```
