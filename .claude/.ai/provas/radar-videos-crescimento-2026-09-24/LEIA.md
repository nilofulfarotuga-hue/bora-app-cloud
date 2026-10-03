# Provas — radar de vídeos de crescimento (24/09/2026)

O robô vive **fora do repositório**, no PC do Danilo
(`C:\Users\danil\Desktop\QG\radar-crescimento\`), porque só de casa é que o YouTube deixa
descarregar as legendas. Aqui ficam cópias fiéis do que corre, para ninguém ter de ir lá ver.

## `pc/` — o que corre no computador

| Ficheiro | O que é |
|---|---|
| `radar_crescimento.py` | o robô: `recolher`, `playbook`, `telegram` |
| `run_diario.ps1` | tarefa das 19:00 (recolhe; ao domingo destila o playbook) |
| `run_telegram.ps1` | tarefa das 20:00 (cinco linhas ao Danilo) |
| `radar.log.parcial` | o log a meio da primeira recolha real, tal como estava |

O `.env` com a chave do robô, a chave do Supabase e a do Gemini **não** está aqui nem no
repositório: vive só no PC, ao lado do script.

## `vps/` — o que corre no servidor

| Ficheiro | O que é |
|---|---|
| `playbook_regras.py` | leitor partilhado do playbook, instalado em `/opt/data/social/` |
| `aplicar_hooks.py` | o remendo que ligou o `fiscal_video.py`, o `social-reel.sh` e o `emdia_redes.py` ao playbook (com cópia de segurança de cada um) |

O `aplicar_hooks.py` só mexe quando o texto-âncora aparece **uma única vez** no ficheiro, e
não repete se a marca já lá estiver — dá para voltar a correr sem medo.
