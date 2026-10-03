# bora-mods — os mods do Claude Code do Bora

> Escrito a 02/10/2026 (missão `mods-bora-2026-10-02`). Claude Code **2.1.287** ou mais novo.
> Para o Danilo, para o Córtex e para o próximo Claude.

Um mod é um plugin de código que corre **dentro** do Claude Code, em todas as sessões deste PC.
Este plugin tem cinco, ligados por esta ordem (a ordem conta: a tranca vem primeiro):

1. **Tranca** (`hooks/tranca.ts` + regras em `hooks/regras.ts`)
   - **Proíbe por código** (nunca se desliga por comando): editar zonas vermelhas (lista em
     `zonas-vermelhas.json`: preços, finalizePurchase, dispatch, Edge Functions de pagamento,
     a própria Trava, settings, workflows do CI, este plugin); mexer na versão do `pubspec.yaml`;
     ficheiros de segredos e segredos em texto claro; `git push --force`/`-f`/`+refspec`
     (o `-F` de uma mensagem de commit já não engana); `git add -A`/`.`; `git reset --hard`;
     `git checkout -- .`; `rm -rf` fora de `build/`, `.dart_tool/`, `node_modules/`;
     `supabase db reset`; SQL destrutivo nas tabelas de dinheiro; UPDATE/INSERT/DELETE direto
     em orders/drivers/wallets… (regra 16/09); políticas RLS de dinheiro; DDL de funções de
     dinheiro; deploy das Edge Functions protegidas (lista PROTSLUG lida do `protege-banco.sh`).
   - **Pergunta ao Danilo** (Recusar por defeito, e sempre Recusar em `claude -p`): `git push`
     normal ("isto publica na Play Store a 100%"), migrations, mudanças de estrutura na base,
     deploy de outras Edge Functions.
   - **Aprova sem caixa de permissão** só o que é leitura: Read/Grep/Glob, `git status/log/diff`,
     `flutter analyze/test/pub get`, SELECT de uma instrução sem funções desconhecidas, listagens
     do Supabase e do Córtex, edições em `lib/`, `test/`, `docs/` e `*.md` fora das zonas.
   - Se a tranca rebentar, **nega** (fail-closed). As regras `deny` dos settings continuam a
     mandar: a tranca não consegue aprovar o que eles proíbem.
2. **Vigia** (`hooks/vigia.ts`): turno a correr e 15 min sem avanço → aviso, `vigia.log`,
   `e2e_log` (chave anon do `.dart_defines`, só insere) e Telegram se houver credencial no PC.
   A mesma chamada 5× seguidas → aviso e lembrete ao Claude (1× a cada 10 min).
3. **Contador** (`hooks/contador.tsx`): a roda de espera mostra `ctx 42% · chamadas 17`; banda
   por cima do prompt com contexto, limite do plano e custo; avisos a 70% e 90% de contexto e a
   80% do plano ("passa o volume ao GLM/OpenCode"). Não chama modelo nenhum.
4. **Painel do CI** (`hooks/ci.tsx`): builds Android, web e iPhone do ramo de trabalho, com o
   versionCode; abre com `/ci` ou sozinho 30 s depois de um `git push`. Botões "Ver log" e
   "Mandar ao Claude" nos que falharam. Lê pelo `gh` se existir, senão pela API do GitHub com a
   credencial do Git do PC.
5. **Contexto** (`hooks/contexto.ts`): ao arrancar diz que os mods estão ativos e confere o
   `ceo-ai`; num prompt que começa por `⚠️ MODO PROTECÇÃO TOTAL` junta o ramo, o último commit
   e o trabalho por gravar; avisa se um prompt de missão vier sem esse cabeçalho.

## Comandos

`/tranca` (últimas 20 decisões e contagem) · `/tranca-off 15` (desliga **só** as aprovações
automáticas por 15 min, máx. 120) · `/vigia` · `/custo` · `/ci` · `/bora` (mapa curto).

## Onde fica o registo

`.claude/.ai/mods/tranca.log`, `vigia.log`, `contexto.log` — uma linha JSON por evento, sem
segredos. Estão no `.gitignore` (`*.log`).

## Como está instalado

Variável de ambiente do utilizador do Windows
`CLAUDE_CODE_PLUGIN_DIRS = C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\plugins\bora-mods`
(o `Desktop\projetosflutter` é uma junção para `C:\BoraLocal\projetosflutter`). Vale para
todas as sessões **abertas depois** de 02/10/2026 09:00, incluindo as do lançador `.cmd` e o
loop. O bloco `env` do `~/.claude/settings.json` não foi usado: a Trava antiga bloqueia a
edição de qualquer `.claude/settings.json` e não se contornou.

## Como desligar

- Uma sessão: `claude --safe-mode`.
- Tudo: `"disableAllHooks": true` num settings, ou apagar a variável `CLAUDE_CODE_PLUGIN_DIRS`.
- A parte que proíbe **não** tem botão: só sai desinstalando (tirar a variável).

## Acrescentar uma zona vermelha

Uma linha nova em `zonas-vermelhas.json` (`padrao` é uma expressão regular sobre o caminho com
barras `/`; `motivo` em português). Esse ficheiro está ele próprio protegido pela tranca: muda-o
o Danilo à mão, ou uma sessão com `--safe-mode` por ordem dele.

## Provar que funciona

```
claude plugin validate .claude/plugins/bora-mods --strict
claude plugin test .claude/plugins/bora-mods          # 43 testes
bun .claude/plugins/bora-mods/verificar/regras.verificar.ts   # 84 verificações com os ficheiros reais
```

## Regra

Só mods nossos. **Nunca** instalar um mod de terceiros: corre com as permissões do Danilo.

## Telegram

`BORA_TELEGRAM_BOT_TOKEN` / `BORA_TELEGRAM_CHAT_ID` não existem neste PC (o token do
@BoraHermesbot vive na VPS). Sem eles a vigia avisa no ecrã, no log e no `e2e_log`, e diz
"sem credencial no PC". Não se copiou o token para lado nenhum: o Danilo decide.
