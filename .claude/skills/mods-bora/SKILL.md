---
name: mods-bora
description: Os mods do Claude Code do Bora (plugin bora-mods, 02/10/2026) — tranca que proíbe zonas vermelhas por código, vigia de missão parada, contador de gasto, painel do CI e contexto de missão. Ler antes de mexer em .claude/plugins/bora-mods, quando a tranca negar um comando, ou quando alguém quiser instalar um mod.
---

# mods-bora

Plugin `bora-mods` em `.claude/plugins/bora-mods/` (README completo lá dentro). Carrega em
todas as sessões do PC pela variável de ambiente do utilizador `CLAUDE_CODE_PLUGIN_DIRS`.

## Os cinco mods (por esta ordem)

1. **tranca** — PROÍBE (zonas vermelhas de `zonas-vermelhas.json`, push forçado, `git add -A`,
   `reset --hard`, `rm -rf` fora de build, SQL destrutivo/DML direto em tabelas de dinheiro,
   deploy protegido, workflows, versão do pubspec, segredos); PERGUNTA (push normal, migration,
   DDL, deploy de outras Edge Functions; Recusar por defeito e em `claude -p`); APROVA sem caixa
   só leitura e edições em `lib/`, `test/`, `docs/`, `*.md` fora das zonas. Fail-closed.
2. **vigia** — 15 min parado → aviso + `e2e_log` + Telegram (se houver credencial); 5 chamadas
   iguais → aviso de círculos.
3. **contador** — contexto %, chamadas, limite do plano; avisos a 70/90% e plano a 80%.
4. **ci** — painel dos builds Android/web/iPhone com versionCode; abre 30 s após um push.
5. **contexto** — junta ramo/commit/WIP ao prompt `⚠️ MODO PROTECÇÃO TOTAL`.

## Comandos

`/tranca` · `/tranca-off N` (só as aprovações; as proibições nunca) · `/vigia` · `/custo` ·
`/ci` · `/bora`. Logs em `.claude/.ai/mods/`.

## Se a tranca negar

Não contornes (nem PowerShell, nem outro ficheiro, nem outra ferramenta). Escreve no
`e2e_log` o que foi negado e porquê, e diz ao Danilo numa frase. Se for falso positivo,
propõe a correção da regra em `hooks/regras.ts` com um teste novo — quem aplica é o Danilo
ou uma sessão com `--safe-mode` por ordem dele (o plugin protege-se a si próprio).

## Como desligar

Uma sessão: `claude --safe-mode`. Tudo: `disableAllHooks: true` ou apagar a variável
`CLAUDE_CODE_PLUGIN_DIRS`.

## Acrescentar uma zona vermelha

Linha nova em `zonas-vermelhas.json` (regex sobre o caminho com `/` + motivo PT), depois:
`claude plugin validate .claude/plugins/bora-mods --strict`, `claude plugin test
.claude/plugins/bora-mods`, `bun .claude/plugins/bora-mods/verificar/regras.verificar.ts`.

## Armadilhas aprendidas (02/10)

- O motor só aceita **um** gancho sem filtro por evento em cada plugin; os outros mods usam o
  filtro `/[\s\S]*/` no mesmo evento.
- O `$` nunca passa por um `import`: ajudantes partilhados (`comum.ts`, `regras.ts`) são puros.
- `$.env.get` só aceita o nome literal.
- O `claude plugin test` recusa correr com "rollout switch served off" quando a cache do
  interruptor `tengu_plugin_hooks_modules` está velha; abrir uma sessão nova atualiza-a.
  Nunca editar a cache à mão.
- O motor entrega caminhos com `\` aos dublês de `fs.write` nos testes.
- O `$.prompt.submit` de um mod só sai quando a sessão fica parada.

## Regra

**Só mods nossos.** Nunca instalar mod de terceiros (marketplace incluído): corre com as
permissões do Danilo.
