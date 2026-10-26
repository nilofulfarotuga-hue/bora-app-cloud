-- 26/10/2026 (geral-sabado-24-10, bloco 6): as conversas que o Emerson lê levam a língua e a
-- categoria do prospect, para responder na língua do cliente e com os factos certos (empresas de
-- obras = assistente de orçamentos). Preço e contrato continuam a só sair com o "manda" do Danilo.
create or replace function public.carteiro_threads(p_chave text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'vault'
as $function$
begin
  perform public._caca_chave_ok(p_chave);
  return coalesce((select jsonb_agg(jsonb_build_object('proposta_id', r.id, 'prospect_id', r.prospect_id, 'nome', p.nome, 'para', r.destinatario,
                    'thread_id', r.gmail_thread_id, 'assunto', r.assunto, 'lingua', p.lingua, 'categoria', p.categoria))
            from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
           where r.estado = 'enviada' and r.gmail_thread_id is not null), '[]'::jsonb);
end $function$;
