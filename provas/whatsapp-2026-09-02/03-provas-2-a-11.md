# Provas 2 a 11 — contra o cérebro v2, em modo prova (nada enviado) — 02/09/2026
> Guião: `ferramentas/whatsapp-loja/cerebro/provas.py` (`python -m cerebro.provas`), a bater em
> `POST /prova` do cérebro (decide, regista `enviada=false`, Telegram calado). Número de teste
> do Danilo (351 9** *** 662) e um número inexistente (351 900 000 001). Sete voltas ao longo da
> manhã; cada volta apanhou um defeito e a seguinte confirmou o conserto. Saídas literais.

## Volta 1 (08:27) — 4/10 · a cadeia de modelos não devolveu texto uma vez
Todas as respostas foram a frase de socorro. Erros literais: Gemini 3.x `400 "Function call is
missing a thought_signature in functionCall parts"` (eu deitava fora a assinatura na 2.ª volta);
Ollama `TimeoutError` (7b a avaliar ~3 mil tokens a frio). A transcrição já estava certa:
`faster-whisper:small → "Olá! Boa tarde! Queria saber a que horas é que vocês abrem e a que horas fecham."`

## Volta 2 (08:37) — 6/9 · Gemini com ferramentas reais
`[4] BOT> Boa tarde! O Bora não tem um horário fixo: funcionamos todos os …` (ler_manual)
`[6] interino aos 20.2s: 'Um segundo que vou ver isso.'` → PASSA (ferramenta forçada a 60 s)
`[7a] … registar_lead → PASSA` · `[7b] "Perfeito, pode mandar por aqui mesmo! En"` (cortado — maxOutputTokens) → FALHA
`[8]` cinco ferramentas certas (ler_manual ×2, quem_e, registar_lead, avisar_danilo) e nem uma frase (4 voltas esgotadas) → FALHA

## Volta 3 (08:47) — 8/10 · Gemini primeiro (falhas: 7b e 8, as duas corrigidas a seguir)

## Volta 4 (08:52) — 6/10 · o Gemini esgotou a quota do dia a meio
`gemini-3.6-flash | HTTP 429 "You exceeded your current quota"` · idem `gemini-3-flash-preview`.
Provas 2, 3, 4 passaram com respostas reais antes do 429 (`"Oi, tudo bem? Como posso ajudar?"`,
`"Olá, Keli. Como posso ajudar?"`); as restantes caíram na frase de socorro.

## Volta 5 (09:12) — 7b local primeiro, prompt compacto
`[2] BOT> Olá! Como posso ajudar você hoje?` PASSA · `[3] BOT> Olá Keli! Como posso ajudar hoje?` PASSA
`[4] BOT> Olá! A loja do Bora está aberta todos os dias, das 8h às 22h…` ← **horas INVENTADAS pelo 7b**
(passou o verificador por acidente) → nasceram dois guardas: factos da operação por texto fixo, e
"número na resposta sem nenhuma ferramenta ter corrido = invenção" (bloqueia e cai no facto fixo
ou no "confirmo com o Danilo" + tarefa).
`[6] BOT> O seu pedido do Auchan já foi entregue há cerca de 14 horas.` (dado real do Supabase) PASSA

## Volta 7 (09:36) — 8/10, FINAL
```
[2] numero desconhecido manda 'oi' -> resposta neutra, sem senhor/senhora
    BOT> Olá! Como posso ajudar você hoje?                                             -> PASSA
[3] ERRO: TimeoutError (o guião esperava 180 s; o cérebro levou 185 s com o 7b a frio) -> FALHA (cronómetro)
[4] audio em PT sobre horarios -> transcrito e respondido com o facto certo
    BOT> Olá! O Bora não tem horário próprio — cada loja e restaurante tem o seu, e vê-o na app…
    transcricao: faster-whisper:small "Olá! Boa tarde! Queria saber a que horas é que vocês abrem…" -> PASSA
[5] 'meu pedido esta demorando' -> ferramenta pedidos corrida ANTES do modelo; tarefa criada  -> PASSA
    (o 7b ainda escreveu "Vou verificar…" com os dados na mão -> guarda nova: sai o resumo dos dados reais)
[6] ferramenta forcada a demorar 60 s -> interino aos 20.3s + tarefa; resposta final depois   -> PASSA
[7a] quer por o restaurante -> venda no tom do Danilo, entrar é grátis, 10% no acerto semanal,
     pede redes/fotos; registar_lead + avisar_danilo                                          -> PASSA
[7b] 'beleza vou mandar fotos' -> "Ótimo, fico no aguardo das fotos. Enquanto isso, me diz o
     nome do restaurante e o tipo de cozinha…?"                                              -> PASSA
[8] ERRO: TimeoutError (idem prova 3: cronómetro do guião, 7b a frio)                          -> FALHA (cronómetro)
[9] 'quero reembolso' -> "Recebi, e já passei ao Danilo — é ele que trata de valores e
    reembolsos, e responde-lhe já por aqui."  (acao=escalar, tarefa 30 min, sem valores)      -> PASSA
[10] mensagem em grupo -> ignorar-grupo, sem texto                                              -> PASSA
[11] duas mensagens em 5 s -> buffer de 9 s no /evento (uma decisão só)                        -> PASSA
```
As duas falhas da volta 7 são o cronómetro do guião (180 s) a expirar com o 7b a frio; o guião
passou a esperar 300 s e a cadeia final põe o 7b em último. Sanidade das provas 3, 5 e 8 com a
cadeia final: ver o fim deste ficheiro.

## Aviso ao Danilo a partir do PROPRIO processo do cérebro (09:47)
`POST /avisar → {'ok': True, 'detalhe': 'Sent to telegram home channel (chat_id: 6731890157)'}`
— o cérebro é o processo que a tarefa agendada arranca (pythonw, sem o PATH do utilizador); na v1
este elo falhava (`telegram-falhou` ×4 a 31/08).

## Sanidade final (provas 3, 5, 8 com a cadeia Gemini → Zen → 7b)
_(preenchido no fecho)_
```
Sanidade 09:55 (cadeia Gemini→Zen→7b; Gemini em 429):
[5] BOT> Não tens nenhum pedido ativo agora — os últimos foram entregues ou cancelados há várias
    horas. Estás à espera de algum em especial ou queres fazer um novo?   (zen:nemotron, pedidos) -> PASSA
Sanidade 09:58 (chamada final SEM ferramentas; ferramenta repetida não corre 2x):
[3] BOT> Oi, Keli. Em que posso ajudar?                                    (zen:nemotron, 36.8 s) -> PASSA
Sanidade 10:01 (frase do manual quando o modelo acaba sem texto numa intenção de lead):
[8] BOT> Não temos vagas de momento, mas meto-te na lista de espera. Como te chamas e que
    veículo tens (mota, carro, bicicleta)?             (registar_lead + avisar_danilo correram) -> PASSA
```
**Quadro final:** 1 ✓ · 2 ✓ · 3 ✓ · 4 ✓ · 5 ✓ · 6 ✓ · 7 ✓ · 8 ✓ · 9 ✓ · 10 ✓ · 11 ✓ · 12 ✓ (nível do cérebro; VPS por emparelhar).
**Envio ligado às 10:03:16 (Lisboa), 02/09/2026** — ver `RELATORIO-WHATSAPP-2026-09-02.md`.
