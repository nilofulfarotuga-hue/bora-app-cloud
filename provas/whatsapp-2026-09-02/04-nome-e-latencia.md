# Duas falhas provadas no banco, corrigidas — 02/09/2026, 10:20–11:15 (Lisboa)

## O que aconteceu (lido em `whatsapp_messages`)

Às 10:13 a extensão apanhou **quatro mensagens antigas do próprio Danilo** (31/08: "Junior, encontrei o
problema…", "Agora percebi tudo, Junior…", "Então é mesmo isso, o Safari…", o link de registo) como se
fossem **entradas**, juntou-as ao "Oi" novo numa só mensagem, e o nemotron (57,1 s) respondeu
"Junior. Tudo bem?". Ao "Meu nome não é Júnior" saiu a frase de socorro "…dou-lhe resposta em 3
minutos" (89,7 s). Três raízes, três correcções, e a ficha reparada.

## 1. Ficha do 351 93* *** 662 (número pessoal de teste do Danilo)

```
antes : nome='Danilo' fonte='supabase' papel='estafeta' tratamento='nome'
        o_que_pediu com texto de SAÍDA misturado ("Junior, encontrei o problema…")
depois: nome='Danilo' fonte='danilo'   papel='teste'    tratamento='neutro'
        o_que_pediu refeito só com ENTRADAS (8 últimas)
        4 linhas de whatsapp_messages corrigidas de entrada -> saida ("corrigido-02/09: era saida")
        bot_pausado=False (a Vigia tinha pausado o bot 2 h por tomar a própria frase por resposta do Danilo)
```
Varrimento de TODAS as fichas: `o_que_pediu` refeito só com entradas; nomes com fonte `disse` sem o
nome em nenhuma entrada seriam apagados (nenhum caso: os 4 nomes restantes vêm do Supabase).

## 2. Regras novas em código

| regra | onde | prova |
|---|---|---|
| "meu nome não é X" → nome sai na hora, `nomes_negados` guarda X, resposta seguinte pede desculpa numa frase e segue sem nome | `identidade.negou_o_nome`, `agente._rapido` (prefixo), `fichas` (persistido em `estilo.nomes_negados`) | abaixo |
| papel `teste` → tratamento sempre neutro, nunca nome | `identidade.decidir_tratamento`, `instrucao_tratamento` | "oi" do 662 → "Diga, em que posso ajudar?" |
| um nome só entra pela ferramenta se estiver na mensagem da PESSOA (nunca de texto antigo nem de saída) | `ferramentas_bot.guardar_na_ficha` | — |
| vocativo inventado no arranque da frase ("Junior. Tudo bem?") sai se não for o nome provado | `identidade.sem_vocativo_inventado` | teste unitário: 'Junior. Tudo bem?…' → 'Tudo bem?…' |
| saída própria nunca é "o Danilo respondeu à mão" (memória + banco 48 h) | `servidor_cerebro._e_texto_proprio` | — |
| Vigia: promessa vencida NÃO gera outra promessa; diz que passou ao Danilo e abre UMA tarefa dele | `tarefas.Vigia.tique` | — |
| extensão v8: direcção pelo remetente (o que não é o contacto é SAÍDA), só as N não lidas do badge, máx. 3, historial nunca | `content.js` (`mensagensAbertas(ctx)`, `varrer`) | log "VERSAO v8-2026-09-02-direcao" no cérebro |
| buffer do cérebro corta a 3 mensagens | `servidor_cerebro._evento_de` | — |

Prova ponta a ponta da negação (número de prova 351 90* *** 010, `/prova`, cérebro real):
```
 8.9s "Boa tarde, sou a Marta. Entregam em Gonçalo?" -> "Boa tarde, Marta. Entregamos sim, …"   ficha: nome='Marta'
 1.8s "O meu nome não é Marta"                        -> "Peço desculpa pela confusão com o nome. Como posso ajudar você hoje com o Bora?"
                                                        ficha: nome=None tratamento='neutro' negados=['marta']
 4.1s "Vou verificar com o meu marido e digo"        -> "Sem problema, fico a aguardar. Quando quiser avançar, é só dizer por aqui."
 0.6s "oi"                                           -> "Diga, em que posso ajudar?"   (sem nome)
```
(Na primeira volta o modelo também pediu desculpa por ele — "Peço desculpa pelo erro." — e a frase saiu
dobrada; o código passou a tirar a desculpa do modelo, e a segunda volta acima mostra uma só.)

## 3. Motor: de 57–90 s para < 10 s

Cadeia nova (`cerebro/cadeia.txt` e `Environment=CEREBRO_CADEIA` na VPS):
`groq:llama-3.3-70b-versatile` (activa-se sozinho quando houver `GROQ_API_KEY` no `cerebro/.env` — a
conta é do Danilo) → `gemini-3.1-flash-lite` → `gemini-3-flash-preview` → `ollama` (qwen 7b quente) →
`zen:nemotron-3-ultra-free`. Tempos curtos por motor (12 s Gemini/Groq, 25 s Ollama, 60 s Zen).

Caminho rápido (`agente._rapido`, `CEREBRO_RAPIDO=0` volta ao antigo): cumprimentos e factos da
operação **sem modelo nem ferramenta**; perguntas do manual com a secção já no prompt, **sem ferramenta**;
`pedidos` corre **só** com `RE_PEDIDO` (pedido/entrega), antes do modelo; **uma** chamada ao modelo, sem
tools; se o texto contém promessa ("vou ver", "já lhe digo", "um momento", "dou-lhe resposta") sem
resultado de ferramenta, o código **rejeita e pede outra vez**; se insiste, cai em texto determinístico
(intenção) ou "Não tenho essa informação aqui à mão — já passei ao Danilo e ele responde-lhe por aqui."
+ Telegram + tarefa de 30 min. A frase "dou-lhe resposta em 3 minutos" deixou de existir no código
(agente, servidor e Vigia).

Medição — 10 mensagens pelo `/prova`, número de teste do Danilo, cérebro real, 11:12 Lisboa
(`whatsapp_messages.latencia_ms`, porta `prova`):

```
 400 ms  cumprimento-fixo       oi                                 -> Diga, em que posso ajudar?
 400 ms  cumprimento-fixo       Bom dia, tudo bem?                 -> Diga, em que posso ajudar?
1600 ms  gemini-3.1-flash-lite  Como funciona o Bora?              -> O Bora é uma app de entregas e serviços aqui na Guarda…
 200 ms  facto-fixo             Vocês entregam ao domingo?         -> Funcionamos todos os dias, incluindo domingos e feriados…
 300 ms  facto-fixo             A que horas abrem?                 -> O Bora não tem horário próprio — cada loja…
1300 ms  gemini-3.1-flash-lite  Vocês fazem entregas de farmácia?  -> Fazemos sim, entregamos medicamentos…
1600 ms  gemini-3.1-flash-lite  onde está o meu pedido?            -> O seu último pedido no Auchan foi entregue ontem…   (ferramenta pedidos, antes do modelo)
3900 ms  gemini-3.1-flash-lite  Quero ser estafeta, têm vagas?     -> Neste momento não temos vagas abertas, … lista de espera…  (lead + Danilo, em código)
7600 ms  gemini-3.1-flash-lite  Tenho um restaurante, como ponho…  -> Funciona assim: pomos o seu restaurante na app…      (lead + Danilo + manual)
1200 ms  gemini-3.1-flash-lite  Posso pagar em dinheiro?           -> Pode sim, aceitamos dinheiro em pagamentos até 40 euros…
RESULTADO: 10 de 10 em menos de 10 s (meta: 9 de 10). Máximo 7,6 s; mediana 1,25 s.
```
Nenhuma promessa rejeitada nas 10; nenhum facto inventado bloqueado.

## O que ainda não está provado ao vivo
- O "oi" **pelo telemóvel** do Danilo: o cérebro responde em 0,4 s (acima), mas o tempo que ele vê no
  ecrã soma a varredura da extensão, a janela de junção de bolhas do cérebro e a fila de saída —
  encurtadas nesta mesma passagem (ver relatório). Quando ele mandar "oi", a linha fica em
  `whatsapp_messages` com `porta='pc-extensao'` e `latencia_ms`.
- Groq: sem chave ainda (a conta é dele); a cadeia já o tem em primeiro e salta-o em 0 ms sem chave.
