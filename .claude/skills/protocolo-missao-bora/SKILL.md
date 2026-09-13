---
name: protocolo-missao-bora
description: >
  Protocolo para escrever, arrancar e fechar uma missão do Bora: formato do prompt de missão,
  escolha da porta (Claude Code / OpenCode / navegador) e do motor, MCP-first, autonomia total
  com carta, lei do pré-voo, observabilidade no e2e_log, paridade do painel admin, digest para
  os outros motores em claude_ai_memoria, idiomas e regras de CI/build. Usar sempre que se vai
  redigir uma ordem de missão, arrancar uma janela nova, ou fechar uma missão (Bloco F).
metadata:
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: missão fable-13-09 (2026-09-13)
---

# PROTOCOLO DE MISSÃO — Bora
> Escrito a 13/09/2026 a partir das missões de Setembro (ios-lancamento, fable-13-09) e do
> `PADRAO_BORA.md`. Entra pelo CEO-AI como todas as skills: **não substitui** o `PADRAO_BORA.md`
> (lei da casa) nem a Lista Vermelha do `ceo-ai` (§1.6). Se isto e o PADRAO discordarem, manda o PADRAO.

## 1. As três portas (13/09/2026) e a escolha do motor

Facto que manda (página `sistema-motores-e-portas` em `claude_ai_memoria`): pelos termos da
Anthropic a assinatura Claude só funciona **dentro** do Claude Code e da Claude.ai — nenhuma
ferramenta de terceiros a pode usar. Por isso há no mínimo duas portas, e na prática três:

| Porta | O que corre lá | Para quê | O que NÃO faz |
|---|---|---|---|
| **1 · Claude Code** (app/CLI no PC do Danilo) | só motores Claude: Opus, Sonnet; Fable só enquanto o Max durar | executar: repo, MCP Supabase, migrações, builds, provas, publicação; **o loop automático (cortex_nova_ordem → carteiro → executor) corre SEMPRE aqui** | — é a porta de execução por defeito |
| **2 · OpenCode** (mesma pasta, colagem manual do Danilo) | ChatGPT Plus por `/connect openai` (gpt-5.x/codex); plano Go (glm-5.2, qwen3.8-max, qwen3.7-max, minimax-m3); Zen grátis; Ollama local — troca-se com `/models` na mesma janela | código médio, refactors, testes, Edge Functions, scripts, volume, telas, traduções, segunda opinião | não tem os hooks da Trava do Claude Code → só zona 🟢; nunca dinheiro, dispatch, wallet, RLS ou publicação em produção |
| **3 · Navegador** (Chrome do PC com sessões pagas) | Gemini web (Veo, Nano Banana), ChatGPT web, Claude.ai | imagem/vídeo (pago primeiro, grátis só em último), leitura de documentos longos, juiz de visão, conversa/decisão/prompts | não executa no repo; não vê a base de dados senão por MCP da Claude.ai |

**Divisão por motor (decidida 13/09):** FABLE = só o crítico (dinheiro, dispatch, wallet,
publicação em produção) · OPUS = zonas protegidas, multi-ficheiro difícil, agente de clique/Chrome,
loop do carteiro · CHATGPT = código médio, refactors, testes, Edge Functions, scripts, imagens da
propaganda · GLM/QWEN = volume, bugs simples, telas, traduções, rascunhos · GEMINI = imagem/vídeo,
documentos longos, juiz de visão, reserva grátis.

**Motor:** o mais barato que aguente a tarefa com segurança (`~/.claude/CLAUDE.md` §2); Claude só
quando nenhum dos outros serve. Sobe para Opus ou acima **sempre** que toque em dinheiro real,
pagamentos, preços, comissões, carteira, dispatch ou zona protegida. Toda a ordem diz no topo
**MOTOR + PORTA** e o fallback na mesma janela (ex.: "Fable → Opus 4.7"), e diz em letras claras
"abre SESSÃO NOVA no Claude Code na pasta X" (uma missão = uma sessão nova; missão grande nunca
corre pelo loop).

**Os motores falam entre si pela tabela `public.claude_ai_memoria`** (`pagina`, `titulo`,
`conteudo`, `origem`, `atualizado_em`): cada janela lê as páginas no arranque e deixa o seu
digest no fim (§7). É a única memória partilhada entre Claude, ChatGPT e OpenCode.

## 2. Formato do prompt de missão (completo e fechado)

Um prompt de missão não deixa nada "a combinar depois". Esqueleto:

```
⚠️ MODO PROTECÇÃO TOTAL ⚠️
run_id: <slug-data>   fluxo e2e_log: <mesmo slug>   data: <dd/mm/aaaa>
Porta: <Claude Code | OpenCode | navegador>   Motor: <X → fallback Y na mesma janela>
Invoca o CEO-AI primeiro. Lê PADRAO_BORA.md e business_rules.md antes de planear.

BLOCO 0 — reconhecimento: ambiente, claude_ai_memoria, últimas 200 linhas do e2e_log,
  migrações de produção vs repo, plano de 5 linhas gravado no e2e_log.
BLOCO 1..N — por ordem de prioridade; cada subitem com CRITÉRIO DE FEITO verificável por máquina
  (SELECT, código HTTP, ficheiro com md5, teste verde) e a prova que tem de ficar guardada.
BLOCO F — fecho obrigatório (§8), mesmo que o contexto esteja a acabar.
CARTA DE AUTONOMIA (§4) — copiada por inteiro, nunca resumida.
```

Regras do texto: português simples; um bloco por assunto; o que é dinheiro diz "dinheiro" no
título do bloco; nunca "se der", "talvez", "vê se consegues" — ou está na ordem ou não está.

## 3. MCP primeiro

Antes de deduzir, **verifica**. Ler a base de dados é melhor do que adivinhar pelo código.
- Supabase MCP: `execute_sql` para ler/provar; `apply_migration` para tudo o que muda schema ou
  função (o MCP dá o número da versão — o ficheiro do repo fica com esse número e o SQL literal).
- Córtex (`cortex_buscar_semantico` / `cortex_ler`) antes de tarefa não-trivial; `cortex_memorizar`
  no fim só com factos confirmados. Se o MCP do Córtex pedir autenticação, regista-se e segue-se.
- O que o MCP não alcança (GitHub Actions sem `gh`, App Store) prova-se pelo efeito: o
  `app_latest_version_code` em `platform_settings`, o `lookup` da Apple por país, um HTTP 200 lido.

## 4. Carta de autonomia (vai inteira em cada ordem)

- Decides sozinho. **Nunca terminas o turno à espera.** Um bloco preso mais de 15 min → linha no
  `e2e_log` com a causa real e passa-se ao seguinte.
- **Nada de perguntas ao Danilo.** O que só ele pode fazer (pagar, senha, clique de autorização,
  decisão legal) fica anotado e é pedido **UMA vez no fim**, pelo Telegram (ponte Hermes), com a
  página já aberta.
- **"Feito" só com prova material** (regra 4 do `~/.claude/CLAUDE.md`): saída literal, SELECT de
  volta, código HTTP, ficheiro lido. Proibido "assumido", "deve estar", "provavelmente".
- **Zonas protegidas** (`dispatch_engine`, `pricing_service.dart`, `finalizePurchase`,
  `bora_tokens`, webhook Stripe, RLS de `orders`/`wallets`/`ledger`) só se mexem **com ordem
  explícita nessa missão e com teste real** (prova em rollback com o JWT da pessoa + pedido de
  teste real). O relatório leva sempre a frase **"⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO"** com a
  lista fechada do que foi aplicado e como se reverte.
- **Os hooks da Trava mandam; não se contornam.** O que a Trava bloquear no repo resolve-se por
  MCP Supabase (`apply_migration`) e regista-se. Reformular o texto (a Trava lê comentários como
  código) é legítimo; desligar a Trava não é.
- **Toda migração aplicada em produção fica no repo** em `supabase/migrations/` com o SQL exacto e
  o timestamp de produção; nunca se reaplica o que já está no ar.
- **Outra janela em paralelo** não toca no mesmo repo. Ficheiros alterados que não são teus →
  `git stash save "<nome>"` (não `stash push`: a guarda lê "push") e segue.
- **Sem push fora do bloco de publicação.** Push = publicação (Play + web). O CI faz o bump do
  `versionCode` — nunca à mão.
- Apps em PT-PT, painel admin em PT-BR, relatórios em português simples para ser ouvido em voz.
- **Toda a feature tem correspondência no painel admin** (gatilho de paridade: convocar `admin`).
- **LOGIN NO NAVEGADOR (regra do Danilo, 13/09/2026):** quando precisares de um site ou painel onde
  não há sessão, ou não conseguires abrir/entrar em alguma janela, não tentes senhas nem peças
  token a ninguém — abre a página de login no próprio Chrome do PC (perfil boraappbora), avisa o
  Danilo pelo Telegram numa linha e continua quando a sessão existir. Fica gravada no Chrome e
  serve para sempre. Uma vez por site.
  **Adendo (13/09, à noite): é o último recurso, não o primeiro.** Nunca sair de uma conta que
  já está iniciada (o Chrome do perfil boraappbora tem o ChatGPT **Free**). Procurar primeiro a
  sessão que já existe: `codex login status` e `~/.codex/auth.json` (conta e plano), o
  **aplicativo do ChatGPT instalado no Windows** (processo `ChatGPT.exe` — é aí que vive a conta
  **Plus**, e é ela que o Codex usa), os outros perfis do Chrome e o Edge. Modo de programador e
  conectores (Córtex, Supabase) configuram-se nas Definições da conta Plus, no app pelo agente
  de clique se só existir lá. OpenCode `/connect openai`: o OAuth abre no navegador predefinido —
  se esse não tiver a sessão Plus, levar o URL ao navegador/perfil que a tem. Imagens: gerar na
  sessão Plus, app ou navegador. Só sem nenhum caminho é que se abre `chatgpt.com/auth/login`
  no Chrome e se pede ao Danilo, pelo Telegram, para entrar uma vez.

## 5. Lei do pré-voo

Antes de começar cada bloco, simular o caminho: timeout, ficheiro/dispositivo em falta,
permissão, RAM (portão 400 MB leve / 800 MB para compilar — medir com
`(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes`), ferramenta que pode
não existir (`gh`, Java certo, Flutter do CI ≠ Flutter do PC). Previsão de falha → muda a
abordagem antes de agir. **Duas falhas iguais → muda de abordagem; nunca uma terceira igual.**
Provas de dinheiro correm **primeiro em rollback** (`DO $$ … RAISE EXCEPTION 'RESULT %' … $$`)
e só depois com pedido de teste real marcado `is_test_order`.

## 6. Observabilidade — o rasto que fica

- `public.e2e_log` (`fluxo` = `run_id`, `passo` = `b<bloco>.<sub>-<nome>`, `estado` ∈ ok ·
  aplicado · provado · corrigido · aviso · falhou · em-curso · fim, `detalhe` com números e
  saídas literais, `device`, `run_id`). Uma linha por subitem; a primeira é o `plano`, a última é o `fim`.
- Provas em `.claude/.ai/provas/<run_id>/` (logs, diffs, capturas, scripts que correram).
- Relatório em `.claude/.ai/reports/<MOTOR>-<data>.md` com cópia em `C:\Users\danil\Desktop\Bora\prompts\`.
- Quarentena (nunca apagar): `C:\Users\danil\_QUARENTENA\<data>\<run_id>\` com `indice.csv`.

## 7. Digest para os outros motores

No fim de cada janela (e a meio, se o contexto estiver a acabar):

```sql
insert into public.claude_ai_memoria (pagina, titulo, conteudo, origem)
values ('digest-<aaaa-mm-dd>-janela-<n>', 'Janela <n> <MOTOR> <dd/mm> — resultado',
        '<10-20 linhas em texto corrido: feito, por confirmar, o que precisa do Danilo, onde estão as provas>',
        'claude-code')
on conflict (pagina) do update set conteudo = excluded.conteudo, atualizado_em = now();
```

## 8. Bloco F — fecho obrigatório

1. Relatório em ficheiro: **acessos no topo; o que NÃO foi feito logo a seguir**; depois bloco a
   bloco com a prova; a secção "⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO" se houver; "PARA O DANILO"
   só com o que só ele pode fazer, com a página/link pronto.
2. Digest (§7). 3. `e2e_log` com o passo `fim`. 4. Telegram em 6 linhas: feito, por confirmar,
   o que precisa do Danilo — pela `orquestracao/ponte-telegram.sh` (base64; ler o log de volta).
5. Se ficou meio-feito: ordem de continuação (`cortex_nova_ordem` ou
   `.claude/.ai/inbox/CONTINUAR-<run_id>.md`) com o ponto exacto — nunca deixar sem mapa.
6. Telemetria da skill usada (frontmatter + linha em `.claude/.ai/knowledge/wiki/skills-metrics.md`).
7. Memória: notas no auto-memory do Claude Code só com o que não está no repo; Córtex se responder.
8. Terminar com `/ctx doctor` e `/ctx stats`.

## 9. CI, build e publicação

- Android: push a `autonomous-night-2026-04-29` → `build_android.yml` (job `autoteste` dos 3
  perfis demo no emulador com Play Store **antes** do `build`; o `build` faz o bump e sobe ao
  Play). **Sem verde, nada é publicado.** Prova do build: `app_latest_version_code` subiu.
- iOS: parte-se sempre de `origin/ios-lancamento` (a linha da build aprovada). Portões iOS:
  varredura de ecrãs + teste do `Info.plist` antes de qualquer build.
- Web: sai junto com o Android (mesmo push). bora-site: `wrangler` (`deploy-cloudflare.sh`), não push.
- Local ≠ CI: o CI corre Flutter 3.41.2 / Java 17; o PC pode ter outro Flutter e outro Java —
  quando o build local falha por ferramenta, corrige-se a ferramenta do PC (JDK portátil,
  `flutter config --jdk-dir`, `--android-skip-build-dependency-validation`), **nunca o Gradle do repo**.
- Push por HTTPS/GCM; nunca `--force`; nunca `reset --hard`.

## 10. Modelo de prompt curto de missão

```
⚠️ MODO PROTECÇÃO TOTAL ⚠️  run_id <slug>  data <dd/mm>  Porta Claude Code  Motor <X → Y>
Invoca o CEO-AI; lê PADRAO_BORA.md e business_rules.md; segue a skill protocolo-missao-bora.
Bloco 0: reconhecimento.  Bloco 1: <assunto, critério de feito>.  Bloco 2: <…>.
Bloco F: fecho completo.  Carta de autonomia inteira em anexo.
```

## 📊 Telemetria (obrigatório no fim de cada execução)
1. Actualizar o frontmatter: `execucoes`, `sucessos` ou `falhas`, `ultima_execucao`.
2. Uma linha em `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
