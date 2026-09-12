---
id: licao-exception-when-others-null
tipo: licao
origem: [_cleaning_notify_user · funções de notificação PL/pgSQL · mega-fix 2026-07-18 Parte 7]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — `EXCEPTION WHEN OTHERS THEN NULL` numa função = falha invisível permanente

**Problema.** A profissional de limpeza não recebia nenhuma notificação de oferta/estado, e
não havia rasto de erro em lado nenhum — o sistema parecia "funcionar" (nenhuma exceção subia,
nenhum log de falha).

**Causa real.** A função de notificação (`_cleaning_notify_user` e afins) envolvia o corpo num
`EXCEPTION WHEN OTHERS THEN NULL`. Qualquer erro lá dentro (canal errado, payload inválido,
timeout do `net.http_post`, coluna em falta) era **engolido silenciosamente**: a transação
principal seguia como se a notificação tivesse ido, e não ficava registo nenhum. Falha 100%
invisível — impossível de diagnosticar sem ler o código linha a linha.

**Regra generalizável.**
- **Nunca** `EXCEPTION WHEN OTHERS THEN NULL` em código que faz efeito colateral (notificar,
  cobrar, escrever). Se a intenção é "não rebentar a transação principal por causa de uma
  notificação falhada", então CAPTURA e REGISTA — não descartes:
  ```sql
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO notification_failures (user_id, kind, erro, created_at)
    VALUES (v_user, 'cleaning_status', SQLERRM, now());
    RAISE WARNING 'notify falhou: %', SQLERRM;
  ```
- Uma tabela de falhas (`notification_failures`) transforma o invisível em observável: dá para
  fazer `SELECT` e ver exatamente o que falhou e porquê.

"Não quero que isto rebente o fluxo" nunca justifica "não quero saber que isto falhou". Engolir
uma exceção sem a registar é esconder o bug, não tratá-lo. Ver [[licao-notify-canal-errado]].
