---
id: fix-oauth-cortex-2026-07-17
tipo: fix
zona: verde
estado: atual
data: 2026-07-17
---

# Cortex MCP "cai de hora em hora" — causa e correção

## Causa raiz (confirmada no código, não suposição)
`server.mjs` do `cortex-mcp` (VPS, `/root/cortex-mcp/`) emitia `access_token` OAuth com
**TTL de exatamente 3600s = 1h** (`tokens.set(at, { exp: now() + 3600 })`, 2 ocorrências).
Isto bate ponto-a-ponto com o sintoma "cai de hora em hora".

**Descartado:** reinício do container a apagar sessão em memória — `docker inspect` mostrou
o container de pé há **8 dias, RestartCount=0**. Não é isso. É mesmo o TTL curto do access_token.

## Correção aplicada (aditiva — OAuth continua a existir, nada removido)
`ACCESS_TTL` subiu de `3600` (1h) para `2592000` (30 dias) — igual ao `refresh_token`, que já
era 30 dias. 2 constantes novas (`ACCESS_TTL`, `REFRESH_TTL`) substituem os literais espalhados.
Deploy feito (`bash /root/cortex-mcp/deploy.sh`), imagem rebuilt, container recriado.

**Testado end-to-end no VPS por curl** (discovery → DCR → `/authorize` PKCE S256 → `/token` →
`tools/list` → `grant_type=refresh_token`): fluxo completo funciona, `expires_in: 2592000`
confirmado na resposta real do servidor.

## Sobre o "token estático" (pedido no prompt) — já existia, aqui está a verdade
O servidor **já suportava** `CORTEX_TOKEN` (bearer estático) em paralelo ao OAuth desde 2026-07-08
(`validToken()` aceita token OAuth OU o bearer fixo). Confirmado vivo: `/root/cortex_mcp_token`
(600, no host) → sem token = 401, com token = 200. **Nada a implementar aqui, já estava feito.**

**Mas isto não resolve o conector do browser.** O conector **web** do claude.ai
(Definições → Conectores → Adicionar personalizado) só suporta **OAuth** — não existe campo para
colar um bearer token nessa UI. O token estático serve para **outros** clientes (Claude Desktop via
config MCP local, chamadas API diretas) — não para a ligação que estava a cair. Por isso a correção
real é a de cima (TTL), não uma troca de OAuth por token no browser. Prefiro dizer isto claramente
a mandar um passo que não existe na interface.

## 🖥️ O único passo humano que sobra
O redeploy reinicia o container → limpa a sessão OAuth em memória que estava ativa → a ligação
atual do conector "Córtex Bora" no claude.ai **vai pedir reconexão uma única vez** (confirmado:
uma chamada de teste nesta sessão devolveu "requires re-authorization" logo a seguir ao deploy).

1. Abre claude.ai → **Definições → Conectores**.
2. Em **Córtex Bora**, se aparecer a marcar erro/desconectado, clica para reconectar
   (ou remove e volta a **Adicionar conector personalizado** com a mesma URL:
   `https://cortex.srv1786862.hstgr.cloud`).
3. Autoriza uma vez (ecrã de consentimento OAuth automático).
4. A partir daqui: sessão válida por **30 dias**, não 1h. Não devias ver "cai" outra vez tão cedo.

## Risco residual (honesto, não escondido)
Estado OAuth continua **em memória** (não em disco) — só se perde outra vez se o **container
reiniciar** (reboot da VPS, crash, `docker restart`). Isso não aconteceu em 8 dias
(`RestartPolicy=unless-stopped`, `RestartCount=0`), portanto não é o caso comum. Persistência em
disco ficaria para uma iteração futura só se isto voltar a acontecer por essa via — não implementada
agora para não adicionar complexidade/risco sem sinal real de que é precisa.

## Ficheiros tocados
- `.claude/.ai/cortex-mcp/server.mjs` (local + `/root/cortex-mcp/server.mjs` no VPS, com backup
  `server.mjs.bak_<timestamp>` no host antes de sobrescrever)
- Este ficheiro (documentação)

## Zona
Verde — infra/Córtex, nunca dinheiro/DB/RLS. Nenhuma zona protegida tocada.
