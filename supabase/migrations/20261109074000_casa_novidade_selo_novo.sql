-- Casa & Manutenção — lançamento como NOVIDADE (m11-amigo-rosto-2026-11-09, adendo 3).
-- Ordem do Danilo (09/11/2026 07:02): "deixa publicada como novidade; do jeito que fazemos sempre nas categorias".
--
-- A definição do selo "Novo" no atalho da Casa (home do cliente). Valor: texto 'AAAA-MM-DD' = último dia
-- (relógio de Lisboa) em que o selo aparece; '' = sem selo. A data vive aqui, nunca no código.
--  · a app lê-a por get_setting('casa_novo_ate') (não é segredo; get_setting já está aberta a anon e
--    authenticated para chaves não secretas);
--  · o painel muda-a em Casa > Configurações > Novidade, pela admin_casa_guardar_definicao (que só aceita
--    chaves casa_* que já existam e com o mesmo tipo — por isso a chave nasce aqui, como texto);
--  · não é dinheiro: não entra no grupo de comissão/promoção e não reabre os valores autorizados.
-- Nasce VAZIA (sem selo). Liga-se na publicação, depois de casa_enabled (docs/casa/PUBLICACAO2-casa.md).
-- Idempotente: correr duas vezes não muda nada.

insert into public.platform_settings (key, value, description, category, is_secret)
values ('casa_novo_ate', to_jsonb(''::text),
        'Selo "Novo" no atalho da Casa até (AAAA-MM-DD, hora de Lisboa; vazio = sem selo)',
        'casa', false)
on conflict (key) do nothing;
