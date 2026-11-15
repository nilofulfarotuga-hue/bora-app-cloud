-- PROPOSTA (missão app-15-11, 15/11/2026; achado do Juiz). Aplica a Claude.ai com execute_sql.
-- Corrige 2 dos 30 trechos de ajuda que já estão no servidor (tipo 'ajuda', aplicados das caixas 25-27):
--   * "Cancelar um pedido": dizia que depois de o estafeta recolher "já não dá para cancelar". O servidor
--     (client-cancel-order + platform_settings, lido 15/11) deixa cancelar, mas custa o valor total.
--     Regras em vigor: antes de um estafeta aceitar 0 € (cancel_fee_before_dispatch_cents = 0); depois de
--     aceitar 2,50 € (cancel_fee_after_accept_cents = 250); depois de recolher o valor total
--     (cancel_fee_after_pickup_ratio = 1); "pronto para levantar" (takeaway) não se cancela.
--   * "Mudar o nome do perfil": dizia que a foto muda em Perfil > Editar perfil; muda no ecrã Perfil.
-- O texto novo é o de docs/ajuda/ajuda-clientes.md deste ramo. Os vetores ficam vazios e o
-- agendamento embeddings-gte-manter (de 2 em 2 min) volta a gerá-los.
-- Só a tabela de ajuda dos robôs; nada de dinheiro.

create table if not exists public.bkp_support_knowledge_chunks_20261115 as
  select k.* from public.support_knowledge_chunks k
   where k.source_type = 'ajuda' and k.source_file = 'docs/ajuda/ajuda-clientes.md'
     and k.section_title in ('Cancelar um pedido', 'Mudar o nome do perfil');
alter table public.bkp_support_knowledge_chunks_20261115 enable row level security;
revoke all on public.bkp_support_knowledge_chunks_20261115 from public, anon, authenticated;

update public.support_knowledge_chunks k
   set chunk_text = v.x,
       content_hash = encode(extensions.digest(convert_to(v.x, 'UTF8'), 'sha256'), 'hex'),
       embedding = null,
       embedding_gte = null,
       indexed_at = now()
  from (values
    ('Cancelar um pedido', $aj$Ajuda Bora (Clientes) — Cancelar um pedido

Podes cancelar na página do pedido. Enquanto nenhum estafeta aceitou o pedido, cancelar é grátis. Depois de um estafeta aceitar, cancelar custa 2,50 €. Depois de o estafeta recolher o pedido, cancelar custa o valor total do pedido (não há reembolso). A app mostra sempre o custo antes de confirmares. Um pedido para ir buscar que já está pronto já não se cancela.$aj$),
    ('Mudar o nome do perfil', $aj$Ajuda Bora (Clientes) — Mudar o nome do perfil

O nome do teu perfil não se muda na app. Para mudar o nome, fala com o Suporte e a equipa trata disso. A foto mudas tu no ecrã Perfil, tocando na câmara por cima da foto. O email é o teu acesso à conta e não se altera.$aj$)
  ) as v(titulo, x)
 where k.source_type = 'ajuda' and k.source_file = 'docs/ajuda/ajuda-clientes.md' and k.section_title = v.titulo;

-- PROVA: select section_title, left(chunk_text, 90), embedding_gte is not null as com_vetor
--           from public.support_knowledge_chunks where source_type = 'ajuda'
--            and section_title in ('Cancelar um pedido', 'Mudar o nome do perfil');
--         (2 linhas com o texto novo; com_vetor passa a true em ~2 min)
