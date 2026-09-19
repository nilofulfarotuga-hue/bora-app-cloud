# Relatório — Fix da TRAVA (`protege-banco.sh` "No such file or directory")
> Sessão · 2026-07-08 · MODO PROTECÇÃO TOTAL (infra) · sem CEO-AI (exceção infra Hermes)
> Resultado: **causa-raiz encontrada e validada**. Fix é **PROPOSE-ONLY** (a própria Trava
> impede o agente de editar o `settings.json` — falta 1 ato manual teu + restart).

## 1. Diagnóstico — o ficheiro NUNCA esteve em falta
- `.claude/hooks/protege-banco.sh` **existe** (5013 bytes, executável, commit `d0e89cd`, git-clean).
- Prova viva: **nesta mesma sessão** ele **bloqueou** a minha migration (falso positivo "DROP" num
  comentário). Ou seja, o script corre e funciona — via o matcher Supabase, que disparou enquanto
  o cwd ainda era a raiz do repo.
- Registo do hook (em `.claude/settings.json`), matcher `Bash|mcp__*Supabase*|...`:
  `"command": "bash .claude/hooks/protege-banco.sh"` — **path RELATIVO**.

## 2. Causa-raiz (confirmada, não é teoria)
O comando do hook usa **path relativo**. O Claude Code corre o hook a partir do **cwd atual** da
sessão Bash. No trabalho anterior corri:
```
cd .../hermes/socio-ai && python -m py_compile ...
```
O `cd` **persistiu** como cwd da ferramenta Bash. A partir daí, **todas** as chamadas Bash do deploy
(scp → docker cp → git) correram o hook a partir de `hermes/socio-ai/`, onde
`.claude/hooks/protege-banco.sh` **não existe** → `No such file or directory` → hook non-blocking →
**a guarda de DB foi saltada** nessas chamadas.

Prova reproduzida:
- Da raiz: `ls .claude/hooks/protege-banco.sh` → existe.
- De `hermes/socio-ai/`: `ls .claude/hooks/protege-banco.sh` → **No such file or directory** (o erro exato).

## 3. Impacto real (honesto)
- A janela de bypass foi entre o `cd` e agora. Nessa janela as minhas chamadas Bash foram
  **scp/ssh/docker/git de ficheiros não-financeiros** — **nenhuma** tocou zona protegida de DB.
- As operações Supabase de risco (migration) aconteceram **antes** do `cd` e **estavam guardadas**
  (uma foi mesmo bloqueada). **Conclusão: nada protegido passou indevidamente.** Mas a fragilidade
  é real e tinha de ser corrigida antes de ligar qualquer gate.

## 4. Validação (o script está 100%)
Testei `protege-banco.sh` **via path absoluto** com 7 payloads simulados (harness em scratchpad):
- BLOQUEIA (exit 2): `git reset --hard` · DROP de tabela financeira (`ledger_entries`) ·
  deploy de edge protegida (`dispatch-engine`) · DDL sobre `pricing_calculate`.
- DEIXA PASSAR (exit 0): `echo` · `SELECT` em orders · `create view` read-only.
- **7/7 OK, 0 falhas.** O invocar por path absoluto encontrou e correu o hook de qualquer cwd —
  ou seja, **a correção (path absoluto) está provada a funcionar**.
- `engine --selftest` no container: limpo, gates OFF (enabled=False, dry_run=True).

## 5. Correção — PROPOSE-ONLY (a Trava protege-se a si mesma)
`.claude/settings.json` e `.claude/hooks/**` estão na **deny list** — o agente **não pode** editá-los
(desenho "auto-protege a trava"). Por isso deixei a correção pronta no **vehicle de proposta**:
- **`.claude/settings.proposto.json`** — igual ao `settings.json` **exceto** os 2 comandos de hook,
  agora com **path absoluto**:
  - `bash /c/Users/danil/Desktop/projetosflutter/bora_app/.claude/hooks/protege-dinheiro.sh`
  - `bash /c/Users/danil/Desktop/projetosflutter/bora_app/.claude/hooks/protege-banco.sh`
- Diff = exatamente 2 linhas (110 e 119). JSON validado.
- Usei path POSIX absoluto fixo (robusto no Git Bash, e consistente com o estilo do `settings.local.json`).
  Alternativa portável `"$CLAUDE_PROJECT_DIR/.claude/hooks/..."` — NÃO usada por risco de barra
  invertida do Windows dentro do bash; fica documentada como opção.

### 🖐️ O que falta de ti (2 minutos)
1. Aplicar a proposta ao ficheiro vivo (a Trava bloqueia-me a mim, não a ti):
   ```
   cp .claude/settings.proposto.json .claude/settings.json
   ```
   (ou muda só as linhas 110 e 119 à mão).
2. **Reiniciar o Claude Code** para recarregar os hooks.
3. Só **depois** disto validado é que decides sobre ligar os safety gates (email/WhatsApp).
   **Não liguei nenhum gate** nesta sessão, como pediste.

## 6. Lição (para não repetir)
- **Hooks nunca com path relativo** — sempre absoluto (ou `$CLAUDE_PROJECT_DIR`), senão um `cd`
  numa sessão Bash desliga a guarda silenciosamente.
- **No agente: evitar `cd` para subpastas** em comandos Bash — usar paths absolutos / `git -C`.
  Foi o `cd` para `hermes/socio-ai` que abriu a janela.
