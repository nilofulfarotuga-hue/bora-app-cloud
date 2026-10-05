// Desligada a 04/10/2026 (auditoria): a senha desta função estava escrita no código público e permitia mudar o IBAN de contas Stripe Connect.
// Convites Connect passam pela stripe-connect-onboard (com login).
Deno.serve(() => new Response('Este link já não está ativo. Pede um novo ao Bora.', { status: 410 }));
