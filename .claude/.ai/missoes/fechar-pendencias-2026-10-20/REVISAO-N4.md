# Revisão N4 (maker/checker) — 21/10/2026

> Revisor de contexto limpo. Não fiz o trabalho do N4; tentei provar que alguma coisa legítima
> deixou de funcionar em produção desde as 21:00. Não fiz commit, push, migração nem deploy.
> RAM medida no arranque: 1550 MB disponíveis (portão leve 400 MB — ok).
> Projeto `ojykpzwqrtusfeakzrna`. Commit revisto: `4785b391` (ramo `seguranca-21-10`).
> Horas em UTC (Lisboa = UTC+1).

Como provei sem incomodar ninguém:
- Chamadas reais às 3 Edges feitas a partir do banco (`net.http_post`), **com os mesmos cabeçalhos que
  os chamadores reais usam**, mas para um utilizador que não existe (`00000000-…-c0de`). A Edge
  responde `no_fcm_token` e não manda nada a ninguém.
- Tudo o resto em rollback (`DO $$ … RAISE EXCEPTION 'RESULT %' $$`), com `SET LOCAL ROLE` e
  `request.jwt.claims` a imitar o papel real.

---

## (A) `notify-admin-message`, `notify-cleaner`, `notify-washer` — só servidor ou admin

**No ar (get_edge_function):** `notify-admin-message` v3 (`verify_jwt=true`, publicada 19:58:32 UTC) e
`notify-cleaner` v11 (`verify_jwt=true`, 20:00:30 UTC) trazem o portão `exigirServidorOuAdmin`
igual ao do repo. O caminho "servidor" (`chamadaDoServidor`) é o MESMO que já existia antes em
`exigirCallerOk`; só saiu o "qualquer utilizador com sessão".

**Quem chama:**
- **App Flutter (cliente, estafeta, parceiro, limpeza, lavagem, painel):** nenhuma chamada.
  `grep` em `lib/` só encontra comentários; a lista completa de `functions.invoke('…')` (50 nomes)
  não tem nenhuma das 3; nenhuma versão antiga da app as invocou (`git log --all -G` vazio).
- **Outras Edge Functions:** nenhuma (o único nome dinâmico, no `support-chatbot`, é `tvde-dest-change`).
- **Banco (7 funções SECURITY DEFINER, todas por `pg_net`):**
  - `Bearer <vault.service_role_key>` (JWT legado): `_carwash_notify_user` → washer;
    `_cleaning_notify_user`, `_cleaning_cron_offer_reping` → cleaner; `admin_send_push_notification`
    (o botão do painel), `motorista_docs_alerta_diario`, `tvde_cancel_ride` → admin-message.
  - Só `apikey: <vault.sb_secret_backend>`, **sem** `Authorization`: `_provider_atividade_avisar` → admin-message.
- **Painel admin:** não chama as Edges direto; usa `admin_send_push_notification` (banco, chave do cofre).
  Mesmo que chamasse, o admin `c9fccf85` tem `app_metadata.role = admin` (é o que o portão novo lê).

**Prova (respostas reais, 20:23:56 UTC):**
```
58135 washer   Bearer JWT legado      -> 200 {"ok":false,"reason":"no_fcm_token"}
58136 cleaner  Bearer JWT legado      -> 200 {"ok":false,"reason":"no_fcm_token"}
58137 admin-msg Bearer JWT legado     -> 200 {"ok":false,"reason":"no_fcm_token"}
58138 admin-msg só apikey sb_secret   -> 200 {"ok":false,"reason":"no_fcm_token"}
58158/58159/58160  as 3 com Bearer sb_secret -> 200 {"ok":false,"reason":"no_fcm_token"}  (pronto para a troca da chave do cofre)
58162 controlo: cleaner com JWT anon  -> 403 {"ok":false,"error":"forbidden"}   (o portão está mesmo ligado; os 200 valem)
```
Desde a publicação (19:58:32 UTC) até 20:31 UTC: 83 respostas do `pg_net`, **0 recusas**
(`forbidden`/`unauthorized`/`Missing authorization`); o único não-200 é o meu controlo anon.

**Veredicto (A): nada partiu.**

## (B) Balde `avatars` — escrita só na própria pasta

**Quem escreve:** `profile_screen.dart` (caminho `'$userId/avatar.jpg'`, `userId = supabase.auth.currentUser?.id`,
`upsert: true`; apagar foto = `remove(['$uid/avatar.jpg'])`), `provider_upload_service.dart`
(`'$uid/avatar.jpg'`, candidatura de limpeza/lavagem). Fallback `upload-avatar` e `delete-account`
usam a chave de serviço (não passam pelas políticas). Painel só lê pelo URL público.
Em toda a história da app o caminho foi sempre `<uid>/avatar.jpg`. No balde: 16 ficheiros, todos em
`<uuid>/…`; 10 com dono = pasta, 6 sem dono (feitos pelo servidor em maio). Balde `public = true`.

**Políticas no ar:** 4 políticas `avatars_propria_pasta_*` (SELECT/INSERT/UPDATE/DELETE) para
`authenticated`, todas com `(storage.foldername(name))[1] = auth.uid()::text`.

**Prova em rollback** (dono real da foto mais recente):
```
RESULT {"insert_propria_pasta": 1, "select_propria": 2, "insert_pasta_alheia": "ERRO 42501", ...}
RESULT {"update_propria": 1, "update_alheia": 0, "anon_insert": "ERRO 42501"}
```
(Uma tentativa minha de imitar o `ON CONFLICT` deu `42P10` por eu ter escolhido mal o índice —
erro do meu teste, não da política; o caminho de substituir a foto foi provado pelo `update_propria: 1`.)

**Veredicto (B): nada partiu.** Limite: não fiz um upload HTTP real com sessão de utilizador (não há
sessão de teste à mão); a prova é a das políticas em rollback.

## (C) 12 funções SECURITY DEFINER fechadas (só `service_role` + dono `postgres`)

**ACL no ar** das 12: `{postgres=X/postgres,service_role=X/postgres}`.

**Quem chama:**
- **App/painel (`lib/`):** nenhuma das 12 por `.rpc(` (grep vazio).
- **Dentro do banco:** `_reservas_pro_autosetup` ← gatilho `trg_reservas_autosetup` em `restaurants`
  (`_trg_reservas_autosetup_fn`, definer, dono postgres); `encomenda_telefone_resumo` ←
  `admin_listar_encomendas_telefone`, `pedido_total_balcao`, `_encomenda_telefone_alertar` (todas definer, dono postgres).
- **Crons:** `appt-expire-pending-payment` (71) e `assinaturas-aviso-renovacao` (82) correm como `postgres`.
- **Edge:** `support-chatbot` chama `agent_propose_action` com `adminClient = createClient(url, secretKey())`.
- **Maestro:** só o agente, pelo MCP `execute_sql` (postgres). Nenhum script chama `maestro_*`.

**Provas:**
```
Parceiro demo liga reservas (role authenticated, rollback):
RESULT {"quem":"authenticated","linhas_update":1,"salas":1,"mesas":6,
        "direto":"42501 permission denied for function _reservas_pro_autosetup"}
Admin (authenticated) -> pedido_total_balcao(<último pedido>) = "17.16"   (chama encomenda_telefone_resumo por dentro)
REST com sb_secret        -> 200 null    (58150)
REST com JWT service legado -> 200 null  (58151)
REST com anon (controlo)  -> 401 {"code":"42501","message":"permission denied for function encomenda_telefone_resumo"} (58152)
service_role (rollback): agent_propose_action -> 23503 FK (entrou); maestro_next_backlog_item -> {"ok":false,"reason":"SEM_ITENS_PENDENTES"};
                         cortex_mark_ordem_criada -> P0001 pid_invalido (entrou)
cron 71 depois da migração (20:04:37): succeeded 20:10:00 e 20:20:00 UTC, "1 row"
```
`admin_listar_encomendas_telefone` não tem linhas (`encomendas_telefone` = 0), por isso o caminho
interno foi provado pelo `pedido_total_balcao`. `support_pending_actions` tem 0 linhas (o chatbot
nunca propôs nada), mas o mecanismo (chave secreta → service_role) está provado acima.

**Veredicto (C): nada partiu por causa do N4.**

## (D) `notify_admin_event` traduz a severidade

**Prova em rollback:**
```
RESULT {"warning":"medium","warn":"medium","WARNING":"medium","info":"low","error":"high",
        "low":"low","medium":"medium","high":"high","critical":"critical","urgente":"ERRO 23514"}
```
Os 4 valores que já valiam ficam iguais; os 4 que rebentavam passam; um valor desconhecido continua a
falhar como antes (não é regressão). CHECK da tabela: só low/medium/high/critical; nenhuma linha
antiga com info/warning. 2 avisos novos gravados depois da migração. ACL igual
(`postgres`, `service_role`).

**Veredicto (D): nada partiu.**

---

## Erro encontrado pelo caminho (NÃO foi o N4)

**A sincronização do Córtex na VPS está parada desde 04/09.** O script
`.claude/scripts/hermes-cortex-proposals-sync.sh` (cron de 10 em 10 min na VPS) chama
`cortex_proposal_sync_upsert`, `cortex_list_approved_pids`, `cortex_get_auth_for_pid` e
`cortex_mark_ordem_criada` com a **chave anon** (`SUPABASE_ANON_KEY` do `.env` da VPS).
A anon já não tinha permissão em nenhuma das quatro **antes** do N4 (as duas que o N4 não tocou
também estão sem anon: `cortex_list_approved_pids`, `cortex_get_auth_for_pid` → `anon=false`), e
a última linha sincronizada em `cortex_red_proposals` é de **2026-09-04 14:20 UTC**. O N4 só tirou o
`authenticated`, que este script não usa. Para voltar a funcionar o script tem de usar uma chave de
servidor (decisão à parte; não mexi).

## Reversão mínima (só se um dia for preciso — hoje não é)

- (A) voltar a publicar a versão anterior das 3 Edges com `exigirCallerOk` (commit `14fb9994`).
- (B) recriar as 4 políticas antigas (estão no cabeçalho da migração `20261021200446_…`).
- (C) `GRANT EXECUTE ON FUNCTION <assinatura> TO authenticated;` para a função em causa.
- (D) `CREATE OR REPLACE` com o corpo antigo (md5 antes: `78ec2a175dcb6b1503d71aaccf8c8fbe`).

VEREDICTO: SIM (nada partiu)
