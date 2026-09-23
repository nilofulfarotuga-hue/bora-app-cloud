⚠️ MODO PROTECÇÃO TOTAL ⚠️
MOTOR: OPUS (Claude Code no PC, com --chrome) — continuação de jev-decisor-2026-09-23.
Invoca primeiro o CEO-AI (.claude/skills/ceo-ai/) e lê PADRAO_BORA.md e a skill protocolo-missao-bora.
run_id / fluxo e2e_log: `jev-decisor-2026-09-23-b` (uma linha por passo, com prova).

PONTO EXACTO ONDE FICOU: tudo do lado da Bora está no ar (Edge Function `decidir` v4, tabela
`decisoes`, 4 regras em sombra, pg_cron `decisor-varrer`, ecrã admin "Decisões (Jev)"). Falta só
o que precisa do Chrome do PC. Relatório: `JEV-DECISOR-2026-09-23.md` na raiz.

PASSO 1 — Chave do Jev. Abre console.typesafe.ai no Chrome (perfil Bora), "Continue with Google"
com a sessão já iniciada de boraappbora@gmail.com, cria a chave em /keys. Grava no Vault:
`select vault.create_secret('<chave>', 'typesafe_api_key', 'Jev TypeSafe — decisor');` (via MCP
execute_sql; nunca no repo, nunca no e2e_log). Regista os limites/preços que a consola mostrar.
Se pedir palavra-passe nova, captcha ou cartão: página aberta, linha no Telegram, e paras aqui.

PASSO 2 — Prova de vida: `select public.decisor_chave_typesafe() is not null;` e uma chamada a
`decidir` com `"motor":"jev"` (ver exemplo em `.claude/.ai/provas/jev-decisor-2026-09-23/repetir_b5.sql`).
Espera motor=jev, modelo jev-1.13.0, latência 70–500 ms.

PASSO 3 — As 20 provas lado a lado: corre `repetir_b5.sql` com :ronda='prova-b5r2' duas vezes
(:motor='jev' e :motor='gemini'; o Gemini só se a quota da GEMINI_API_KEY tiver voltado) e lê com a
consulta de `provas_b5.md`. Escreve acerto e tempo de cada motor no relatório.

PASSO 4 — Telegram (ponte `orquestracao/ponte-telegram.sh`): resumo da missão original em voz,
duas frases — o que o decisor já decide e o que está em sombra. Copia o relatório para
C:\Users\danil\Desktop\Bora\Projetos\.

Fora do âmbito, só reportar: a GEMINI_API_KEY do Supabase está a dar 503/429 ao robot-b
(6 de 8 execuções a 23/09).

Termina com /ctx doctor e /ctx stats.
