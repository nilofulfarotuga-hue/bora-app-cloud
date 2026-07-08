# 🔄 Religar o sync Obsidian (D6) — script criado + testado · hook PROPOSTO
> Data: 2026-05-31 · O **export código→vault** estava em falta; foi **criado e testado** com sucesso.

## ✅ Feito e testado
- **Script novo:** `.claude/scripts/export-to-obsidian.ps1` (direção **código → vault**, inverso do `sync-obsidian-knowledge.ps1`). Idempotente (SHA256, state em `.claude/.ai/.export-state.json`).
- **Exporta:** `bora_app/relatorios/*.md` → `<vault>\Bora App\relatorios\` · `bora-knowledge/knowledge/*.md` → `<vault>\Bora App\knowledge\`.
- **Teste (D6.4):** criado ficheiro-teste → corrido o script → **apareceu no vault** ✅ → ficheiro-teste removido. 20 .md exportados na 1ª corrida.

### Correr manualmente (imediatamente fiável)
```powershell
.\.claude\scripts\export-to-obsidian.ps1 -VaultPath "C:\Users\danil\Desktop\Bora"
# dry-run: acrescentar -DryRun
```

## ⚠️ Hook automático — PROPOSTO (não aplicado)
**Porque não apliquei:** `settings.json` é zona "pergunta antes" (AUTONOMY PRINCIPLE), e um hook `Stop` corre em **cada fim de turno** (pesado). Decisão tua.

**Config recomendada** (via skill `update-config`, em `.claude/settings.json`):
```jsonc
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\danil\\Desktop\\projetosflutter\\.claude\\scripts\\export-to-obsidian.ps1\" -VaultPath \"C:\\Users\\danil\\Desktop\\Bora\""
          }
        ]
      }
    ]
  }
}
```
- **Garantia anti-congelamento:** corre sempre que o Claude termina → o vault nunca mais atrasa.
- **Cautela:** se `Stop` correr demasiadas vezes, preferir o evento `SessionEnd` (1×/sessão) — confirmar qual o teu harness suporta.

## Fallback fiável (se o hook não convier)
- Skill/atalho manual `/sync-obsidian` (correr o script) + lembrete no fim de cada sessão de trabalho.
- OU Windows Task Scheduler diário (corre o export 1×/dia).

## Notas
- O `export-to-obsidian.ps1` vive em `projetosflutter/.claude/scripts/` (fora do repo bora_app, como o sync existente) → **não versionado**. Recomendação: mover ambos os scripts para um local tracked se quiseres histórico.
- Bidirecional completo = `export-to-obsidian` (saída) + `sync-obsidian-knowledge` (entrada), ambos idempotentes por SHA256.
