# Costura fechada — Claude.ai cria ordem nova (2026-07-09)

A última costura do loop está **fechada**: o Claude.ai (chat web) passa a **criar ordens novas**
(não só editar páginas) via a ferramenta nova `cortex_nova_ordem`. O ciclo agora arranca do início
real — eu (Claude.ai) crio a ordem → campainha → executor(PC) → juiz → aprovada/corrigir.

## ✅ O que foi feito
- **`cortex_nova_ordem` adicionada** ao `cortex-mcp` (VPS) + **repo sincronizado**
  (`.claude/.ai/cortex-mcp/server.mjs`, +26/-1). Backup do server.mjs/Dockerfile no VPS antes de tocar.
- **Redeploy** via `deploy.sh` (idempotente: mesmo token, issuer, mount, traefik, `--user 10000`).
  Saúde OK: `401` sem token, `200 {"ok":true,"oauth":true,"write_enabled":true}` com token.

## ✅ Testado (curl com token estático — sem simular o Claude Code)
1. **`tools/list`** → aparece `cortex_nova_ordem` (agora 7 ferramentas). ✅
2. **Zona vermelha** (`tarefa` = "alterar pricing_service… comissão") →
   `{"id":null,"roteado":"aprovacao_admin","zona":"vermelha","pid":"prop-…"}` e **0 ordens na fila**.
   Nunca entra no loop. ✅
3. **Zona verde** (com `orquestracao_enabled=false` p/ não gastar executor) → criou
   `ordem-20260709054707-4ca6.md` na fila **e a campainha disparou a partir da tool**
   (`campainha.log: evento em ordem-…-4ca6.md -> carteiro`); o carteiro **respeitou o kill switch**
   (`T5: kill switch OFF`) e a ordem ficou `aberta`. ✅ Depois: limpo + `enabled=true` restaurado.

## Como funciona (desenho)
`cortex_nova_ordem({ tarefa, zona?, teto_tentativas? })`:
- **id novo:** `ordem-<YYYYMMDDHHMMSS>-<rand4>`.
- **zona:** auto-detetada por palavras-chave (regex ≥ cobertura do carteiro T3); `zona` manual só
  **escala** para vermelha, **nunca desce** vermelha→verde (segurança).
- **`teto_tentativas`:** aceite no schema mas **IGNORADO** — o sistema fixa sempre **5**.
- **verde** → escreve `orquestracao/<id>.md` (estado: aberta, autor: claude.ai, criada, tarefa) →
  o ficheiro na fila **dispara a campainha inotify** (mesmo dir montado; confirmado
  `cortex-brain` do host = `/brain` no container). Devolve o `id` p/ `cortex_ler(id)`.
- **vermelha** → **não escreve na fila**; grava na fila de aprovação do admin (`proposals.jsonl`,
  igual a `cortex_propor`) e devolve `roteado: aprovacao_admin`.

## 📋 Ordem de teste — pronta p/ o Danilo disparar via Claude.ai (ao vivo)
Da próxima vez, no chat web, chamar **exatamente**:

> **`cortex_nova_ordem`** com `tarefa` =
> `"Cria o ficheiro orquestracao_selftest_2.md na raiz do projeto bora_app com a data e hora atuais em UTC e devolve o caminho completo. Nao faças git commit nem git push."`

Esperado: devolve `id: ordem-…`, estado `aberta`, zona `verde`. Depois `cortex_ler(id)` mostra
`aberta → executando → respondida → aprovada`, e chega Telegram "terminada e aprovada". (Como
`orquestracao_enabled=true`, corre sozinha.) É o 1.º ciclo **começado 100% pelo Claude.ai**.

## 🚦 Travas (mantidas, sem exceção)
- **Zona vermelha nunca no loop** — testado (roteia p/ admin). Além disto o carteiro T3 e os hooks
  da Trava no PC continuam a bloquear.
- **Teto 5 fixo** (o param é ignorado). **T5** `orquestracao_enabled` respeitado — testado (fica aberta).
- Redeploy não mexeu em zona vermelha nenhuma; `cortex-mcp` só toca `.md`, nunca DB/dinheiro/shell.

## ⚠️ Bugs / riscos (mesmo fora do scope)
1. **Reset de OAuth no restart:** recriar o container zera o estado OAuth em memória (clients/tokens).
   O conector web do claude.ai **re-autentica via DCR** na próxima ligação; o token estático
   (Desktop/API) persiste. Custo real: pode ser preciso reconectar o conector uma vez.
2. **Ordens não vão p/ git:** de propósito — a fila é efémera; `cortex_nova_ordem` faz `writeFileSync`
   simples (sem commit), ao contrário de `cortex_escrever` (que faz push). A campainha vê o disco,
   não o git, por isso funciona à mesma.
3. **Herança de ontem (honestidade):** o `selftest-t5` ficou `aberta` na fila (a minha limpeza de
   ontem falhou-o) e o **cron de fallback executou-o às 23:17** (criou `t5.txt` inócuo, juiz aprovou).
   Hoje limpei `selftest-t5.md` + `t5.txt`. Prova que o fallback funciona, mas também que ordens de
   teste esquecidas **correm mesmo** — limpar sempre a fila a seguir a testes.
4. **`tarefa` numa linha:** o `cortex_nova_ordem` colapsa `\n`→espaço (o carteiro lê `tarefa:` numa
   linha). Ordens muito longas/multi-passo ficam numa linha só — ok para comandos; para planos
   grandes, referir uma página do Córtex em vez de meter tudo na tarefa.

Ficheiros: `.claude/.ai/cortex-mcp/server.mjs` (repo, sincronizado com o VPS).
Anterior: `loop_ligado.md`. Backups VPS: `/root/cortex-mcp/server.mjs.bak_*`.
