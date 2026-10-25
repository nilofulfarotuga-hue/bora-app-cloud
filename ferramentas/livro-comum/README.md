# Livro comum — cópia versionada dos scripts (missão livro-comum-2026-10-23)

Os ficheiros vivos estão na VPS (`/opt/data/bin`, `/opt/data/rotinas`, `/usr/local/bin`) e no PC (`~/.claude/livro`).
Isto é a cópia para não se perderem. Nenhum tem chaves: todos as leem do `.env` de cada máquina.

## VPS (`vps/`)
| Ficheiro | Onde vive | Quando corre |
|---|---|---|
| `livro_gravar.py` | `/opt/data/bin` | à mão / por outros scripts — grava uma página do livro (recusa `[PESSOAL]` e segredos) |
| `livro_ao_acordar.py` | `/opt/data/bin` | cron `8,38 * * * *` — SOUL do Hermes = `SOUL-base.md` + erros-aprendidos + regras-do-danilo + digest |
| `SOUL-base.md` | `/opt/data` | a alma curta do Hermes (editar esta, nunca o `SOUL.md`) |
| `livro_noite.py` | `/opt/data/bin` | 23:40 Lisboa — livro-hermes-aprendeu, livro-hermes-skills, livro-indice, livro-resumo |
| `livro_faxina.py` | `/opt/data/bin` | domingo 22:30 Lisboa — escriba propõe, critico revê; nada se apaga |
| `livro_fila.py` + `aprender` | `/usr/local/bin` + contentor | unidade `livro-fila.path` — o comando `aprender` do Hermes grava em erros-aprendidos |
| `cacador_loop.py` | `/opt/data/rotinas` | dias úteis 07:30 Lisboa — 10-20 negócios novos com email verificado + maquete |
| `caca_respostas.py` | `/opt/data/rotinas` | dentro do leitor do carteiro (hora a hora) — classifica e responde |
| `caca_fila.py` + `caca` | `/usr/local/bin` + contentor | unidade `caca-fila.path` — o "manda" do Danilo envia o rascunho |
| `radar_freelas.py` | `/opt/data/rotinas` | 08:30 Lisboa — lista de freelas + propostas no Telegram |
| `whatsapp_modo_rascunho.py` | `/opt/data/rotinas` | nunca (encaixe DESLIGADO; ver página whatsapp-a-discutir) |
| `critico_skills.py` | — | revisão única das skills do Hermes (25/10) |

Também na VPS: `sincroniza-memoria-claude.sh` passou a `7,37 * * * *` e o `_sincroniza_memoria_claude.py` salta páginas
`[PESSOAL]` (o repo é público); o Motor Bora manda pedidos com `[PESSOAL]`/`[PRIVADO]` só para Cloudflare/Groq/local;
o espelho das skills (`sync-brain.sh fast`) corre a `15,45`; o Hermes lê-o por `skills.external_dirs`.

## PC (`pc/`)
`livro-ao-acordar.mjs` (cópia local do livro importada pelo `~/.claude/CLAUDE.md`), `livro-claude-code-aprendeu.mjs`
(memória automática do Claude Code → livro), `espelhar-skills.mjs` (pasta comum ↔ `~/.claude/skills`, sem apagar),
`renovar-livro.cmd` (corre os três). O gancho de arranque e a tarefa agendada ficaram por aprovar: ver `docs/TRANCAS.md`.
