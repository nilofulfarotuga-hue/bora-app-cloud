CREATE OR REPLACE FUNCTION public.agent_get_store_info(p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_q    text := lower(extensions.unaccent(btrim(COALESCE(p_query, ''))));
  v_res  jsonb;
  v_min  int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF length(v_q) < 2 THEN RETURN jsonb_build_object('ok', false, 'erro', 'escreve o nome da loja'); END IF;
  BEGIN v_min := (public.get_setting('min_order_cents') #>> '{}')::int; EXCEPTION WHEN OTHERS THEN v_min := NULL; END;
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.ord), '[]'::jsonb) INTO v_res FROM (
    SELECT CASE WHEN lower(extensions.unaccent(r.name)) = v_q THEN 0
                WHEN lower(extensions.unaccent(r.name)) LIKE v_q || '%' THEN 1 ELSE 2 END ord,
      jsonb_build_object(
        'loja', r.name,
        'tipo', CASE WHEN r.is_partner THEN 'parceira' ELSE 'compra pelo estafeta' END,
        'categoria', r.category,
        'em_breve', COALESCE(r.coming_soon, false),
        'aceita_pedidos_agora', CASE WHEN COALESCE(r.coming_soon, false) THEN false
                                     ELSE COALESCE((st.v->>'is_open')::boolean, false) AND COALESCE(r.is_online, false) END,
        'em_pausa', COALESCE((st.v->>'em_pausa')::boolean, false),
        'abre', CASE WHEN st.v->>'opens_at' IS NOT NULL THEN COALESCE(st.v->>'opens_dia', '') || ' às ' || (st.v->>'opens_at') END,
        'fecha_em_minutos', (st.v->>'closes_in_minutes')::int,
        'muito_movimento_mais_minutos', CASE WHEN r.busy_until > now() THEN r.busy_extra_minutes END,
        'horario_semana', (SELECT jsonb_object_agg(dn.pt,
             CASE WHEN COALESCE((r.business_hours->dn.k->>'closed')::boolean, false) THEN 'fechado'
                  WHEN r.business_hours->dn.k IS NULL THEN 'sem horário'
                  ELSE (r.business_hours->dn.k->>'open') || '–' || (r.business_hours->dn.k->>'close')
                       || CASE WHEN r.business_hours->dn.k->>'break_start' IS NOT NULL
                               THEN ' (pausa ' || (r.business_hours->dn.k->>'break_start') || '–' || (r.business_hours->dn.k->>'break_end') || ')'
                               ELSE '' END END)
           FROM (VALUES ('mon','segunda'),('tue','terça'),('wed','quarta'),('thu','quinta'),
                        ('fri','sexta'),('sat','sábado'),('sun','domingo')) dn(k, pt)),
        'entrega_gratis_a_partir_de_eur', CASE WHEN r.free_delivery_min_cents IS NOT NULL THEN round(r.free_delivery_min_cents / 100.0, 2) END,
        'taxa_pedido_pequeno_abaixo_de_eur', CASE WHEN NOT COALESCE(r.is_partner, false)
             THEN round(COALESCE(r.min_order_cents_override, v_min) / 100.0, 2) END,
        'tempo_preparo_min', r.takeaway_default_prep_minutes,
        'aceita_reservas_de_mesa', COALESCE(r.reservations_enabled, false),
        'recolha_na_loja', COALESCE(r.takeaway_enabled, false),
        'morada', r.address,
        'aviso_da_loja', NULLIF(btrim(COALESCE(r.about_text, '')), '')) j
      FROM public.restaurants r
      LEFT JOIN LATERAL (SELECT public.is_partner_open(r.id) v) st ON true
     WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)
       AND lower(extensions.unaccent(r.name)) LIKE '%' || v_q || '%'
     ORDER BY 1 LIMIT 5) x;
  RETURN jsonb_build_object('ok', jsonb_array_length(v_res) > 0, 'lojas', v_res,
    'agora_em_portugal', to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'));
END $function$
;
