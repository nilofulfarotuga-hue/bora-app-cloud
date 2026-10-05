-- 05/10 08:48 — Danilo: o cliente paga o preço que vê na app; se o real sair mais barato, a diferença fica
-- com a Bora; se sair mais caro, a Bora assume e o sistema corrige o preço. NÃO se devolve excedente.
-- Desliga o gatilho criado às 07:17 (fica no banco desligado, sem efeito). Já aplicado em produção.
alter table public.orders disable trigger trg_excedente_preautorizacao;
comment on function public.fn_excedente_preautorizacao() is 'DESLIGADO 05/10 por decisão do Danilo: não se devolve excedente — o cliente paga o preço que vê na app.';
