# Provas 1 (silêncio), 12 (duas portas, uma resposta) e "Danilo respondeu à mão" — 02/09/2026

## Prova 1 — silêncio provado na tabela `whatsapp_messages` (Supabase, 08:39)
Contagem por direcção/estado, com o envio desligado e as provas já corridas contra o cérebro:

```
direcao  enviada decisao          porta        n
entrada  false   silencio-missao  pc-extensao  3     <- mensagens reais recebidas pela porta: só registadas
entrada  false   (null)           prova        13    <- entradas das provas (número de teste)
saida    false   escalar          prova        1     <- resposta decidida, NUNCA enviada
saida    false   responder        prova        11    <- respostas decididas, NUNCA enviadas
```
Nenhuma linha com `enviada=true`. A fila de saída do cérebro descarta tudo enquanto a bandeira
existir (`/pendentes` devolve `[]` e limpa a fila), e a extensão tem a segunda tranca (`ENVIO_DESLIGADO=true`).

## "Quando o Danilo responde à mão, o bot cala 2 h nesse contacto" (Bloco 4)
Evento `saida-danilo` (mensagem de saída que não foi do bot) entregue ao cérebro para o número de
prova 351 9** *** 002:
```
/evento saida-danilo: {'ok': True, 'acao': 'bot-pausado-2h'}
ficha: bot_pausado=True ate=2026-09-02T09:35:51+00:00 por=danilo respondeu à mão
```
A ficha fica pausada até `bot_pausado_ate`; `fichas.pausado()` devolve `silencio-pausado` no agente.
(O exemplo de tom que este teste gravou no manual foi removido por ser texto meu, não do Danilo.)

## Prova 12 — extensão (PC) e VPS ao mesmo tempo → sem resposta dupla
A tranca é por id de mensagem, partilhada no Supabase (`whatsapp_locks`). A mesma `msg_id` entregue
às duas portas, com os dois cérebros a correr (PC `porta=pc-extensao`, VPS `porta=vps-baileys`):
```
PC, 1a vez : {'ok': True, 'acao': 'silencio-missao'}      <- ficou com a mensagem (tranca inserida)
PC, 2a vez : {'ok': True, 'acao': 'ja-vista'}             <- dedup local
VPS, mesma msg_id: {"ok": true, "acao": "ja-vista"}       <- a VPS viu a tranca da outra porta
whatsapp_locks: [{'msg_id': 'false_351900000001@c.us_PROVA12_1788334551', 'porta': 'pc-extensao'}]
```
A porta Baileys da VPS continua **sem emparelhar** (401 desde 31/08 — ver relatório), por isso a
prova é ao nível do cérebro, que é onde a tranca vive; a porta só entrega o que o cérebro decide.
