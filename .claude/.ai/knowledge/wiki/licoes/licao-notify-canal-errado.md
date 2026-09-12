---
id: licao-notify-canal-errado
tipo: licao
origem: [notify-client Edge Fn · fluxo de limpeza · mega-fix 2026-07-18 Parte 7]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — notificação enviada pelo canal/`type` errado = entregue mas o app não a roteia (nada aparece)

**Problema.** A profissional de limpeza "recebia" a notificação (o envio tinha sucesso do lado
do servidor) mas nada aparecia no telemóvel dela.

**Causa real.** O payload da limpeza saía pela Edge Function `notify-client` com
`type: 'cleaning_status'`. Mas a `notify-client` tinha tratamento **hardcoded** para
`order_status` (o caso do cliente de delivery) e o app do lado do destinatário só roteava os
`type` que conhecia. Um `type` que o roteador do app não reconhece → a mensagem chega ao
dispositivo mas o handler não sabe o que fazer com ela → deep-link nenhum, ecrã nenhum, som
nenhum. "Enviado com sucesso" no servidor ≠ "mostrado ao utilizador".

**Regra generalizável.**
- Cada público (cliente / estafeta / parceiro / profissional) precisa de um canal ou de um
  `type` que o SEU app saiba rotear. Reutilizar a função de outro público só funciona se o
  `type` for genuinamente respeitado ponta-a-ponta (servidor emite → app roteia por esse `type`).
- Duas saídas limpas: (a) a função de envio passa a **respeitar o `type` recebido** e faz
  deep-link por tipo; ou (b) criar uma função dedicada por público (ex.: `notify-cleaner` no
  padrão da `notify-partner`).
- Testar sempre o caminho COMPLETO: servidor → push → handler do app → ecrã. Parar em "o
  servidor devolveu 200" é meio teste.

Uma notificação só existe quando o utilizador a vê. O `type` é o contrato entre quem envia e
quem mostra — se as duas pontas não concordam, a mensagem morre calada. Ver
[[licao-exception-when-others-null]].
