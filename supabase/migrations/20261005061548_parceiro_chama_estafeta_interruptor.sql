-- Interruptor do "parceiro chama estafeta" (05/10/2026, fecho da ronda de 04/10).
-- APLICADA em produção a 05/10/2026 como versão 20261005061548.
--
-- PORQUE: o fecho ainda trata estes pedidos (cliente do balcao/telefone, pagos em
-- dinheiro, o estafeta paga o total a loja e recebe-o do cliente — regras de negocio
-- 2.4.1) como um pedido normal de parceiro em dinheiro: credita a loja como se ela
-- ainda nao tivesse recebido e cobra ao estafeta o dinheiro que ele entregou a loja.
-- Num pedido de 10 EUR de balcao (total 14, estafeta 4): loja +12,57 a mais,
-- estafeta 10 a menos. O caminho nunca foi usado (0 pedidos), mas a app publicada a
-- 04-05/10 mostra o botao a 5 lojas. Ate o fecho estar certo, a funcao recusa com
-- 'indisponivel'. Liga-se no painel (Configuracoes > dispatch) quando estiver.
--
-- COMO: acrescento por ancora (contagem = 1, copia antes, prova de igualdade feita
-- em transaccao desfeita). Nada mais na funcao muda.

insert into public.platform_settings (key, value, description, category) values
  ('dispatch_parceiro_chama_estafeta_ligado', 'false'::jsonb,
   'Liga o botao "Chamar estafeta" do parceiro (cliente do balcao ou telefone). DESLIGADO de proposito: o fecho ainda trata estes pedidos como um pedido normal em dinheiro — a loja ficaria com dinheiro a mais e o estafeta seria cobrado a mais. So ligar depois de o fecho destes pedidos estar corrigido.',
   'dispatch')
on conflict (key) do nothing;

create table if not exists public.bkp_fn_partner_chamar_estafeta_20261005 (
  guardado_em timestamptz not null default now(),
  definicao   text not null
);
alter table public.bkp_fn_partner_chamar_estafeta_20261005 enable row level security;

do $porta$
declare
  v_def text; v_n int;
  v_ancora text := E'BEGIN\n  IF auth.uid() IS NULL TH';
  v_porta  text := E'BEGIN\n  -- [05/10/2026] Interruptor do "parceiro chama estafeta": fica desligado ate o fecho\n  -- destes pedidos estar certo (ver .claude/.ai/missoes/ronda-04-10/pronto/).\n  IF COALESCE((public.get_setting(''dispatch_parceiro_chama_estafeta_ligado'') #>> ''{}'')::boolean, false) IS NOT TRUE THEN\n    RETURN jsonb_build_object(''ok'', false, ''error'', ''indisponivel'');\n  END IF;\n  IF auth.uid() IS NULL TH';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'partner_chamar_estafeta';
  if v_def is null then raise exception 'funcao partner_chamar_estafeta nao existe'; end if;
  if position('dispatch_parceiro_chama_estafeta_ligado' in v_def) > 0 then
    return; -- ja tem a porta
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_ancora, ''))) / length(v_ancora);
  if v_n <> 1 then raise exception 'ancora aparece % vezes (tem de ser 1)', v_n; end if;
  insert into public.bkp_fn_partner_chamar_estafeta_20261005 (definicao) values (v_def);
  execute replace(v_def, v_ancora, v_porta);
end $porta$;
