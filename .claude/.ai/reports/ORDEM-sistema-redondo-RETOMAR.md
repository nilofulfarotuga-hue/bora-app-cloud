# ORDEM — sistema-redondo-2026-08-20 · RETOMAR EM SESSÃO NOVA

> Escrito 2026-08-21 pela sessão de 13h, que fica por aqui de propósito.
> **Lê isto todo antes de tocar em nada.** O que está aqui foi verificado ao vivo,
> não é suposição.

---

## CORRECÇÃO À ORDEM ORIGINAL (confirmada pelo Danilo)

Onde a ordem diz *"edita a alma do batedor em `~/.hermes/profiles/batedor/`"*,
**lê `/opt/data/scripts/radar-ia.sh` na VPS.**

Porquê: o `~` do contentor é `/opt/data`. O perfil só tem `profile.yaml` com **2
linhas de descrição** (decorativo), `workspace/` vazio e nenhum `AGENTS.md`. A
tarefa `Radar de IA semanal (batedor)` (id `69cd23e1dcef`, cron `0 8,9 * * 0`)
tem `prompt` **vazio** e corre `script: radar-ia.sh`.

Quem editar o `profile.yaml` não muda nada e o batedor continua a recomendar o
Agent-Reach.

## COMO CHEGAR LÁ

```
ssh -i ~danil/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud
docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 sh -lc '<comando>'
```

Sempre `-u hermes`. Ficheiro: `/opt/data/scripts/radar-ia.sh` — 203 linhas,
8996 bytes, `-rwxr-xr-x hermes hermes`, mexido a 2026-08-20 20:36.

Correr à mão: `RADAR_FORCE=1 bash /opt/data/scripts/radar-ia.sh`

---

## BLOCO 1 — as três regras (POR FAZER)

**Primeiro: cópia de segurança.** É ficheiro vivo.
```
cp -p /opt/data/scripts/radar-ia.sh /opt/data/scripts/radar-ia.sh.bak_20260821
```

**Regra A — INVENTÁRIO.** Nunca recomendar o que ele já tem; se um achado já cá
estiver, dizer "já tens" e passar ao seguinte. Inclui pelo menos: Claude Code Pro,
OpenCode Go, Hermes com os 3 bots (fiscal, batedor, escriba), **Agent-Reach**
(saiu recomendado DUAS vezes), agent-skills, Impeccable, Córtex/carteiro/juiz,
Supabase, Stripe, Firebase, Codemagic.

**Regra B — PREÇO.** Proibido pôr na gaveta "poupar dinheiro" algo que exige chave
paga ou subscrição. Se exigir: diz o preço e classifica noutra frente. Preço não
verificável na fonte → escrever "preço não confirmado".

**Regra C — HARDWARE.** PC de 4 GB, VPS de 4 GB com 1 core. Nada que não caiba lá
pode ser apresentado como "alternativa local". O achado não se esconde — só não se
vende como usável.

**Prova exigida:** correr com `RADAR_FORCE=1` e colar a saída literal a mostrar
**pelo menos uma rejeição por inventário e uma por preço**. Sem isso não conta.

> Nota: com `RADAR_FORCE=1` a semana 34 é reescrita (`2026-34.md`). Se quiseres
> guardar a versão actual antes, copia-a — há já um `_arquivo-corrida1-2026-34.md`
> a mostrar que o script arquiva a corrida anterior.

## BLOCO 2 — FECHADO ✅

```
### ls -la /opt/data/radar/
drwxr-xr-x  2 hermes hermes  4096 Aug 20 20:36 .
-rw-r--r--  1 hermes hermes 16785 Aug 20 20:33 2026-34.md
-rw-r--r--  1 hermes hermes 16596 Aug 20 20:18 _arquivo-corrida1-2026-34.md
-rw-r--r--  1 hermes hermes  1186 Aug 20 20:33 _execucoes.log
-rw-r--r--  1 hermes hermes   368 Aug 20 20:36 _ja_enviados.txt
### escrevivel pelo hermes?  SIM
```

Existe, é do `hermes`, é escrevível, e o script faz `mkdir -p` na mesma.

**Semana 33: NÃO dá para gerar — decidido, não reabrir.** O `radar-collect.sh`
puxa feeds **ao vivo** (`hnrss.org/frontpage`, `simonwillison.net/atom/everything`,
`huggingface.co/blog/feed.xml`), sem janela de datas. E o `_execucoes.log` **começa
a 2026-08-20** — nunca houve corrida da 33. Gerar agora e chamar-lhe "2026-33"
seria pôr as notícias desta semana com o nome da passada: prova falsa. Fica assim.

Isto também explica os "dois relatórios no Telegram": foram **ambos da semana 34**
(21:17 e a forçada das 21:32), não 33 + 34.

## BLOCO 3 — anti-mentira (POR FAZER)
Proposta `prop-carteiro-ordem-20260811160435-2540` no Córtex, parada desde 11/08.
Ler pelo Córtex, executar o que ainda faz sentido, e para cada medida escrever:
**aplicada / já existia / dispensada**, com o motivo. O padrão de prova material já
está em vigor — o que estiver coberto marca-se "já existia" e segue.

## BLOCO 4 — curador do Córtex (POR FAZER)
`_tools/cortex_nightly.py` não corre desde 8 de Julho; o `_debt.md` ainda diz
"primeira geração parcial". Descobrir porquê (cron morto? caminho errado? erro
apanhado?), corrigir, correr uma vez com `--report` e colar o número real de
páginas em dívida.

## BLOCO 6 — Agent-Reach (APURAR SEM LIGAR)
Já está em `/opt/data/.agent-reach` dentro do contentor. Fazer **grep no código
por endpoints e por chaves de API**. Se só lê páginas por HTTP ou Chrome local →
é grátis, resolve o buraco do `web_extract` (sem solução desde 11/08 porque
firecrawl/tavily/exa exigem chave paga) → **liga**. Se aparecer chamada a serviço
pago → **para e diz**.

## BLOCO 5 — Open Design (REGRA QUE DECIDE SOZINHA)
Só liga se a geração correr por uma chave que ele **já tem**: `GEMINI_API_KEY`
(projeto SEM faturação) ou o conector higgsfield. **Chave nova ou cartão: nem
pensar.** Se o Open Design só funcionar com serviço pago próprio, fica de fora e
escreve-se porquê.

**PROIBIDO** instalar a aplicação de desktop (Electron + Next.js + Node 24 não cabe
em 4 GB). Só o servidor MCP.

---

## REGRAS DA CASA (não negociáveis)

- Prova material: quando o artefacto fica na VPS, a prova é a saída literal de
  `docker exec ... ls -la` ou `cat` — **nunca** um caminho do disco do PC. Foi
  esse o erro que matou a ordem anterior.
- Um bloco de cada vez, fechado antes do seguinte. Nada em paralelo.
- Sem `git push`. Sem tocar em dinheiro, pagamentos, dispatch, pricing, RLS nem
  `versionCode`.
- Não mexer na cadeia de modelos (`gemini-3.6-flash` → `nemotron-3-ultra-free` →
  `hy3-free`). PROIBIDOS `deepseek-v4-flash-free` e `mimo-v2.5-free`. `glm-5.2`
  em 429 até ~08/09.
- Gemini: usar sempre o secret `GEMINI_API_KEY` (projeto sem faturação). Nunca uma
  chave nova. Agosto fechou em crédito contra 103 EUR em Julho — a chave é que
  cobra, não o projeto.
- Se um bloco tocar em dinheiro, autenticação ou Stripe: **para e reporta**.
- Já ligados e a NÃO mexer: os 5 crons (`auto_close_no_show_reservations`,
  `reservas_pro_expire_lists`, `reservas_pro_pending_alert`,
  `reservas_pro_morning_summary`, `wallet_overdue_alerts`).

## NÃO REABRIR (decidido)
DeepSeek Harness · DeepSeek Reasonix (chave paga) · Qwen Code (tier grátis acabou
em Abril) · LiteRT/Gemma em Raspberry Pi (não tem) · awesome-claude-skills
(catálogo) · Qwen 3.8 27B (não corre em 4 GB — anotado para quando for barato).

## FECHO
1. Relatório num ficheiro único, uma secção por bloco: feito / prova literal / por fazer.
2. Uma linha no `e2e_log` com `fluxo=sistema-redondo-2026-08-20`.
3. Digest curto para o Danilo colar no @BoraHermesbot.
4. `/ctx doctor` e `/ctx stats`.

---

## DÍVIDA SEPARADA, DE OUTRA MISSÃO

**Prova no ecrã da persistente do TVDE a parar** (o bug das 06:41: ele recusou e o
telemóvel continuou a tocar). O código está corrigido e publicado na **540**; falta
só a captura. O telemóvel ficou sem bateria — precisa de **carregador de parede**,
o cabo do PC estava a descarregá-lo.

Como provar: app na 540, criar oferta de teste só para a conta dele
(`4f61dd31-5e9e-4a7c-a557-7d53d2ceded7`), recusar, e mostrar que a notificação
morre e o som para.
