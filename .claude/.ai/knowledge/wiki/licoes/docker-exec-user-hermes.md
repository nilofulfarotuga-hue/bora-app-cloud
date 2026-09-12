---
id: licao-docker-exec-user-hermes
tipo: licao
origem: [sessão 2026-07-08: erro "Permission denied" ao arquivar sessoes no VPS]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Lição — `docker exec`: escolher o **user** certo

**Problema.** Comandos no container `hermes-agent-fvnc-hermes-agent-1` falhavam de formas opostas
conforme o user.

**Tentativas que falharam.**
1. `docker exec -u hermes ...` para `mkdir` em `/opt/data/_vault_velho_arquivo/` → **`Permission denied`**
   (a pasta é **root-owned**, criada por scripts do host).
2. (Inverso conhecido) correr como root um comando do agente → perde `HOME=/opt/data`, `.env`,
   caches e credenciais do `hermes`.

**Porquê falharam.** O `hermes` não escreve em dirs de `root`; o `root` não tem o ambiente do `hermes`.

**Solução (regra generalizável).**
- Trabalho do **agente** (ler `.env`, correr `daily_pulse.py`, escrever em `daily-pulse/`): `docker exec -u hermes -e HOME=/opt/data`.
- Operações em **caminhos root-owned** (arquivar em `_vault_velho_arquivo/`): `docker exec -u root`.
- Na dúvida, `ls -la` o alvo primeiro e escolher o user pelo **dono** do caminho.
