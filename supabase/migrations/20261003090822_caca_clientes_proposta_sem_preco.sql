-- Os emails do caca-clientes nao levam preco (pedem conversa): a proposta pode nao ter preco_mes_eur.
alter table public.prospect_propostas alter column preco_mes_eur drop not null;
