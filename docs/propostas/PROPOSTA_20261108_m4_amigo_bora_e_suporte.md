# Para o Claude.ai publicar — Amigo Bora v1 + adendo 1 do suporte (08/11/2026)

Ramo: `ai/2026-11-08-m4-amigo-bora` (worktree `C:/BoraLocal/wt-m4-2026-11-08`). Nada disto está no ar:
a trava do modo automático só deixa a sessão do PC enviar o ramo de ensaio. Zona verde: nenhuma escrita
em pedidos nem em dinheiro.

## Ordem para publicar

1. **Migrações** (idempotentes; provadas no PGlite 50/50, duas voltas seguidas — `.claude/.ai/provas/m4-amigo-bora-2026-11-08/prova_sql_pglite.txt`):
   1. `supabase/migrations/20261108210000_amigo_bora_v1.sql` — definições do Amigo, `assistant_client_profile`,
      `assistant_deixas`, `assistant_comparacoes`, RPCs `assistant_amigo_*` e `admin_amigo_*`, cron
      `amigo-bora-perfis` (minuto 23 de cada hora), faixa permanente do assistente desligada (cópia
      `bkp_home_banners_assistente_20261108`), robôs `edge-amigo` e `edge-amigo-perfil` em `claude_robos`.
   2. `supabase/migrations/20261108220000_suporte_conversa_admin.sql` — avisos do suporte apontam para
      `/admin/support/sessions/<id>` (push leva o mesmo link), avisos antigos corrigidos (cópia
      `bkp_admin_notifications_suporte_20261108`), papel `admin` nas mensagens, modo `admin` nas sessões,
      RPCs `admin_suporte_sessoes / _conversa / _responder / _devolver`.
2. **Edge Functions** (as três passam `deno check`; 19 testes Deno verdes):
   - `client-assistant` (v11; com a personalidade desligada ou sem a migração 1 comporta-se como a v10;
     leva também o `_shared/claude.ts` do repo, que já estava mais novo que o publicado nesta função).
   - `assistant-profile-refresh` (NOVA, `verify_jwt=false`: só aceita a chave do servidor ou um admin).
   - `support-chatbot` (pedir pessoa → WhatsApp da Bora 937 501 673 + escala + aviso; modo admin cala o robô).
3. **App** (as 3: Play, App Store, web) a partir do ramo, depois de juntar ao principal.

## Provas a fazer depois de publicar (as que o PC não podia fazer)

```sql
-- 1) Definições e cron
select key, value from platform_settings where key in
 ('assistant_personality_enabled','deixa_promocoes_enabled','assistant_amigo_model','assistant_amigo_welcome_text');
select jobname, schedule from cron.job where jobname = 'amigo-bora-perfis';
-- 2) Avisos antigos já com o link novo (o do S., sessão 24c369e0…)
select event_type, deep_link, count(*) from admin_notifications
 where event_type in ('support_user_message','support_ticket_new') group by 1,2;
-- 3) Perfil gerado (depois de chamar a função ou do cron das :23)
--    POST /functions/v1/assistant-profile-refresh {"user_id":"<id>"} com a chave do servidor
select user_id, perfil->'habitos' habitos, perfil->'lojas_favoritas' lojas, fonte, modelo, custo_usd, atualizado_em
  from assistant_client_profile order by atualizado_em desc limit 5;
-- 4) Comparação guardada e deixas
select app, origem, vencedor, total_outra_cents, total_bora_cents, diferenca_cents, jsonb_array_length(itens) n
  from assistant_comparacoes order by criado_em desc limit 5;
select tipo, texto, mostrada_em, clicada_em from assistant_deixas order by mostrada_em desc limit 5;
-- 5) Custo por robô
select robo, modelo, count(*), round(sum(custo_usd),4) usd, round(avg(custo_usd),5) med
  from ia_gastos where robo in ('edge-assistente','edge-amigo','edge-amigo-perfil') and quando > now() - interval '1 day'
 group by 1,2;
```

Prova do "costume" (sexta): a conta `demo.cliente@bora.app` só tem 1 pedido entregue (quinta 29/10, Auchan).
Para o teste da sexta são precisos 3 pedidos de teste entregues em sextas à noite na mesma loja
(`is_test_order=true`, pagamento em dinheiro), criados pela skill `seed-demo-data` (o PC não escreve em
`orders`). Depois: `assistant-profile-refresh {"user_id": <demo>}` → abrir o Amigo numa sexta depois das 17h →
"Hoje é sexta. Queres o do costume do …?" → "Sim, repete" → carrinho cheio → ecrã de pagamento (NÃO pagar).

Prova da comparação: mandar ao Amigo a imagem `.claude/.ai/provas/m4-amigo-bora-2026-11-08/carrinho_outra_app_teste.png`
(carrinho sem marca: Gyoza 4,50, Combinado Tradicional 14,00, Coca-Cola 2,50, total 25,10 €) com
"compara com a Glovo" → cartão com as linhas e a conta; linha nova em `assistant_comparacoes`.

Prova do suporte: com uma conta de teste escrever "falar com assistente" no chat de ajuda → resposta com
o WhatsApp 937 501 673 e o botão "Abrir o WhatsApp da Bora"; sessão `escalated=true`
(`escalation_reason='pediu_pessoa'`); aviso com `deep_link=/admin/support/sessions/<id>`; tocar no aviso
(painel web e telemóvel) abre a conversa; responder no painel → a mensagem aparece no chat da app sem
recarregar e o robô não responde às mensagens seguintes até "Devolver ao robô".
