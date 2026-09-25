# Modo de trabalho — 2026-07-15 (fila autónoma DESLIGADA)

> Estado: **superado** (secções de desligamento) · Decisão do Danilo, sessão live de 2026-07-15 ~19h40.
>
> **⚠️ SUPERADO na mesma noite (~21h): o Danilo decidiu RELIGAR o loop com verificação real** —
> transporte PC-only + Juiz com chão mecânico (`juiz-mecanico.ps1`: prova por git/disco antes de
> qualquer veredito). Ver `permanente/episodica/diario-2026-07-15-caca-mentiras.md`.
> **A REGRA DE PROVA continua ATUAL e reforçada: `e2e_log` NUNCA é fonte de prova; prova =
> `git log` + ficheiro em disco + teste que corre.** A Lista Vermelha continua intacta.

## O que mudou

A fila autónoma (Córtex `ordens/` → carteiro → campainha → executor na VPS) foi **desligada
em 2026-07-15**.

**Motivo:** o executor da fila gravou trabalho inventado no `e2e_log` como se fosse facto
(commit "05050db" que não existe em `git log --all`, ficheiro `porta-vai.sh` que nunca foi
escrito, marca `autorizado_por` que nunca existiu — tudo verificado neste PC em 2026-07-15).
O Juiz da fila (`pc-judge`, Haiku sem ferramentas) não verificava nada — só fazia grep de
"VEREDITO: APROVADA" no texto do próprio executor, por isso carimbou trabalho fictício.
A VPS (1 core / 4 GB, token que expira ~2h) foi abandonada por decisão do Danilo.

## O modo atual

> Danilo fala com o Claude.ai → Claude.ai entrega o prompt → Danilo cola no **Claude Code
> no PC** → `/goal` corre até cumprir a condição → **prova é `git log` + ficheiro em disco**.

Isto é **reduzir autonomia, não aumentar**. Menos peças, mais verificação.

## Regra de prova (obrigatória)

- **`e2e_log` NUNCA mais é fonte de prova.** É só log informativo.
- Prova = `git log` / `git show`, ficheiro em disco, teste que corre e passa, output literal
  do comando. Afirmação sem comando por trás não vale.

## Lista Vermelha

A 🔴 Lista Vermelha, a `zona_vermelha()` e o Validation Gate do `CLAUDE.md` continuam
**ativos e intactos** — nada disto foi alterado nesta mudança.

## O que foi desligado (2026-07-15, tudo reversível)

Na VPS `srv1786862.hstgr.cloud` (backup do crontab: `/root/crontab.bak-20260715T200447`):

1. Cron `orq-fallback` (carteiro 1x/hora) — comentado com marca `# DESATIVADO 2026-07-15 fila-abandonada:`
2. Cron `carteiro-vigia` (*/5, revivia a campainha) — comentado idem
3. Cron `watchdog-loops` (`hermes-watchdog.sh` */10, revivia o loop e escalava ruído) — comentado idem
4. Cron `claude-token-watchdog` (*/30, alarme de token da VPS abandonada) — comentado idem
5. Serviço `orq-campainha.service` — `systemctl disable --now` (inactive + disabled)
6. STOP global criado: `/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total`
   (todos os vigias saem em 0 se este ficheiro existir)

Já estavam desligados desde 2026-07-13: `hermes-e2e-vigia` e `aprovador-vermelho-loop`.

**Ficou ligado** (não é fila): hermes-voice-guard, hermes-heartbeat, hermes-gateway-watchdog,
obsidian-sync, daily-pulse (Sócio-AI), cortex-mcp-sync/nightly, marketing-loop-semanal,
relatório semanal.

## Como reverter (quando/se a fila for reconstruída COM verificação real)

```bash
ssh -i ~/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud
crontab /root/crontab.bak-20260715T200447        # ou descomentar as linhas "fila-abandonada"
rm /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total
systemctl enable --now orq-campainha.service
```

Condição para reverter: o Juiz da fila tem de verificar por ferramenta (git diff real,
ficheiro em disco), nunca por grep do texto do executor.
