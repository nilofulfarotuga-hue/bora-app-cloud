---
id: licao-dual-owner-column
tipo: licao
origem: [supabase/functions/register-partner · RPCs partner_* · mega-fix 2026-07-18 Parte 3]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — `restaurants` tem DUAS colunas de dono (`user_` e `user_id`); ler/gravar sempre AMBAS

**Problema.** Parceiros criados após ~junho/2026 nasceram "sem dono funcional": conseguiam
cadastrar-se mas nenhuma RPC de parceiro os reconhecia (não recebiam pedidos, não viam o
dashboard como donos). O admin também não os associava a um utilizador.

**Causa real.** A tabela `restaurants` acumulou **duas** colunas para o mesmo conceito de dono,
por legado nunca unificado:
- `user_` — coluna antiga; é a que TODAS as RPCs de parceiro leem
  (`partner_takeaway_accept`, `_reservas_pro_assert_partner`, `partner_dispatch_decision`, …).
- `user_id` — coluna nova; é a que o cadastro (`register-partner/index.ts`, comentário
  "BUG-2 FIX") passou a gravar.

O insert gravava só `user_id`; as RPCs liam só `user_` → o dono existia numa coluna e era
procurado na outra. Silencioso: nenhum erro, só ausência de resultados.

**Regra generalizável.** Enquanto as duas colunas coexistirem:
1. Todo **insert/update** de `restaurants` grava o dono nas DUAS (`user_` E `user_id`).
2. Toda **RPC nova** que filtra por dono lê AMBAS: `WHERE user_ = auth.uid() OR user_id = auth.uid()`.
3. Proteção permanente: trigger `BEFORE INSERT OR UPDATE` que espelha
   `user_ := COALESCE(user_, user_id)` e `user_id := COALESCE(user_id, user_)`.
4. Só remover uma coluna depois de uma migration de unificação deliberada (backfill + trocar
   todas as leituras) — nunca "de repente".

Quando existirem duas colunas para a mesma coisa, assume que metade do código usa uma e metade
usa a outra até prova em contrário. Escreve nas duas, lê das duas.
