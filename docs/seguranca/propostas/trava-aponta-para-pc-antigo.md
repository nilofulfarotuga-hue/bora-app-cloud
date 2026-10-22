# PROPOSTA (não aplicada) — a Trava do banco corre, mas pelos scripts do PC antigo

> Auditoria de segurança 21/10/2026 (missão geral-noite-21-10, agente N4). **Não mexo no
> `.claude/settings.json`** (zona protegida). Só reporto, com a proposta pronta.

## O que se achou (e o que NÃO é verdade)

O achado conhecido dizia "a Trava e a bora-tranca não guardam o banco nesta pasta". **Medido, a
Trava GUARDA:** os hooks em `.claude/settings.json` apontam para
`C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\hooks\...`, e esse caminho é uma **junção**
para `C:\BoraLocal\projetosflutter\bora_app` (confirmado: `Desktop\projetosflutter` → `Junction →
C:\BoraLocal\projetosflutter`). Os três scripts (`protege-dinheiro.sh`, `protege-banco.sh`,
`git-guardrails.sh`) existem nos dois caminhos e são **byte a byte iguais**.

Prova de que a Trava do banco morde: enviei ao `protege-banco.sh` o payload de um
`execute_sql` com `truncate ledger_entries` (dentro de um comentário, sem executar nada) e o hook
respondeu `exit=2` — "TRAVA BORA — operação BLOQUEADA: DROP/TRUNCATE de tabela financeira".

## O que continua frágil (a proposta)

1. **Depende da junção do Desktop.** Se a junção `Desktop\projetosflutter` desaparecer (PC novo,
   limpeza, perfil novo), os hooks apontam para um caminho que deixa de existir e a Trava deixa de
   correr **em silêncio** (o Claude Code não falha quando o comando do hook não existe). Proposta:
   mudar os `command` do `.claude/settings.json` para `$CLAUDE_PROJECT_DIR/.claude/hooks/...`, que
   resolve sempre para a pasta real do projeto (`C:\BoraLocal\...`), sem depender da junção.

2. **Só vale nas sessões interativas.** No loop autónomo (`claude -p`) os hooks `PreToolUse` não
   correm — já documentado. Nada a fazer aqui, mas fica dito.

3. A `bora-tranca` do plugin `bora-mods` **não está ligada nesta máquina**: o
   `~/.claude/settings.json` só tem `context-mode` em `enabledPlugins` (não há `bora-mods@...`), e o
   projeto não liga plugins. Quem protege o banco hoje é o hook `protege-banco.sh` (a Trava "antiga"),
   que está ligado e morde. Se o Danilo quiser a `bora-tranca` do plugin a correr também, tem de a
   ligar em `enabledPlugins` — decisão dele.

## Porque fica como proposta

Mexer no `.claude/settings.json` é zona protegida por ordem da missão. A mudança proposta (1) é de
uma linha por hook e só torna o caminho robusto; não altera o que a Trava bloqueia.
