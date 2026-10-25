---
name: distribuir-trabalho
description: >
  OBRIGATÓRIA em toda a missão, prompt, ordem do carteiro ou lista de tarefas do Bora (e de qualquer
  projeto do Danilo). O Danilo abre SÓ o Claude Code: o Claude é o CHEFE e reparte o trabalho pelos
  outros motores por dentro da sessão — ChatGPT Plus (opencode run / codex), GLM e Qwen (plano Go),
  Gemini (CLI ou perfil Bora do Chrome), modelos grátis do Zen — pelo script ~/.claude/motores/delegar.ps1,
  com a cascata de ~/.claude/motores/MOTORES.json. Dispara sempre que houver mais do que uma peça de
  trabalho, código a escrever, refactor, testes, scripts, Edge Functions, traduções, telas, rascunhos,
  documentos longos para ler, imagens ou vídeo para gerar, ou quando alguém pensar em mandar o Danilo
  "abrir o OpenCode/ChatGPT/Gemini" ou "colar" alguma coisa noutra ferramenta (proibido). Dinheiro,
  dispatch, wallet, RLS, git push e publicação NUNCA se delegam. Quem faz não verifica.
metadata:
  versao: 1.0
  criada: 2026-09-17
  criada_por: missão uma-porta-2026-09-17 (Claude Code, Opus)
  origem_da_queixa: "Não quero ficar a comandar OpenCode, ChatGPT e Claude Code. Mando o prompt ao Claude e ele distribui a tarefa por cada um. Não quero copiar e colar." — Danilo, 14/09 e 17/09/2026
  execucoes: 1
  sucessos: 1
  falhas: 0
  ultima_execucao: 2026-09-18 (em-dia b9-fecho, glm, ok)
---

# DISTRIBUIR TRABALHO — uma porta só, o Claude reparte

## 1. Regras que não se discutem
- **O Danilo abre só o Claude Code.** Nenhum prompt, relatório ou mensagem o manda abrir OpenCode, ChatGPT, Codex, Gemini ou colar texto de uma ferramenta para outra. Se uma peça precisa de outro motor, és **tu** que o chamas por dentro.
- **Só o Claude mexe em git, produção e zonas vermelhas** (dinheiro, `dispatch_engine`, `pricing_service`, `finalizePurchase`, `bora_tokens`, Stripe/webhook, RLS de `orders`/`wallets`/`ledger`, migrações, `git push`, publicação). Isso nunca sai da tua sessão (Fable se houver, senão Opus).
- **Quem faz não verifica.** Toda a peça delegada é relida por ti com contexto limpo e testada antes de ser aplicada; mudança em vários ficheiros leva também uma revisão de **outro** motor.
- **O mais barato que dê conta com segurança**, pela cascata do `MOTORES.json`. Pago primeiro nas imagens/vídeo (Gemini AI Plus no perfil Bora, ChatGPT Plus no perfil Danilo); grátis só em último.
- **Prova material**: o `delegar.ps1` faz o teste anti-mentira em cada chamada e devolve código honesto. Sem `RESULTADO {...}` com `"estado":"ok"` não há peça feita.

## 2. O ciclo, peça a peça
1. **Partir** o pedido em peças pequenas (≤ 20 min de trabalho cada), cada uma com **critério de feito verificável por máquina** (teste verde, ficheiro com md5, SELECT, HTTP 200).
2. **Classificar** cada peça pelo tipo do `MOTORES.json` → `cascatas`:
   | tipo | para | cascata |
   |---|---|---|
   | `codigo` | código médio, refactors, testes, scripts, Edge Functions | chatgpt → qwen → sonnet (reserva grátis: zen) |
   | `volume` | volume, bugs simples, telas, traduções, rascunhos | glm → qwen → chatgpt (reserva grátis: zen) |
   | `documentos` | ler documentos longos | gemini → glm → sonnet (reserva grátis: zen) |
   | `imagem-video` | imagem e vídeo de propaganda | gemini-web (perfil Bora) e chatgpt-web (Plus) — os dois geram, o fiscal fica com a melhor; grátis só em último |
   | `dinheiro` | dinheiro, dispatch, wallet, RLS, git push, publicação | **nunca se delega** |
   | `verificacao` | verificação final | tu, com contexto limpo (+ outro motor se forem vários ficheiros) |
3. **Escrever a tarefa num ficheiro** `.md` (na pasta de provas da missão ou no scratchpad): contexto mínimo, ficheiros a tocar, critério de feito, o que é proibido. Nada de segredos.
4. **Delegar** (uma peça de cada vez; no máximo 2 em paralelo e só com mais de 3 GB de RAM livre — o script impõe isto):
   ```powershell
   powershell -NoProfile -File "$env:USERPROFILE\.claude\motores\delegar.ps1" tipo:codigo "<pasta do projeto>" "<tarefa.md>" -Id <id-curto>
   ```
   `<motor>` também pode ser um nome (`chatgpt`) ou uma lista (`chatgpt,qwen,zen`). O trabalhador corre numa **cópia isolada** (sem o `.git` do repo real, com um git descartável só para o diff) em `%LOCALAPPDATA%\bora-delegacoes\<data>\<id>\work` — nunca na árvore principal, nunca em worktree (o OpenCode segue o `.git` da worktree até ao repo real) e nunca dentro de `~/.claude` (o Claude headless não escreve lá). O script força `PWD`/`OLDPWD`/`INIT_CWD` para a cópia porque o OpenCode e o Codex herdam o `PWD` do Bash de quem chama e escreviam na pasta real (provado 17/09). Tempo máximo 20 min, 1 repetição, depois desce para o motor seguinte. Códigos: `0` ok · `3` anti-mentira falhou em todos · `4` todos falharam/timeout · `5` portão de RAM/paralelo · `6` o motor respondeu mas não alterou nenhum ficheiro (não conta como feito) · `1` erro. Os registos (tarefa, prompt, saída, `diff.patch`, `diff-stat.txt`, `log.txt`, `resultado.json`) ficam em `~/.claude/delegacoes/<data>/<id>/`.
5. **Ler o resultado**: a última linha `RESULTADO {...}` (motor que fez, segundos, estado, `alteracoes`) e a pasta `~/.claude/delegacoes/<data>/<id>/` (`saida.txt`, `diff.patch` relativo à raiz da pasta, `diff-stat.txt`, `log.txt`, `erro-*.txt`); a cópia com o trabalho está em `%LOCALAPPDATA%\bora-delegacoes\<data>\<id>\work`. Na tarefa escreve sempre caminhos **relativos** à pasta ("na raiz desta pasta"), nunca absolutos.
6. **Rever com contexto limpo e testar** (tu). Vários ficheiros? Manda o `diff.patch` a outro motor com uma tarefa "revê este diff, aponta erros" (`tipo:codigo`) antes de aplicar.
7. **Aplicar** só depois de aprovado: `git -C <pasta> apply <diff.patch>` na árvore principal (o patch é relativo à raiz da pasta delegada; se a pasta não for git, copiar os ficheiros de `work/` pelos nomes do `diff-stat.txt`), correr os testes, e só então commit — e só o Claude faz commit/push, e nunca fora do bloco de publicação.
8. **Relatório**: para cada peça, o motor que a fez, o tempo, a prova, e o que falhou com a causa real. Se um motor pago estava esgotado (limite semanal do Plus, saldo do Go a zero) e a peça desceu para a reserva grátis ou para o Sonnet, diz-se.

## 3. Estado dos motores (17/09/2026 — verifica com o teste anti-mentira antes de confiar)
- ChatGPT Plus (`opencode run -m openai/…` e `codex exec`, mesma conta nilofulfaro@gmail.com): **limite semanal esgotado até 19/09 09:08**.
- Plano Go (`opencode-go/glm-5.2`, `qwen3.8-max`): **"Insufficient balance"** — só com pagamento do Danilo (opencode.ai, PARA O DANILO).
- Gemini CLI: instalado a 17/09 (v0.60.0). O OAuth pessoal (boraappbora) foi feito mas a Google devolve `UNSUPPORTED_CLIENT` (Code Assist individual descontinuado) — inútil. Funciona pela chave da API do `backend/.env` (lida em runtime pelo `delegar.ps1`) com o modelo `gemini-3-flash-preview` (o por defeito pendura): anti-mentira 29,7 s; cascata `documentos` provada (34 s). Com cap/403/429 → Gemini web AI Plus no perfil Bora pelo agente de clique (skill `contas-e-navegadores`).
- Zen grátis (`opencode/nemotron-3-ultra-free`, `opencode/big-pickle`): passou o anti-mentira; serve para peças de baixo risco. **Nunca recebe dados de clientes, pedidos, telefones, emails, `.env` ou chaves** (pode treinar com o conteúdo): o `delegar.ps1` varre a tarefa e a cópia e, se for sensível, salta o Zen e mete o Sonnet (provado 17/09). Ficheiros de segredos (`.env*`, `.pem`, `.key`, `.p12`, `.jks`, `.keystore`, `.pfx`) nunca são copiados para nenhum motor.
- Ollama local: devolveu vazio via opencode — não contar. Desde 17/09 o modelo já não fica sempre quente (aquecedor do cérebro do WhatsApp desligado): carrega quando chamado e sai da memória depois.
- `refrescar-motores.ps1` atualiza a lista viva de modelos uma vez por semana (tarefa `MotoresRefrescar`).

## 4. O que nunca fazes
- Mandar o Danilo abrir outra ferramenta ou colar texto.
- Delegar dinheiro, dispatch, wallet, RLS, migrações, push ou publicação.
- Aplicar um diff sem o ter lido e testado tu.
- Dizer "feito" sem o `RESULTADO` do script e a prova do teste.
- Esconder erros com `2>$null` ou `-o /dev/null`.

## 📊 Telemetria (no fim de cada uso)
Incrementa `execucoes` e `sucessos`/`falhas` no frontmatter; uma linha em `.claude/.ai/knowledge/wiki/skills-metrics.md` quando estiveres num repo do Bora; o relatório diz o motor de cada peça.
