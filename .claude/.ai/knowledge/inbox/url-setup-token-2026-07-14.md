# URL de setup-token capturada (2026-07-14)

**Tarefa:** [PROPOSE-ONLY não aplicável — só captura+report] Correr `claude setup-token`
na VPS (container `hermes-agent-fvnc-hermes-agent-1`) com timeout curto, capturar SÓ a
URL de autorização impressa, sem manter sessão viva nem esperar código.

## O que foi feito

1. SSH `root@srv1786862.hstgr.cloud` (chave `id_ed25519_vps`, já validada antes — ver
   [[project_hermes_bridge_oneway]]).
2. **Gotcha novo:** `docker exec ... claude setup-token` dentro do container NÃO chama o
   binário real — `/usr/local/bin/claude` é um **shim** que diz "Não chames 'claude'
   diretamente... A redirecionar para o PC via pc" (o `claude` do container não está
   logado; o shim existe para o Hermes não o apanhar por engano durante operação normal).
3. Binário real localizado: `/usr/local/lib/node_modules/@anthropic-ai/claude-code/node_modules/@anthropic-ai/claude-code-linux-x64/claude` (v2.1.185).
4. Corrido via `timeout 15 script -qc "<binário real> setup-token" /dev/null`, output
   capturado com `head -60`, sessão morta pelo timeout (não ficou nada pendurado).

## ⚠️ URL de autorização (válida até se correr `setup-token` de novo — cada corrida gera code_challenge/state novos)

```
https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback&scope=user%3Ainference&code_challenge=aQgcibgEatnCcErZJ_cxgWSIGGVwOlr4zxnvng_8WLw&code_challenge_method=S256&state=yLJpJ-MWXkSoFEl-nMojgWIdb9FyPETnTTpSzAbXrAw
```

## Próximo passo (não feito agora — fora de escopo desta tarefa)

Para completar o login: o Danilo abre a URL acima, autoriza, copia o código, e depois é
preciso correr `setup-token` **de novo** (gera state novo) e colar o código na mesma
sessão interativa — não dá para reaproveitar esta URL depois de gerada uma nova corrida.

---

URL: https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback&scope=user%3Ainference&code_challenge=aQgcibgEatnCcErZJ_cxgWSIGGVwOlr4zxnvng_8WLw&code_challenge_method=S256&state=yLJpJ-MWXkSoFEl-nMojgWIdb9FyPETnTTpSzAbXrAw
