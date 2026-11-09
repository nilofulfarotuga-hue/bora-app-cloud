-- 20261109210000_erros_fora_scope.sql
--
-- Cópia no repo de dois consertos que o Claude.ai aplicou em produção a 09/11/2026
-- (~21:00, por MCP execute_sql; e2e_log 7572, erros fora do scope achados na M10, e2e_log 7333).
-- Idempotente: correr outra vez não muda nada.
--
-- (1) O enum cancellation_initiator só aceitava client/admin/system, mas
--     partner_dispatch_decision grava 'partner' quando a loja cancela -> erro ao gravar.
--     Conferido em produção a 09/11 depois do conserto: client,admin,system,partner.
-- (2) ofertas_prestador_log dava todos os privilégios a anon (RLS ligada, sem políticas:
--     sem fuga, mas não devia ter). Conferido a 09/11: anon sem nenhum privilégio.
--
-- Nota: ALTER TYPE ... ADD VALUE não pode ser usado na mesma transação em que é criado;
-- aqui só se acrescenta, não se usa.

ALTER TYPE public.cancellation_initiator ADD VALUE IF NOT EXISTS 'partner';

REVOKE ALL ON TABLE public.ofertas_prestador_log FROM anon;
