# MOTOR DE CONHECIMENTO SEMI-AUTOMÁTICO — Auditoria (Fase 0) + Plano (Fase 1)

> 2026-07-20 · CEO-AI · MODO PROTECÇÃO TOTAL · **NADA IMPLEMENTADO — aguarda "vai"**

---

## FASE 0 — AUDITORIA (com prova)

### 1. Onde vive o conhecimento hoje

| Fonte | Caminho | Estado real (medido) |
|---|---|---|
| Índice | `.claude/.ai/knowledge/INDEX.md` | 7.471 B (dentro do teto de 24 KB) |
| Lições procedurais | `permanente/procedural/licoes/` | **7 lições** + README (mais recentes 14/07) |
| Lições wiki | `wiki/licoes/` | **21 lições** (mais recentes 17–18/07) |
| Bugs resolvidos | `permanente/episodica/bugs-resolvidos.md` | 16.562 B |
| Decisões | `permanente/episodica/decisoes.md` | 15.671 B |
| Inbox | `inbox/` | **164 ficheiros .md · 1,4 MB** ← maior fonte, não curada |
| Regras de negócio | `.claude/.ai/business_rules.md` | **194.567 B (190 KB)** ← nunca cabe no contexto |
| Métricas skills | `wiki/skills-metrics.md` | 9.807 B |

Nota: `permanente/episodios/` **não existe** — a pasta real é `permanente/episodica/`.

### 2. Já existe consolidação/digest?

**NÃO existe digest.** Existe **higiene**, que é coisa diferente:
- `_tools/cortex_nightly.py` — cron VPS `5 7 * * *` (Lisboa). Produz `_debt.md` +
  `inbox/_reports/nightly-<data>.md`. É *manutenção* (confiança/decaimento/aging do inbox),
  **não** um resumo para o executor ler. Dry-run por defeito, stdlib-only, nunca toca zona vermelha.
- ⚠️ A schtask chamada `Consolidator` que aparece no Windows é **nativa da Microsoft**
  (`%SystemRoot%\System32\wsqmcons.exe`, pasta `\Microsoft\Windows\Customer Experience
  Improvement Program\`) — **não é nossa**. Por isso o nome novo não pode ser esse.

**Conclusão:** C1 é aditivo, não duplica o `cortex_nightly.py`. Copia-lhe o padrão (stdlib, repo-side, reversível).

### 3. O executor carrega lições antes de correr uma ordem? — **NÃO**

Prova, cadeia completa `carteiro.sh` → `pc-loop` → `run-claude-loop.cmd`:

`carteiro.sh:444` lê a ordem e `carteiro.sh:502` executa-a **crua**:
```sh
id=$(get id "$f"); tarefa=$(get tarefa "$f"); tent=$(get tentativa "$f"); tent=${tent:-0}
...
saida=$(exec_ordem "$tarefa"); printf '%s\n' "$saida" > "$FILA/$id.saida.txt"
```
Único enriquecimento é o prefixo de modelo (`carteiro.sh:255`): `prefixo="[MODELO: ${modelo:-SONNET}]"`.

`run-claude-loop.cmd:120` — a chamada real ao executor:
```bat
"%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format stream-json --verbose %MODEL% %PERM% %TURNS% %BUDGET% < "%TASKFILE%"
```
O `%GUARD%` (linha 59) é só disciplina de loop (não commitar, PROPOSE-ONLY, Lista Vermelha).
**Zero lições, zero digest, zero Córtex.** O executor só apanha o `CLAUDE.md` (porque corre
com `cd /d "%PROJ%"`). Ou seja: hoje ele começa cego a tudo o que foi aprendido desde 08/07.

### 4. Agendamentos atuais (para não colidir)

**PC (schtasks):** `BoraAutoLimpezaRAM` (rep. 15 min) · `BoraGitPushBridge` (rep. 15 min) ·
`BoraTesteFechadoMonitor` (diária 09:03) · `Bora-heartbeat-desktop` · `BoraE2E_MonitorProva` (parada).

**VPS (crontab, `CRON_TZ=Europe/Lisbon`):** `17 * * * *` carteiro fallback · `*/5` carteiro-vigia ·
`*/10` aprovador-vermelho · `*/10` cortex-proposals-sync · `*/2` espelho-supabase ·
`30 4` obsidian-sync · `30 6` cortex-mcp-sync · `5 7` cortex-nightly · `25 7` evolution-ordens ·
`0 7` daily-pulse · domingos: marketing-loop 20:30 / relatório 21:00.

→ **04:00 e 16:00 estão ambos livres.** 04:00 fica 30 min antes do obsidian-sync; 16:00 fica
17 min antes do carteiro fallback. Sem sobreposição com nada pesado.

### 5. O loop "falha → lição" está firme? — **NÃO. Está partido.**

- `.claude/juiz/reflexao.py` **existe mas é código morto**: nenhum `.sh`/`.cmd`/`.ps1` o invoca.
  O único script do Juiz ligado ao loop é o `anti_trapaca.py` (`juiz-mecanico.ps1:66-74`).
- O que o loop faz numa rejeição (`carteiro.sh:600-610`): grava `nota:` no ficheiro da ordem e
  reabre (`CORRIGIR`) ou tranca (`TRAVADA`). **Nunca escreve uma lição.**
- As 28 lições existentes vieram de **commits manuais em lote** (ex.: `bbbdd28` "religar motor
  de aprendizagem + 7 licoes", `0aa56b1` "2 licoes novas"), não do ciclo automático.

**Consequência:** sem C4, o C1 consolida um corpo de lições que deixou de crescer sozinho.

---

## FASE 1 — PLANO (aguarda aprovação)

### C1 — Consolidador agendado
- **Script:** `.claude/.ai/knowledge/_tools/consolidador.py` — stdlib-only, **read-only** sobre as
  fontes, escreve **1 ficheiro**. Zero build, zero teste, zero rede. Padrão copiado do `cortex_nightly.py`.
- **Saída:** `permanente/procedural/estado-atual-consolidado.md` (zona 🟢 verde, pasta já
  existente e gravável — 6 ficheiros lá dentro hoje). Versionado com data + hash das fontes.
- **Conteúdo (4 blocos):** lições vigentes resumidas por categoria · bugs conhecidos abertos ·
  regras de negócio críticas em vigor · armadilhas recorrentes ("não faças X").
- **Teto duro: 12 KB (~3.000 tokens).** Truncagem determinística por prioridade — o digest
  **nunca** pode sufocar o contexto do executor. Só aplica factos `estado: atual`.
- **Agendamento:** schtask nova **`BoraMotorConhecimento`** (nome livre de colisão com a
  `Consolidator` da Microsoft) — **04:00 e 16:00**, `-StartWhenAvailable`, PC.
- **Custo RAM:** processo Python a ler ~200 ficheiros de texto — dezenas de MB, ordens de
  grandeza abaixo do executor. Não compete com o 4GB.

### C2 — Injeção automática por tarefa ← **o coração**
- **Mecanismo:** hook nativo **`SessionStart`** em `.claude/settings.json`, com
  `hookSpecificOutput.additionalContext` a carregar o digest.
- **Confirmado (agente claude-code-guide):** o `SessionStart` **dispara em `claude -p` headless**;
  e `.claude/settings.json` do projeto **tem precedência** sobre o `CLAUDE_CONFIG_DIR`.
- **Ganho decisivo:** **zero alterações ao `carteiro.sh` e ao `run-claude-loop.cmd`.** O loop que
  funciona não é tocado — o risco de partir a esteira cai para ~zero. E cobre de borla as
  sessões interativas do Danilo, não só o executor.
- **Script:** `.claude/hooks/injeta-digest.sh` — **fail-open** (digest ausente/corrompido →
  não emite nada, `exit 0`, a sessão arranca à mesma), teto de tamanho, e aviso embutido se
  o digest tiver >24h ("possivelmente desatualizado").
- **Matchers:** `startup` + `resume` + `compact` (sobrevive à compactação).
- Cada injeção incrementa um contador → alimenta o C3.

### C3 — Painel admin (Central de Autonomia) — obrigatório
- **Onde:** cartão novo "Motor de Conhecimento" no `AdminRobotSuggestionsScreen` (a superfície única).
- **Mostra:** hora da última consolidação · tamanho + preview do digest · toggle liga/desliga ·
  cadência 2×/dia ↔ 1×/dia · contador "lições aplicadas por ordem".
- **Dados:** tabela nova `knowledge_digest_status` (1 linha: `ultima_consolidacao`, `tamanho_bytes`,
  `preview` ~2 KB, `licoes_contadas`, `injecoes_total`) + 2 chaves **não-financeiras** em
  `platform_settings`: `knowledge_consolidator_enabled`, `knowledge_consolidator_cadence`.
  Nenhuma chave `stripe_*`/`pricing_*`/`fee_*`/`token_*` é tocada.
- O `consolidador.py` **lê o toggle antes de correr** → o botão do admin é um kill switch a sério.

### C4 — Fechar o loop (ligar, não recriar)
- **Ligar** o `reflexao.py` que já existe ao `carteiro.sh`, **só no ramo `TRAVADA`**
  (`carteiro.sh:606-607`) — não no `CORRIGIR`. Motivo: gerar lição a cada re-tentativa
  reproduz a `licao-spam-ordens-autoreferencial` já registada.
- A lição sai como **rascunho para `inbox/`**; quem promove a permanente continua a ser o
  `bibliotecario-cerebro` (a regra de escritor único mantém-se intacta).
- **Passo 0 da implementação:** ler a interface real do `reflexao.py` antes de ligar — pode
  precisar de adaptador. Diff mínimo, aditivo.

### Ordem de execução proposta
C1 (digest existe) → C2 (passa a ser lido) → C4 (volta a crescer) → C3 (Danilo vê e controla).
C2 sozinho já entrega o pedido central; C3 é o gatilho de paridade admin obrigatório.

### Riscos e travões
| Risco | Travão |
|---|---|
| Digest engorda e sufoca o executor | Teto duro 12 KB + truncagem determinística |
| Hook rebenta e trava toda e qualquer sessão | Fail-open: erro → `exit 0` sem contexto |
| Digest velho ensina coisa errada | Carimbo de data + aviso automático >24h; só `estado: atual` |
| Colisão de horário/RAM | 04:00 e 16:00 provadamente livres; job só-leitura |
| Auto-commit a furar a regra do Danilo | Consolidador **não** faz commit. Escreve e pára. |

### Fora de escopo (não mexer)
Análise profunda do `evolution-engine` (pattern-mining pesado) — continua ocasional, como está.

### Zona vermelha
Nenhum componente toca Stripe/pricing/tokens/dispatch. **Não há travagem financeira neste plano.**
