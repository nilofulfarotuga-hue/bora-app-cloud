# Pré-5A — Migração Obsidian vault

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Tipo:** filesystem only (zero DB / Edge Fns / Flutter)

## Motivo

Tudo num sítio + git como backup natural + portabilidade entre máquinas.
Decisão Danilo (Opção 2, 2026-05-04).

## Antes → Depois

| | Antes | Depois |
|---|---|---|
| Localização | `C:\Users\danil\Desktop\Bora` | `bora_app/.obsidian-vault/` |
| Backup | manual (sync scripts existiam mas estavam desactualizados) | git |
| Sync scripts | inexistentes apesar de mencionados em INDEX.md | desnecessários (vault dentro do repo) |

## Execução

- 51 .md + 97 ficheiros config copiados (148 totais, 142.95 MB)
- Método: `Copy-Item -Recurse -Force` (binary preserve, sem encoding normalisation)
- SHA256 100% match source vs destino (mismatches=0, only_source=0, only_dest=0)
- Source `C:\Users\danil\Desktop\Bora` intactus (drift=0 pós-copy)

## Decisões aplicadas (Danilo, 2026-05-04)

- **Sync scripts:** Opção α — não criados (vault vive no repo, git é o sync)
- **`.smart-env/`:** 4.9 MB → ignorado em `.gitignore` (re-gerado pelo plugin Smart Connections)
- **`.obsidian/` granular:** workspace*, cache, app.json, plugins/, themes/ → ignorado; `community-plugins.json` + `core-plugins.json` → commitados (lista plugins partilhável)
- **`.trash/`:** ignorado preventivamente (não existe actualmente)
- **`.obsidian/2026-04-24.md` (stub 0 bytes):** migrado tal qual
- **`.obsidian/.obsidian/` recursivo:** migrado tal qual (artefacto plugin)

## Como abrir

1. Abrir Obsidian
2. "Open folder as vault" → `bora_app/.obsidian-vault/`
3. Plugins re-instalam-se a partir de `community-plugins.json` se necessário

## Critério apagar source

- 7 dias de utilização OK em destino
- SHA256 weekly match check (manual ou cron pessoal)
- Após validação: apagar `C:\Users\danil\Desktop\Bora` (sessão futura)

## Skills identificadas
Nenhuma (sessão filesystem trivial).
