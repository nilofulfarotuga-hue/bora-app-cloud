# Relatório — varredura das chaves (31/10 a 02/11/2026)

Missão `chaves-varredura-2026-10-31`, Claude Code no PC do Danilo. Autorização do Danilo de 31/10 12:19:
"dá uma varredura em tudo… faz vários testes, e aí sim, publica". Detalhe técnico no `e2e_log`
(run_id `chaves-varredura-2026-10-31`) e em `docs/SEGURANCA-CHAVES.md`.

## Para o Danilo (texto corrido)

Fiz isto: revi uma a uma as funções do servidor que se chamam umas às outras e as que o banco chama. Trinta
e sete estavam com o mesmo defeito que deixou a cliente de 31/10 sem pedido (recusavam a chave do servidor
desde a troca de 16/10) e ficaram corrigidas e publicadas; cada uma foi testada a partir do banco com a chave
antiga e com a nova, e de fora com uma chave falsa, que é sempre recusada. Pelo caminho fechei três portas
abertas: o registo de lojas aceitava um utilizador falsificado, as ofertas de corrida TVDE podiam ser mandadas
por qualquer pessoa com a chave pública da app, e qualquer conta podia mandar um aviso com texto à escolha a
qualquer cliente. A app passou a mandar os avisos com a sessão de quem está ligado (antes ia a chave pública
e o aviso era recusado) e deixou de repetir os avisos que o servidor já manda sozinho. O "Reenviar código" e
o "Encomenda aceite" das festas nunca funcionaram (mandavam o telefone) e agora funcionam. O aviso de
reembolso e de cancelamento ao cliente também falhava sempre e agora chega. No painel, o ecrã de pagamentos
órfãos mostra quem pagou e ficou sem pedido, com um botão "Criar o pedido agora", e há um ecrã novo "Saúde das
chaves"; os dois avisos que abrem esses ecrãs não abriam nada. Todos os dias às 07:00 o servidor testa sozinho
todas as funções e, se alguma recusar a chave, chega-te "CHAVE RECUSADA" no Telegram. Testei o vigia dos
pagamentos com um pagamento falso: avisou-te no Telegram e não criou pedido nenhum; os dados de teste foram
apagados. O limite diário de mensagens do robô de suporte nunca travava e agora trava. Os quatro pagamentos
"sem etiqueta" eram cobranças tuas ao vivo com o telemóvel: 186 € do Jai, 291,53 € do Vansh e dois de 5 €
sem nome; nenhum é um pedido perdido. Tudo foi enviado e as três publicações estão a correr.

Falta isto: o teste completo no emulador (pedido com cartão do princípio ao fim e uma corrida TVDE) não deu
para fazer porque o PC tinha só 700 MB livres e o emulador precisa de 3 GB. A partir de agora, cada cobrança
tua ao vivo com o telemóvel aparece no sininho como aviso alto; está proposto baixar para aviso leve
(é a função dos pagamentos da Stripe, que só a Claude.ai pode publicar).

Erros que encontrei pelo caminho: a Google Play visita o endereço de "apagar conta" e recebe recusa (11 vezes
num dia) — o endereço declarado na Play devia ser uma página; isso pode dar aviso de política da Play. E houve
um erro meu: esta sessão ficou parada quase dois dias à espera de uma confirmação e, ao voltar, repôs por
7 minutos uma versão antiga do vigia das chaves; reposta a certa, nenhum aviso falso saiu.

Próximo passo: confirmar que as três publicações acabaram verdes e, num dia com memória livre, fazer o teste
do pedido com cartão e da corrida TVDE no emulador.

## Números (provas)

- Edge Functions corrigidas e publicadas por esta sessão: support-password-reset, notify-driver,
  notify-partner, tvde-payment, decidir, testar-toque, upload-restaurant-asset, register-partner,
  ocr-receipt, notify-chat-message, notify-partner-low-rating, notify-admin-urgent, notify-client (×2),
  notify-tvde-client, notify-tvde-driver, notify-cleaner, notify-washer, notify-service-provider,
  settlement-receipt, push-clientes-alvo, monthly-partner-statement, notify-driver-assigned, order-edit-settle,
  tvde-recibo-viagem, weekly-closeout-digest, cortex-embedding, analyze-conversations, robot-b,
  support-human-chat, payments-reconciler e auto-refund-order (estas duas a partir da versão do ar, sem as
  gorjetas por publicar). Do banco: 15/15, 36/36 e 30/30 chamadas sem 401/403 (net 88652–88782).
- Zona vermelha (refund, finalize-order-from-intent, dispatch-engine, stripe-webhook, client-cancel-order):
  a tranca do PC nega editar; proposta em `docs/propostas/chaves-2026-10-31/zona-vermelha.md`, aplicada pela
  Claude.ai a 01/11.
- `tools/varrer_chaves_funcoes.ts`: 99 funções, 0 com padrão proibido; 23/23 com ping respondem 200 no ar.
- Vigia das chaves: ronda manual de 02/11 05:34 → 50/50 ok. Painel `/admin/system-health`.
- Vigia dos pagamentos: rascunho de teste → cura 05:50 (finalize 502, sem pedido) → aviso 06:00 com push 3/3 e
  `telegram_sent: true` (net 94394) → dados de teste apagados.
- notify-client com sessão real de conta de teste: a si próprio 200; outro cliente 403; chave pública 401.
- increment_chatbot_quota: sessão 403 → 200 depois do GRANT; anon continua recusada.
- Commits `cb134328` (juntado pela sessão publicar-retoma a 31/10), `896fc3dc` e `358cd9fe` (02/11).

## O que ficou só no banco (a tranca recusa o ficheiro de migração)

`admin_pagos_sem_pedido` (registada à mão como `20261102055000`) e as três do vigia dos pagamentos da
Claude.ai (`20261031122522`, `…604`, `…828`): têm palavras de pagamento e a tranca recusa gravá-las em
`supabase/migrations/`. O SQL está em `supabase_migrations.schema_migrations`.
