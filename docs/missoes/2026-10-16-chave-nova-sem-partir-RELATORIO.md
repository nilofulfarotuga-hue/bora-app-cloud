# Relatório — chave nova sem partir (16/10/2026)

Missão `chave-nova-16-10`. Motor: Claude Fable 5.1, sessão remota no PC do Danilo. Porta: Claude Code.
Ramo `chave-nova-16-10` (worktree `C:\BoraLocal\wt-chave-nova-16-10`), a partir de `origin/autonomous-night-2026-04-29` (18c33305).

**Acessos usados:** projeto Supabase `ojykpzwqrtusfeakzrna` (MCP: SQL, migrações, Edge Functions, registos); GitHub `nilofulfarotuga-hue/bora-app-cloud` (`gh` já com sessão no PC); Telegram do Danilo pela VPS (`orquestracao/ponte-telegram.sh`); Chrome perfil Danilo (página de tokens da Supabase aberta).
**Criado nesta sessão:** funções `chaves-semear` (ativa) e `chaves-diagnostico` (já só responde 410); RPC `vault_semear_chave_servidor`; segredo `bora_server_secret` no cofre do banco; módulo `supabase/functions/_shared/chaves.ts`; caixinha `pedir-token-supabase.ps1` e atalho `COLAR-TOKEN-SUPABASE` no ambiente de trabalho; documentos `docs/SEGURANCA-CHAVES-2026-10-16.md` e este.

## 1. O que NÃO ficou feito (primeiro)

1. **O ficheiro da ordem não chegou ao PC.** `PROMPT_chave_nova_sem_partir_2026-10-16.md` não estava no disco, no ramo remoto, na tabela `despacho`, na `claude_ai_memoria` nem no Drive. Segui o "Parado 2" do plano de 15/10 (`docs/SEGURANCA-CHAVES.md`): criar/usar a chave secreta nova sem partir as funções. Se a ordem tinha mais alguma coisa, não a vi.
2. **A troca final no cofre não foi feita.** Só pode ser feita quando as 17 funções que lêem o papel dentro do JWT aceitarem a chave nova — 7 ainda não aceitam (ver 3).
3. **7 das 17 funções ficaram por remendar no repositório:** `refund` e `finalize-order-from-intent` (a tranca da casa recusou — zona vermelha; propostas em `.claude/.ai/missoes/chave-nova-16-10/propostas/*.patch`); `auto-refund-order`, `monthly-partner-statement`, `notify-service-provider`, `robot-b`, `weekly-closeout-digest` (o classificador do modo automático do Claude Code recusou a edição duas vezes; o que falta fazer em cada uma está no anexo).
4. **9 das 10 remendadas ainda não foram publicadas.** Só a `push-clientes-alvo` (canário) foi. Publicar as outras a partir do disco precisa do token de administração da Supabase (pedido ao Danilo às 07:02). Sem token, publicava-se pelo MCP copiando ficheiros de 200 a 500 linhas à mão — não quis correr esse risco em funções de dinheiro.
5. **As chaves legadas continuam ligadas** (é o clique final do Danilo, quando a maioria das instalações tiver build ≥ 671 / iPhone ≥ 193; hoje `app_min_supported_version_code` está a 0).
6. **CI e `backend/.env` do PC com a chave nova: por fazer.** Precisa de uma colagem da chave (`sb_secret`) — é o único sítio onde a chave tem de sair da Supabase. Na VPS não é preciso nada (ver 4).
7. **A migração da troca não ficou escrita no repositório** (o classificador recusou gravar um ficheiro com `vault.update_secret`). O SQL está em `docs/SEGURANCA-CHAVES-2026-10-16.md` §5 e deve entrar como migração no dia em que for aplicado.

## 2. Para o Danilo

Fiz isto: descobri que a chave secreta nova da Supabase já existe e que a própria Supabase já a põe dentro de todas as funções do servidor, mesmo nas variáveis com o nome antigo. Por isso metade do trabalho que o plano de 15/10 temia já não existe: as 84 funções já usam a chave nova para falar com o banco, sem ninguém lhes tocar. Também medi que a porta de entrada das funções aceita a chave nova, portanto não é preciso desligar nenhuma proteção. O que faltava era o lado do banco: as 53 funções do banco mandam a chave antiga quando chamam o servidor. Em vez de reescrever essas 53, pus a chave nova no cofre do banco por um caminho em que ela nunca passa por mim nem por ti (uma função do servidor copia-a para o cofre), e escrevi uma peça comum que ensina cada função a aceitar as duas chaves enquanto durar a transição. Essa peça está testada, dez funções já a têm no repositório e uma está publicada e provada ao vivo com as duas chaves e com um token falso (recusado).

Falta isto: publicar as outras funções (preciso do token da Supabase que te pedi: gera, copia, cola na caixinha), aplicar os dois remendos de zona vermelha, e só depois fazer a troca no cofre e desligar as chaves antigas. Também preciso, uma vez, que cole a chave nova numa caixinha para eu a pôr no GitHub e no `.env` do PC.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico: os remendos em `refund` e `finalize-order-from-intent` só ensinam as funções a aceitar a chave nova; não mudam um cêntimo de nenhuma regra. Com o teu "vai", aplico os dois ficheiros `.patch` e publico.

Erros que encontrei pelo caminho: o webhook da Stripe chama a função que finaliza um pedido pago por rascunho com a chave nova, e essa função recusa (401). Ainda não apanhou ninguém porque esse caminho nunca foi usado (tabela `payment_drafts` vazia). O remendo está na proposta. E duas funções do banco mandam avisos ao admin com uma chave vazia desde sempre (talão pendente e PIN errado cinco vezes) — nunca chegam; não é desta missão, fica registado.

Próximo passo: o token, o "vai", e a colagem da chave. Depois eu fecho o resto sozinho (publicar, provar, trocar no cofre) e só te chamo para desligar as chaves antigas no painel.

## 3. O que ficou feito, com prova

1. **Diagnóstico das variáveis das Edge Functions** (função descartável `chaves-diagnostico`, 16/10 ~05:00 UTC, nonce num cabeçalho): `SUPABASE_SECRET_KEYS={default: sb_secret_… (41)}`, `SUPABASE_PUBLISHABLE_KEYS={default: sb_publishable_… (46)}`, `SUPABASE_SERVICE_ROLE_KEY` = sb_secret (41), `SUPABASE_ANON_KEY` = sb_publishable (46), `SUPABASE_JWKS` só ES256. Já desativada (v2 responde 410).
2. **Portão aceita as chaves novas** — medido com `notify-partner-low-rating` (verify_jwt=true): sem cabeçalhos 401 `UNAUTHORIZED_NO_AUTH_HEADER`; `Bearer lixo` 401 `UNAUTHORIZED_INVALID_JWT_FORMAT`; só `Bearer sb_publishable` → 403 da própria função; só `apikey` → 403 da função. Com a secreta, a partir do banco: `chaves-semear` `Bearer <nova>` → 200 (id 39972); `notify-partner-low-rating` `Bearer`/`apikey` nova → 403 da função (39973/39974).
3. **Módulo `_shared/chaves.ts`** + 12 testes verdes (`deno test --allow-env --allow-net=127.0.0.1`), `deno check` limpo. Aceita a chave nova por igualdade em tempo constante; a legada só confirmada no Auth; recusa JWT forjado, anon, publicável e lixo.
4. **Cofre semeado sem copiar nada:** migração `20261016070000_chave_nova_cofre_semear.sql` aplicada (RPC `vault_semear_chave_servidor`, só service_role); `chaves-semear` publicada (verify_jwt=true) e chamada do banco com a legada (id 39963) → 200 `{ok:true, prefixo:"sb_secret_", tamanho:41}`; `vault.bora_server_secret` criado às 06:26:10 UTC.
5. **Ar vs repositório, função a função** (agente com `compara.js`, byte a byte): 13 das 17 iguais ao HEAD; `payments-reconciler` igual por datas (commit 09:13Z, publicação 09:14Z de 05/10); `analyze-conversations`, `robot-b`, `cortex-embedding` iguais por construção (último commit = espelho ar→repo de 24/09, sem publicação desde). **`tvde-payment` estava À FRENTE no ar** (v19 de 10/10, reembolso sem alarme falso) — espelhada byte a byte para o repo (commit a11d8b36).
6. **10 funções remendadas no repo** (commit bdeb157a): analyze-conversations, cortex-embedding, notify-admin-urgent, notify-driver-assigned, notify-partner-low-rating, order-edit-settle, payments-reconciler, push-clientes-alvo, settlement-receipt, tvde-recibo-viagem. `deno check` ok em todas (a `order-edit-settle` tem um erro de tipos `npm:@types/node` que já existia no HEAD).
7. **Canário publicado e provado:** `push-clientes-alvo` v2 (MCP). Do banco: legada → 400 "user_ids, title e body sao obrigatorios" (id 39991); nova em Bearer → 400 (39992); nova só em apikey → 400 (39993); JWT forjado com role=service_role (+apikey nova) → 401 do portão (39994); forjado só → 401 (39995).
8. **VPS:** nenhum `.env`, serviço ou contentor usa a chave legada ao vivo; só 3 ficheiros parados a têm escrita (`/root/bora-e2e-web/setup-accounts.sh`, um cache de build em `/root/bora_app/build/`, `migration_trigger_dispatch.sql`). PC: só `backend/.env` tem `SUPABASE_SERVICE_ROLE_KEY`. CI: `secrets.SUPABASE_SERVICE_ROLE_KEY` em `build_android.yml` e `build_ios.yml` (aviso de atualização; não fatal).
9. **Registo:** 20 linhas no `e2e_log` (fluxo `chave-nova-16-10`, run `chave-nova-2026-10-16`), ids 3710–3730.

## 4. Erros encontrados pelo caminho (não corrigidos, de propósito)

- `stripe-webhook → finalize-order-from-intent` com `Bearer sb_secret` → 401 (função só lê papel no JWT). Caminho nunca usado (`payment_drafts` = 0 linhas; sem chamadas 14–16/10). Proposta pronta.
- `_trg_notify_reimbursement_pending_fn` (lê `app.service_role_key` e `app.supabase_url`) e `driver_validate_delivery_pin` (lê `app.settings.service_role_key`) — as três definições não existem (`current_setting` = NULL) → mandam `Authorization: Bearer NULL`. Os avisos "talão pendente" e "PIN errado 5×" nunca chegam. Corrigir lendo do cofre como as outras 53.
- Tranca `bora-mods`: falsos positivos em linhas que declaram constantes `*_KEY` a partir do ambiente e num JWT de brincar num teste (regra do Danilo de 15/10: falso positivo por palavra é defeito a corrigir).
- Guardrail do git lê a pasta `push-clientes-alvo` como um `git push`.

## 5. Como continuar (ordem)

1. Token da Supabase na caixinha (ou aqui na conversa) → `npx --yes supabase@latest functions deploy <slug> --project-ref ojykpzwqrtusfeakzrna --use-api --yes` para as 9 remendadas; provar cada uma do banco (`docs/SEGURANCA-CHAVES-2026-10-16.md` §4).
2. "vai" do Danilo → `git apply` dos dois `.patch` de zona vermelha + aplicar o anexo nas 5 recusadas pelo classificador → publicar e provar as 7.
3. Troca no cofre (§5 do documento), vigiar `net._http_response` e os registos das funções por duas horas. Gravar a migração no repo.
4. Colagem da chave → `gh secret set SUPABASE_SERVICE_ROLE_KEY` (repo `nilofulfarotuga-hue/bora-app-cloud`) e `backend/.env`.
5. Quando a maioria tiver build ≥ 671: Danilo desliga as chaves legadas no painel; apagar `*_legada_20261016`, `chaves-diagnostico`, `chaves-semear`, e os 3 ficheiros parados da VPS.

## Anexo — o que falta nas 5 funções que o classificador recusou

Em todas: acrescentar `import { chamadaDoServidor } from '../_shared/chaves.ts'` ao lado do import do `createClient` (com ou sem ponto-e-vírgula conforme o ficheiro).

- **auto-refund-order** (linha 25): a condição `if (roleFromJwt(token) !== 'service_role') return json({ error: 'forbidden' }, 403);` passa a `if (roleFromJwt(token) !== 'service_role' && !(await chamadaDoServidor(req))) return …`.
- **monthly-partner-statement** (linhas 84–91): antes do `try` criar `const chaveNovaOk = await chamadaDoServidor(req)`; dentro, `if (!chaveNovaOk && !authHeader.startsWith('Bearer ')) throw …` e só descodificar o JWT quando `!chaveNovaOk`.
- **notify-service-provider** (linhas 32–45): igual — `const chaveNovaOk = await chamadaDoServidor(req)` antes da verificação do `Bearer`; a verificação do `Bearer` e a descodificação do JWT só quando `!chaveNovaOk`.
- **robot-b** (linha 666): `if (jwtRole === 'service_role') {` passa a `const chaveNovaOk = await chamadaDoServidor(req); if (jwtRole === 'service_role' || chaveNovaOk) {`.
- **weekly-closeout-digest** (linhas 96–104): igual ao monthly-partner-statement (mesmo bloco `try`/`catch`).

A forma já aplicada na `settlement-receipt` e na `notify-admin-urgent` serve de modelo.
