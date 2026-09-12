# 08 — LIÇÕES APRENDIDAS (não repetir erro pago)

## Git / CI / publicação

- SSH do PC do Danilo falha sempre (`Permission denied publickey`) → HTTPS + `credential.helper=manager` + `pull --rebase --autostash`. SEMPRE confirmar que o commit chegou no GitHub (senão o CI não builda e todo mundo acha que buildou).
- `paths-ignore` avalia TODOS os commits do push: commit `.md`/`.claude/` sozinho não dispara build, mas "dá boleia" a código pendente → build+publicação acidental. Antes de qualquer push, listar o que viaja junto.
- Trabalho de infra sensível vai pra branch isolada + worktree (padrão P1/P2/P3 do motor de conhecimento) — nunca direto na branch auto-publicada.
- Antes de culpar automação por um push misterioso: verificar reflog/GitHub. Já aconteceu duas vezes de acusarem a BoraGitPushBridge e o publicador era o próprio Danilo noutra janela. A bridge falha sempre (SSH) e é inofensiva — decisão: não mexer nela.

## Execução / loop

- Uma ordem de cada vez — 4 simultâneas derrubaram o terminal do PC 4GB.
- Nada pesado no PC local (compile web = OOM). Pesado vai pra VPS; compile grande na VPS precisa de swap 6G.
- Flutter web headless sem GPU não renderiza (CanvasKit `ReadPixels`) — SwiftShader/xvfb/GitHub Actions não resolvem. Teste web de verdade = `flutter drive` + `integration_test`.
- `is_rate_limit()` só em outputs <600 bytes; parser de horário de resume precisa entender HH:MMam/pm com timezone.
- Saída de subprocesso suja: rejeitar o blob inteiro (limpo ou nada) — filtrar linha-a-linha já plantou mensagem de erro disfarçada de regra no Cérebro.
- Ordem de teste destinada a TRAVAR: criar o ficheiro já com `tentativa:5` via `mv` atômico — senão o inotify acorda o executor no intervalo.

## Conhecimento / honestidade

- Digest injetado em toda sessão tem TETO (12KB) — cada KB custa contexto. Cortar por PESO (dinheiro/segurança primeiro), nunca por ordem de ficheiro. Fragmentos de secção sem contexto não ensinam nada — fora.
- Nunca plantar alegação de proveniência falsa ("veredito determinístico" quando veio de um LLM). O anti_trapaca existe pra isso; o selftest do C4 falha de propósito se a alegação voltar.
- Prova > palavra: execução se prova por SELECT em `e2e_log`/`orders`, hash de ficheiro, log com timestamp. Imagem não é prova de fluxo backend.
- Pré-preenchido no terminal ≠ enviado. Já registramos como feito algo que o Danilo nunca apertou Enter. Confirmar estado real antes de anotar.
- Se um julgamento automático falha, degradar pra "PENDENTE" — nunca inventar veredito.

## App / produto

- Interruptor de feature: achar o mecanismo REAL no código/DB antes de criar setting nova (a `tvde_enabled` criada em `platform_settings` era inerte — ninguém lia; o gate real era `users.tvde_access`).
- Overloads de RPC com PostgREST dão 404 — fundir numa função só com defaults (caso `tvde_request_ride`, e `tvde_add_stop` que dropou a overload velha ANTES de dar 404).
- Colunas novas: confirmar a TABELA certa (`service_providers` vs `restaurants` — já criamos em `restaurants` por engano e tivemos que remover).
- Testes com Stripe live cobram DE VERDADE — pagamento em teste é sempre cash.
- `assert()` é STRIP em release mode — nunca usar pra validação de produção.
- CallKit/ConnectyCube e `flutter_overlay_window`: caminhos mortos no TVDE, não revisitar.

## Sites / assets

- Artifact no celular do Danilo: imagem externa não renderiza — embutir base64/SVG. Container do Claude.ai só alcança domínios da allowlist (raw.githubusercontent.com sim; supabase.co não).
- Sem imagens de stock da internet nos mini-sites (direito autoral) — só material do Danilo/parceiro ou SVG próprio.
