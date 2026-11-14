-- Limpeza da fila do radar de videos (missao sistema-conteudo-14-11, bloco 4.2).
-- So DML (UPDATE em radar_videos, INSERT em despacho). Nunca DELETE: fechar = mudar veredito/acao.
-- Regras: pagina ideias-videos-danilo, seccao "09/11/2026 — REGRA NOVA M10" (pendente nota >= 8 vira
-- UMA tarefa por tema; dinheiro, precos, pagamentos, RLS/seguranca e contas ficam para o Danilo).
do $$
declare
  r record;
  v_id bigint;
  v_lista text;
  v_verm text := '(pago|paga |preço|preco|assinatura|stripe|cart[aã]o|pagamento|comiss|carteira|rls|seguran|criar conta|abrir conta|conta nova|publicar|cr[eé]dito|€|\$|r\$|cobrar|vend[ae]|mensalidade|clientes|atualizar o hermes)';
begin
  -- 1) duplicados: mesmo titulo (normalizado) ou mesmo assunto (mesma proposta/tarefa citada na acao)
  with base as (
    select youtube_id, veredito, nota_utilidade n, recolhido_em,
           left(regexp_replace(lower(titulo), '[^a-z0-9]+', '', 'g'), 40) tnorm,
           (regexp_match(acao, '(radar-tarefa-[a-z0-9-]+|prop-[0-9a-f]{8}|m8-[a-z0-9-]+)'))[1] k
    from radar_videos),
  d_t as (
    select youtube_id, first_value(youtube_id) over (partition by tnorm
             order by (veredito in ('novo','pendente')), n desc nulls last, recolhido_em) keep
    from base where tnorm <> ''),
  d_k as (
    select youtube_id, first_value(youtube_id) over (partition by k
             order by n desc nulls last, recolhido_em) keep
    from base where k is not null and veredito in ('novo','pendente')),
  dups as (
    select youtube_id, keep from d_t where keep <> youtube_id
    union
    select youtube_id, keep from d_k where keep <> youtube_id)
  update radar_videos v
     set veredito = 'duplicado',
         acao = '[duplicado 14/11 de ' || d.keep || '] ' || coalesce(v.acao, ''),
         revisto_em = now(), atualizado_em = now()
    from (select distinct on (youtube_id) youtube_id, keep from dups) d
   where v.youtube_id = d.youtube_id and v.veredito in ('novo','pendente');

  -- 2) verdes (sem dinheiro, sem contas, sem custo) com nota >= 8: UMA tarefa por tema no despacho
  for r in
    select tema, count(*) n from radar_videos
     where veredito in ('novo','pendente') and nota_utilidade >= 8
       and para in ('sistema','filme','bora','em_dia')
       and lower(coalesce(acao,'') || ' ' || coalesce(ideias::text,'') || ' ' || coalesce(titulo,'')) !~ v_verm
     group by tema order by 2 desc
  loop
    select string_agg('- ' || coalesce(link, 'https://www.youtube.com/watch?v=' || youtube_id) || ' (' || para || ', nota ' ||
                      nota_utilidade || '): ' || left(coalesce(acao, titulo), 160), E'\n')
      into v_lista
      from (select * from radar_videos
             where veredito in ('novo','pendente') and tema = r.tema and nota_utilidade >= 8
               and para in ('sistema','filme','bora','em_dia')
               and lower(coalesce(acao,'') || ' ' || coalesce(ideias::text,'') || ' ' || coalesce(titulo,'')) !~ v_verm
             order by nota_utilidade desc, recolhido_em desc limit 15) t;

    insert into despacho (origem, para, tipo, titulo, tarefa, prioridade, estado)
    values ('agente', 'emerson', 'tarefa',
            'radar: aplicar o que e verde — ' || r.tema || ' (' || r.n || ' videos)',
            'MISSAO: radar-tarefa-' || r.tema || E'\n' ||
            'Da limpeza da fila do radar (14/11). Estes videos passaram nas regras do radar e sao verdes: ' ||
            'sem dinheiro, sem contas novas, sem custo, sem publicar, sem mensagens para fora. Para cada um: ' ||
            'ler a acao, fazer a parte segura e reversivel (estudar, escrever o guia ou o plano, testar numa copia) ' ||
            'e escrever o resultado. Proibido: atualizar ou reiniciar o Hermes, instalar coisas pesadas, mexer em ' ||
            'precos, pagamentos, carteiras, RLS. Se um passo precisar disso, fica precisa-danilo com o motivo.' || E'\n' ||
            'Os 15 primeiros (a lista completa: radar_videos com acao a comecar por "[despacho #" e o id desta linha):' || E'\n' ||
            v_lista || E'\n' ||
            'FEITO quando: resultado nesta linha com o que foi feito por video e prova (ficheiro, e2e_log ou SELECT).',
            40, 'aberta')
    returning id into v_id;

    update radar_videos
       set veredito = 'despachado',
           acao = '[despacho #' || v_id || ' 14/11] ' || coalesce(acao, ''),
           revisto_em = now(), atualizado_em = now()
     where veredito in ('novo','pendente') and tema = r.tema and nota_utilidade >= 8
       and para in ('sistema','filme','bora','em_dia')
       and lower(coalesce(acao,'') || ' ' || coalesce(ideias::text,'') || ' ' || coalesce(titulo,'')) !~ v_verm;
  end loop;

  -- 3) o que fica: motivo escrito na acao (o veredito nao muda; entram nas opcoes numeradas da noite)
  update radar_videos
     set acao = '[fica 14/11: ' ||
                case when para = 'dinheiro'
                       or lower(coalesce(acao,'') || ' ' || coalesce(ideias::text,'') || ' ' || coalesce(titulo,'')) ~ v_verm
                     then 'precisa do Danilo, mexe em dinheiro, vendas, contas ou custo'
                     when coalesce(nota_utilidade, 0) < 8 then 'nota abaixo de 8, a regra M10 so faz tarefa com nota 8 ou mais'
                     else 'precisa do Danilo' end || '] ' || coalesce(acao, ''),
         atualizado_em = now()
   where veredito in ('novo','pendente') and coalesce(acao, '') not like '[fica 14/11:%';
end $$;
