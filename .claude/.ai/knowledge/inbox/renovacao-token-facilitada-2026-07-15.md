---
tipo: handoff
data: 2026-07-15
agente: devops-ci (executor autonomo)
estado: atual
---

# Atalho de renovação do token da VPS — mínimo de cliques para o Danilo

## O que existia antes
Quando o token OAuth do Claude Code na VPS expira, o Danilo tinha de: SSH manual à VPS →
copiar a URL longa gerada por `claude setup-token` → abrir no telemóvel → autorizar → copiar
o código → voltar ao terminal SSH e colar. Muitos passos manuais, terminal exposto.

## O que foi criado
**`renovar-vps-token.cmd`** (raiz do repo `bora-app-cloud`, ao lado do `assistir.cmd` já
existente — o repo já é a pasta que o Danilo tem no ambiente de trabalho do Windows).

Fluxo reduzido a **2 cliques do Danilo**: autorizar no browser + colar o código.
Tudo o resto (SSH, tmux, extração da URL, abrir o browser, injetar o código) é automático.

1. O script faz SSH à VPS (`root@srv1786862.hstgr.cloud`, chave
   `%USERPROFILE%\.ssh\id_ed25519_vps` — mesma já usada no fluxo manual documentado em
   `e2e-via-vps-web-2026-07-11.md`) e (re)arranca uma sessão tmux persistente `authnow2` a
   correr `claude setup-token` — o **mesmo mecanismo real usado manualmente em 2026-07-14**
   (confirmei o processo `tmux new-session -d -s authnow2 ... claude setup-token` ainda vivo
   no host, PID root de ontem).
2. Captura o pane da sessão via `tmux capture-pane -p` e extrai a URL `https://...` com
   `grep -oE`.
3. Abre essa URL automaticamente no browser padrão do Windows (`start ""  "%URL%"`) — o Danilo
   **não precisa copiar/colar a URL**, só vê o browser abrir.
4. Pede ao Danilo para colar o código (`set /p CODE=`) depois de ele autorizar.
5. Envia o código de volta para a sessão tmux da VPS via `tmux send-keys ... Enter` por SSH,
   espera 3s, e mostra as últimas linhas do pane para confirmação visual ("Login successful").

Se o Danilo não colar nada, a sessão tmux fica aberta na VPS (nada se perde) e o aviso diz
como continuar manualmente (`ssh %HOST% "tmux attach -t authnow2"`).

## O que foi testado (e o que NÃO)
Testado **nesta sessão, na própria VPS** (sem esperar o token expirar de verdade, como pedido):
- Mecânica de `tmux new-session` + `capture-pane -p` + `grep -oE 'https://[^ ]+'` para extrair a
  URL de um processo interativo a correr dentro da sessão — **funciona**.
- Mecânica de `tmux send-keys` a injetar um código de volta na sessão e confirmar a mensagem de
  sucesso no pane — **funciona** (testado com um mock que imprime URL + espera código +
  responde "Login successful, code=...").
- A string exacta do comando remoto que o `.cmd` envia via SSH (incluindo o `usebackq` +
  backticks do `FOR /F` no lado Windows, necessário porque o comando remoto tem aspas simples
  internas) foi revista à mão para confirmar que as aspas ficam balanceadas.

**Não testado** (fora do alcance desta sessão, sem root nem PC Windows):
- O `claude setup-token` real — não tenho root na VPS nesta sessão (`sudo` pede password), e
  correr `claude` dentro deste container redireciona para a ponte do PC do Danilo (shim
  `/usr/bin/claude` → `pc`), o que teria efeitos colaterais indesejados. Não toquei na sessão
  `authnow2` de ontem (só a inspecionei via `ps aux`, sem conseguir ler o pane por falta de
  root).
- A execução real do `.cmd` num Windows de facto (`start`, `ssh.exe`, `set /p`) — não há PC
  Windows disponível nesta sessão. A sintaxe segue o padrão já usado no `assistir.cmd` e nos
  scripts documentados em `e2e-via-vps-web-2026-07-11.md` e `daily-pulse/SKILL.md`.

## Próxima vez que o watchdog avisar "token expirou"
1. Danilo faz duplo-clique em `renovar-vps-token.cmd` na pasta do repo (ambiente de trabalho).
2. Espera a janela abrir o browser sozinha.
3. Clica **Autorizar**.
4. Copia o código da página e cola na janela do `.cmd` quando pedido.
5. Confere a última linha mostrada ("Login successful" ou parecido) — feito.

## Ficheiros tocados
- `renovar-vps-token.cmd` (novo, raiz do repo)
- `.claude/.ai/knowledge/inbox/renovacao-token-facilitada-2026-07-15.md` (este handoff)

## Para o bibliotecário-cerebro
Sugestão de destino permanente: `procedural/convencoes.md` ou um novo
`procedural/licoes/licao-renovacao-token-vps.md` — regista o mecanismo `tmux authnow2` como o
canónico para renovação de token (evita reinventar da próxima vez), e liga a
`e2e-via-vps-web-2026-07-11.md` (onde o acesso SSH ao host já estava documentado).
