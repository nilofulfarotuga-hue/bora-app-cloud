# Proposta de publicação — M11, o Amigo com rosto (09/11/2026)

As travas (trava do modo automático e bora-tranca) estão ligadas e barraram, com a mensagem
"publica o Claude.ai", a migração, a função do servidor e o envio git. Está tudo pronto e
provado no ramo `ai/2026-11-09-m11-amigo-rosto` (só no PC: worktree
`C:\BoraLocal\wt-m11-2026-11-09`; cópia em `C:\BoraLocal\missoes\m11-amigo-rosto-2026-11-09\m11.bundle`).
Nada disto mexe em dinheiro, preços, Stripe, carteira, dispatch nem pedidos.

## Ordem (cada passo tem a sua prova)

1. **Migração** `supabase/migrations/20261109060000_amigo_rosto.sql` (MCP `apply_migration`
   ou `supabase db query -f` + registo). Idempotente, sem DROP/DELETE; faz cópia
   `bkp_platform_settings_amigo_20261109` antes. Prova depois:
   `select key, value from platform_settings where key like 'amigo\_%';` → 5 linhas, e
   `select public.admin_amigo_rosto_overview(30);` como admin.
   Já provada em PGlite (17/17): `docs/amigo/provas/pglite-amigo-rosto-2026-11-09.txt`.
2. **Edge `client-assistant`** a partir do ramo (CLI `functions deploy client-assistant --use-api`,
   verify_jwt como está). Antes de publicar confirmar que o que está no ar é a v16 = repo de
   origin (a 09/11 05:25 era igual: index.ts e amigo.ts idênticos). Muda: identidade do Amigo
   "amigo para tudo" sem "assistente de compras" (adendo 1-B), etiqueta `[cara:...]` → campo
   opcional `emocao`, saudação com o habitual. Apps antigas ignoram o campo novo.
   Prova depois: 5 conversas de teste sem "de compras" e o campo `emocao` na resposta.
3. **App nas 3**: juntar o ramo em `autonomous-night-2026-04-29` JUNTO com o commit
   `884e3def` (barra do parceiro, está só em `origin/ai/2026-11-08-m10-publicar`; junta-se sem
   conflitos). Atenção: o 884e3def leva capturas para `.claude/.ai/provas/m10-2026-11-08/`
   (uma chama-se `3-login-cliente.png`): ver se têm dados pessoais antes de irem para o repo
   público. Depois `git push origin autonomous-night-2026-04-29`; o CI sobe o versionCode
   (Android acima de 718) e publica a web; iPhone pelo TestFlight como a M10.
4. Só depois de as lojas terem a versão: `app_latest_version_code` / iOS como a M10.

## O que a app faz sem os passos 1 e 2

Funciona: sem as definições no servidor vale o padrão (rosto ligado, com camisa, voz ligada,
velocidade 1, mosaico ligado); sem o campo `emocao` a cara decide-se pelo estado; a contagem de
uso falha em silêncio; o painel mostra "migração por aplicar". Mas o Amigo continuaria a
poder dizer "assistente de compras" até o passo 2.
