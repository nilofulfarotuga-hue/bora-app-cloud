---
id: licao-verificar-fonte-de-sync
tipo: licao
origem: [Fase 0/1A: obsidian-sync.sh puxava Desktop\Bora (velho) em vez do vault canónico]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Lição — num sync, auditar a **FONTE**, não só o destino

**Problema.** O Hermes lia notas **desatualizadas**. O destino (`/opt/data/obsidian-bora`) enchia-se
e "parecia" a funcionar, mas com o vault **errado**.

**Tentativas que falharam.** Confiar que "a sync corre" (o cron 04:30 disparava e o destino tinha 88 .md).
O sintoma (destino cheio) escondia a causa (fonte errada).

**Porquê falhou.** `obsidian-sync.sh` fazia `tar -C C:/Users/danil/Desktop Bora` — a fonte era o vault
**velho** (`Desktop\Bora`, 88 .md), não o canónico (`bora_app/.obsidian-vault`, 150 .md).

**Solução (regra generalizável).** Ao diagnosticar um sync, **abrir o script e ler a FONTE do `tar`/`rsync`**.
Um destino com dados não prova que a fonte é a certa. Corrigida a fonte para `.obsidian-vault` →
150 .md canónicas. (Bónus: o alias `bora-pc` não resolvia em `docker exec` → transporte explícito
`ProxyCommand=tailscale nc`.)
