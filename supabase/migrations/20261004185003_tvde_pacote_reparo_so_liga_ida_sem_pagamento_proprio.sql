-- 2026-10-04 (revisão de contexto limpo): a procura automática da ida pendente aceitava
-- qualquer corrida por cartão/MB Way por pagar. Uma corrida AVULSA à espera do seu próprio
-- pagamento podia ser ligada a um vale órfão e despachada como perna pré-paga (e o cliente
-- ainda pagava o cartão dela). A ida do pacote nunca tem PaymentIntent próprio nem é perna
-- de volta: a procura passa a exigir as duas coisas. Patch por âncora, com contagem.
--
-- Prova em rollback (04/10): avulsa com PI próprio -> vale.out=null, avulsa.pay inalterado,
-- admin alertado; ida do pacote sem PI -> vale.out_ok=true, ida.pay=succeeded.
do $patch$
declare
  v_def text; v_new text;
  v_anc constant text := E'       AND COALESCE(r.payment_method,''cash'') IN (''card'',''mbway'')\n       AND r.created_at > now() - interval ''45 minutes''';
  v_adm text; v_adm_new text;
  v_anc_adm constant text := E'             and coalesce(r.payment_method,''cash'') in (''card'',''mbway'')\n             and r.created_at > now() - interval ''45 minutes''';
begin
  insert into public.bkp_fn_tvde_roundtrip_20261004 (proname, definicao)
  values ('tvde_create_roundtrip_credit@antes_patch_pi_null',
          pg_get_functiondef('public.tvde_create_roundtrip_credit(uuid,uuid,integer,text)'::regprocedure));

  v_def := pg_get_functiondef('public.tvde_create_roundtrip_credit(uuid,uuid,integer,text)'::regprocedure);
  if (length(v_def) - length(replace(v_def, v_anc, ''))) / length(v_anc) <> 1 then
    raise exception 'ancora da funcao do vale: esperava 1 ocorrencia';
  end if;
  v_new := replace(v_def, v_anc,
    E'       AND COALESCE(r.payment_method,''cash'') IN (''card'',''mbway'')\n       AND r.payment_intent_id IS NULL\n       AND COALESCE(r.is_return_leg, false) = false\n       AND r.created_at > now() - interval ''45 minutes''');
  execute v_new;

  v_adm := pg_get_functiondef('public.admin_tvde_pagos_sem_corrida(integer)'::regprocedure);
  if (length(v_adm) - length(replace(v_adm, v_anc_adm, ''))) / length(v_anc_adm) <> 1 then
    raise exception 'ancora da lista admin: esperava 1 ocorrencia';
  end if;
  v_adm_new := replace(v_adm, v_anc_adm,
    E'             and coalesce(r.payment_method,''cash'') in (''card'',''mbway'')\n             and r.payment_intent_id is null\n             and coalesce(r.is_return_leg, false) = false\n             and r.created_at > now() - interval ''45 minutes''');
  execute v_adm_new;
end $patch$;
