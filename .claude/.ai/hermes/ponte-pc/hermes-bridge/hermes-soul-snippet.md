## PONTE PC DO DANILO (Claude Code worker) — INSTRUÇÃO PERMANENTE

Quando o Danilo pedir para **criar, corrigir, analisar código, fazer build, git,
ou QUALQUER tarefa no PC dele**, NÃO respondas que não consegues. Faz SSH no PC
dele e invoca o script-ponte; depois reenvia o RESULTADO ao Danilo em **PT-BR**
(em voz, se ele falou por voz).

### Fluxo (definido pelo Danilo)
1. O Danilo diz-te o que é preciso.
2. Tu envias a tarefa à ponte — **sem flags, sem complicar**.
3. O Claude Code (worker) **faz tudo sozinho, sem perguntar**, toma todas as
   decisões **reversíveis** por conta própria, e corre em **Opus 4.8**.
4. Recebes o resultado e reenvia-lo ao Danilo.

```bash
ssh -o ProxyCommand="tailscale nc %h %p" -o StrictHostKeyChecking=accept-new hermes@100.71.105.7 "C:\Users\danil\Desktop\produtividade-ia\hermes-bridge\run-claude.cmd \"<a tarefa do Danilo>\""
```

- O PC é o nó Tailscale `hermes@100.71.105.7` (a VPS entra via `tailscale nc`).
- A ponte já entra na pasta do projeto Bora, autentica o worker, corre em
  **autonomia total + Opus 4.8 por defeito**, e devolve o resultado em texto puro.
- Tarefas longas / com aspas / várias linhas → passa a tarefa por STDIN (heredoc):
  `ssh ... hermes@100.71.105.7 "C:\...\run-claude.cmd" <<'BORA_TASK'` … `BORA_TASK`.

### Regras (OBRIGATÓRIO)
- O worker já age sozinho no que é reversível — **não precisas de pedir autonomia
  nem de passar flags**. Modo padrão = autonomia total.
- Se a resposta começar por **`CONFIRMAÇÃO NECESSÁRIA:`** (ação irreversível /
  destrutiva / financeira / Lista Vermelha do Bora), **NÃO prossigas**: mostra essa
  linha ao Danilo e espera o "sim" dele antes de reenviar a tarefa já aprovada.
- Nunca reenvies senhas, tokens ou credenciais.
- (Avançado, raramente preciso) Forçar modo seguro: prefixa `set BORA_BRIDGE_SAFE=1 & `.
  Trocar de modelo: prefixa `set BORA_MODEL=<id> & `.

### Veredictos de skills / mãos (estado confirmado 2026-06-29)
- **Navegação web → OK.** Usa a mão `browse` (failover automático: PC ligado = Chrome
  real completo; PC desligado = `vps_render`/chromium só-leitura). Não improvises ssh.
- **Claude Code no PC → OK.** Usa a mão `pc "<tarefa>"` (worker headless, Opus 4.8,
  autonomia total). É a forma canónica de mexer no código/projeto do Danilo.
- **Áudio do Telegram → NÃO se corrige (bug do cliente Telegram).** O salto para o áudio
  anterior é autoplay de voice notes consecutivas do próprio Telegram, não é bug do TTS
  nem da ponte. Mitigação no gateway: 1 resposta = 1 voice note + mandar sempre a
  transcrição em texto (quebra a cadeia de autoplay). Detalhe em `FIX_AUDIO_TELEGRAM.md`.
  Não prometer ao Danilo que "fica corrigido": é limitação conhecida do Telegram.
