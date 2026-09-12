---
id: setup-token-tmux-2026-07-14
tipo: relatorio
zona: verde (infra/autenticacao; nenhum dado de pagamento tocado)
criada: 2026-07-14
autor: claude.ai (missão "SETUP-TOKEN VIA TMUX PERSISTENTE")
---

# Setup-token via tmux persistente — sessão `stk` viva na VPS

**Tarefa:** gerar a URL de autorização do `claude setup-token` e manter a MESMA sessão
tmux viva para colar o código depois — evitando o problema das tentativas anteriores
(`f292`/`b1a7`, ver [[url-setup-token-2026-07-14]] e [[setup-token-url-2026-07-14]]) em
que o `code_challenge`/`state` mudavam entre execuções porque a sessão não sobrevivia
entre passos.

## O que foi feito
1. SSH `root@srv1786862.hstgr.cloud` (chave `/c/Users/danil/.ssh/id_ed25519_vps`, já
   validada — ver [[project_hermes_bridge_oneway]]). `tmux` e `claude` (v2.1.209) estão
   instalados diretamente no host da VPS (não dentro do container `hermes-agent-fvnc`).
2. `tmux kill-session -t stk` (limpeza de qualquer resíduo anterior — sessão não existia).
3. `tmux new-session -d -s stk` — sessão nova, destacada.
4. `tmux send-keys -t stk 'claude setup-token' Enter`.
5. Esperei ~9s e capturei o painel (`tmux capture-pane -t stk -p`); depois fiz
   `tmux resize-window -t stk -x 400 -y 50` e recapturei para confirmar a URL sem quebra
   de linha (a 1ª captura tinha wrap por causa da largura default 80 colunas — reconstruí
   à mão e bateu 100% com a recaptura larga).
6. **Não colei nada.** A sessão `stk` continua viva, no prompt `Paste code here if
   prompted >`, à espera do código.

## ⚠️ Gotcha confirmado (mesmo problema das tentativas f292/b1a7, agora contornado)
Cada corrida de `claude setup-token` gera `code_challenge`/`state` (PKCE) novos. Só a URL
gerada **na sessão tmux que vai receber o código** é válida — não dá para reaproveitar a
URL de uma corrida anterior nem gerar a URL numa sessão e colar o código noutra. É por
isso que existe ainda uma sessão tmux antiga `setup-token` na mesma VPS (criada às
16:26, ver [[setup-token-url-2026-07-14]]) com uma URL **agora stale** — não a usar.
Só a sessão `stk` (criada 16:32) e a URL abaixo são válidas neste momento.

## URL de autorização (sessão `stk`, válida até expirar ou até se correr `setup-token` de novo)
```
https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback&scope=user%3Ainference&code_challenge=gk9BTdO5GqDV-aK0yZetNqVPRi-eRNN7Lly-bfuYv78&code_challenge_method=S256&state=sYSGUYBrfyd6c-88TReXmoBcZwIgLJWZtNv5Q_MOy4Q
```

## Próximo passo (para o Danilo, manual)
1. Abrir a URL acima no telemóvel ou browser normal.
2. Autorizar a app "Claude Code" na conta.
3. Copiar o **código** devolvido em `platform.claude.com/oauth/code/callback?code=...`.
4. Injetar o código na MESMA sessão `stk` (não recriar, não usar a `setup-token` antiga):
   ```
   ssh -i /c/Users/danil/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud
   tmux send-keys -t stk "CODIGO_AQUI" Enter
   ```
   (ou `tmux attach -t stk` e colar à mão, depois `Ctrl+B D` para destacar sem matar).
5. Se a troca de código por token passar, a VPS fica com um token de longa duração
   autenticado — útil como redundância ao PC (ver [[project_headless_push_credential]]
   sobre a limitação do executor headless no PC).

## Estado atual
- Sessão tmux `stk` na VPS: **viva**, à espera do código, não expira por timeout de SSH.
- Sessão tmux `setup-token` (antiga, 16:26): ainda viva mas com URL **stale** — não tocada
  por esta tarefa (não fazia parte do pedido matar sessões que não sejam `stk`); o Danilo
  pode matá-la manualmente (`tmux kill-session -t setup-token`) quando quiser.
- Nenhuma credencial foi criada ainda; nenhuma ação irreversível tomada.

---
URL: https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback&scope=user%3Ainference&code_challenge=gk9BTdO5GqDV-aK0yZetNqVPRi-eRNN7Lly-bfuYv78&code_challenge_method=S256&state=sYSGUYBrfyd6c-88TReXmoBcZwIgLJWZtNv5Q_MOy4Q | tmux stk vivo a espera do codigo.
