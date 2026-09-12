# Prova 0 — envio DESLIGADO antes de qualquer outra coisa (02/09/2026, 07:51)

Regra de arranque do Danilo: durante a missão o bot não responde a ninguém. Antes de abrir o
WhatsApp Web ou tocar em mais nada, trancaram-se as duas portas do PC. A da VPS vem a seguir
(ver `01-envio-desligado-vps.md`).

## Porta 1 — o cérebro (`servidor_cerebro.py`, 127.0.0.1:8790)
Bandeira em ficheiro, lida **a cada pedido** (não só ao arrancar):
`C:\BoraLocal\Desktop-PC-antigo\ferramentas\whatsapp-loja\ENVIO_DESLIGADO`

Cérebro antigo (PID 13836, código sem a bandeira) terminado e reiniciado. Saída literal:

```
SUCCESS: The process with PID 13836 has been terminated.
saude    : {'ok': True, 'servico': 'cerebro-whatsapp', 'porta': 8790, 'envio_desligado': True}
responder: {'acao': 'silencio-missao', 'texto': '', 'aviso_danilo': ''}
lembretes: {'lembretes': []}
--- ultimas 2 linhas do log ---
{"evento": "responder", "numero": "351000000000", "msg": "oi tudo bem", "acao": "silencio-missao", "envio_desligado": true, "ts": "2026-09-02T07:51:14"}
{"evento": "lembretes", "n": 0, "envio_desligado": true, "ts": "2026-09-02T07:51:14"}
--- quem segura a porta agora ---
  TCP    127.0.0.1:8790         0.0.0.0:0              LISTENING       41476
```

Com a bandeira, `/responder` devolve silêncio **sem calcular nada** — não abre fichas, não
guarda estafetas, não chama o modelo, não avisa o Telegram. O que chegou fica no log.

## Porta 1b — a própria extensão (`vigia-whatsapp-bora/content.js`, v6)
Segunda tranca, no sítio que envia: `const ENVIO_DESLIGADO = true;` e a primeira linha de
`enviar()` é `if (ENVIO_DESLIGADO) { log('ENVIO DESLIGADO ...'); return false; }`. Os lembretes
proactivos também saem cedo. `node --check` passou. O Chrome estava fechado (0 processos) e só
foi aberto DEPOIS desta prova, por isso carregou já o `content.js` v6.

## Estado do canal quando a missão começou
- Chrome fechado desde pelo menos 31/08 22:50 (última decisão no log) até 02/09 07:53 — a porta do
  PC esteve **parada um dia inteiro**; nada foi respondido a ninguém nesse intervalo.
- Última resposta enviada a um contacto real antes da missão: 31/08 22:50, "Boa noite, o senhor.
  Como posso ajudar hoje?" ao número ...120.
