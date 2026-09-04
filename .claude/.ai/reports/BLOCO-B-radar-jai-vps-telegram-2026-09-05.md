# BLOCO B — radar-jai: diagnóstico do silêncio + mudança para a VPS (2026-09-05)

> Executor: devops-ci (agente autónomo). Projeto tocado: `C:\BoraLocal\projetosflutter\radar-jai`
> (projeto separado do `bora_app` — nada de dinheiro/Stripe/dispatch/pricing envolvido).

## TAREFA 1 — Diagnóstico do silêncio de 2 dias

Danilo apontou 3 causas possíveis. Nenhuma delas é a causa real, confirmado com saída literal:

### (a) Agendador do Windows — NÃO é a causa
```
schtasks /query /fo LIST /v | Select-String -Pattern "RadarJai" -Context 0,15
```
As 4 tarefas (`RadarJai-Pedidos`, `-Noticias`, `-Diario`, `-Semanal`) mostravam
`Last Result: 0` (sucesso) com execuções recentes reais em 04/09/2026
(08:30:01, 23:31:01, 23:46:01). Só `RadarJai-Semanal` nunca tinha corrido — mas é
esperado: só corre à 2ª feira 09:00 e ainda não tinha passado uma.

### (b) PC desligado — NÃO é a causa
O PC esteve ligado e as tarefas correram sozinhas hoje (prova acima). O modo é
`Logon Mode: Interactive only` — ou seja, **existe sim** uma dependência estrutural
de o PC estar ligado com a sessão do Danilo aberta (é a "nota honesta" que já estava
no `README.md` do próprio projeto) — mas essa dependência não causou o silêncio
*desta semana*, porque o PC esteve ligado.

### (c) TELEGRAM_TOKEN vazio — FALSO. Já tinha sido corrigido pelo próprio Danilo
`radar-jai/.env` já tinha `TELEGRAM_TOKEN` e `TELEGRAM_CHAT_ID` preenchidos desde
**2026-09-01** — confirmado pelo próprio histórico git do projeto:
```
0fae53e actualização do relatório: Telegram ligado (token do Hermes via VPS)
```
e pelo comentário no `.env`: *"Telegram do Danilo — copiado do Hermes na VPS
(2026-09-01, a pedido dele)"*. É o mesmo bot/token do Hermes.

**Confirmado ao vivo** que o token é válido e aponta para o chat certo (chamada real
à API do Telegram, não suposição):
```
getMe   -> {"ok":true,"result":{"id":8288018149,"username":"BoraHermesbot", ...}}
getChat -> {"ok":true,"result":{"id":6731890157,"first_name":"Danilo","last_name":"Fulfaro","type":"private"}}
```
E os logs do próprio radar-jai (`logs/tarefa-diario.log`) mostram entrega bem
sucedida (o código verifica `resp.get("ok")` da API, não só HTTP 200 — não é o
falso-positivo clássico) em **09-02, 09-03 e 09-04**, todos os dias:
```
[2026-09-04 08:30:02] [mod6_fila] aviso entregue por Telegram
[2026-09-04 08:30:02] [mod6_fila] ok: digest entregue via telegram
```

### Conclusão honesta do diagnóstico
Nenhuma das 3 causas apontadas se confirma tecnicamente — o sistema estava, no
mecanismo, a entregar avisos reais todos os dias. Não consigo provar por que o
Danilo não viu esses avisos (não há como reproduzir "o que ele não notou"). A
explicação mais provável, sem certeza: o mesmo chat privado do `@BoraHermesbot`
recebe também heartbeat, carteiro, social, etc. — o digest do radar pode ter-se
perdido no meio de muitas outras mensagens automáticas, ou o conteúdo (mesmos itens
pendentes recicladas dia após dia) pareceu "nada de novo" e passou despercebido.
Isto fica registado como hipótese, não como facto provado.

O risco estrutural real que valia a pena resolver — apontado corretamente pelo
Danilo mesmo sem ser a causa desta semana — é a dependência de o PC estar ligado.
Foi isso que a Tarefa 2 resolveu.

---

## TAREFA 2 — Mudança para a VPS + reaproveitamento do bot já existente

### O que já estava feito (por Danilo, 2026-09-01)
`.env` já usava o **mesmo bot/token do Hermes** (`@BoraHermesbot`, chat privado do
Danilo) — não foi preciso pedir credencial nova nenhuma. Confirmado com `getMe`/
`getChat` acima.

### Bugs corrigidos antes de mudar de SO (Windows → Linux)
`radar/comum.py` tinha 2 dependências Windows-only que fariam o arranque
**rebentar logo na primeira linha do `correr.py`** em qualquer distro Linux:
1. `ram_disponivel_mb()` usava `ctypes.windll.kernel32.GlobalMemoryStatusEx` —
   não existe em Linux. Corrigido: em Linux lê `/proc/meminfo` (`MemAvailable`),
   mantendo o comportamento Windows intacto (guarda de `sys.platform == "win32"`).
2. `GUARDA_FC_CLONE` era um `Path` Windows hardcoded
   (`C:/BoraLocal/projetosflutter/guarda-fc-site`). Passou a ler de
   `ENV.get("GUARDA_FC_CLONE")` com o mesmo valor Windows como default — não muda
   nada no PC, permite apontar para outro caminho na VPS.

Testado no PC depois da mudança (continua a funcionar em Windows):
```
RAM_MB= 1845
GUARDA_FC_CLONE= C:\BoraLocal\projetosflutter\guarda-fc-site
```
**Nota:** estas alterações ficaram só no working tree do `radar-jai` (não foram
commitadas — o repo desse projeto é local, sem remote, e a regra é só commitar
quando pedido).

### Onde a VPS já corre coisas (investigado antes de mexer)
`.claude/.ai/hermes/orquestrador-carteiro/deploy/DEPLOY.md` e
`ponte-pc/hermes-bridge/README.md` deram o caminho real:
`ssh root@srv1786862.hstgr.cloud` (chave `~/.ssh/id_ed25519_vps`) — SSH direto,
**não** via Tailscale SSH (esse pedia reautenticação interativa por browser, o que
seria uma tarefa manual proibida de pedir ao Danilo sem necessidade real).
Confirmado com `whoami`/`hostname`/`uptime` reais antes de mexer em nada.

A VPS já corre scripts Python puros diretamente no host (fora de Docker), como
`/opt/data/rotinas/manha.py|cobrador.py|guarda_noturno.py` via cron root com
`/usr/bin/python3` — segui exatamente este padrão para o radar-jai, em vez de
meter dentro do container do Hermes (`hermes-agent-fvnc-hermes-agent-1`), que é
zona do Hermes/carteiro e não precisa de mais uma carga lá dentro.

### O que foi feito na VPS
1. Projeto inteiro copiado via `tar` + `scp` (excluindo `.git`, `__pycache__`) para
   `/root/radar-jai/` — inclui `radar.db` (histórico real), `.env` (Gmail +
   Telegram), código, `REGRAS.md`. Verificado que os acentos em PT sobreviveram
   (`REGRAS.md` lido de volta com "missão", "é", "arranque" intactos).
2. `chown -R root:root /root/radar-jai` (dono correto para o cron do root).
3. 4 linhas novas no `crontab -l` do root (herdam o `CRON_TZ=Europe/Lisbon` já
   declarado uma vez no topo do crontab, o mesmo padrão usado por outros blocos
   Bora — `radar-dinheiro-semanal`, `social-*`):
   ```
   */15 * * * * cd /root/radar-jai && /usr/bin/python3 correr.py pedidos   >> logs/cron.log 2>&1 # radar-jai-pedidos
   0 * * * *    cd /root/radar-jai && /usr/bin/python3 correr.py noticias  >> logs/cron.log 2>&1 # radar-jai-noticias
   30 8 * * *   cd /root/radar-jai && /usr/bin/python3 correr.py diario    >> logs/cron.log 2>&1 # radar-jai-diario
   0 9 * * 1    cd /root/radar-jai && /usr/bin/python3 correr.py semanal   >> logs/cron.log 2>&1 # radar-jai-semanal
   ```
   Mesma cadência que as tarefas do Windows tinham.
4. Windows Scheduled Tasks **desativadas** (não apagadas — reversível):
   ```
   schtasks /change /tn "RadarJai-Pedidos"  /disable   -> SUCCESS, Status: Disabled
   schtasks /change /tn "RadarJai-Noticias" /disable   -> SUCCESS, Status: Disabled
   schtasks /change /tn "RadarJai-Diario"   /disable   -> SUCCESS, Status: Disabled
   schtasks /change /tn "RadarJai-Semanal"  /disable   -> SUCCESS, Status: Disabled
   ```
   (evita duplicar avisos e divergência entre 2 `radar.db` diferentes — a VPS passa
   a ser a única fonte de verdade a partir de agora).

### O que ficou no PC / degradado — e porquê (não forçado para a VPS sem razão)
1. **Ganchos de jogo do Guarda FC** (`mod3_gancho`, clone local de
   `guarda-fc-site`) — esse repo GitHub é **privado**
   (`git ls-remote` → `fatal: could not read Username for 'https://github.com'`).
   Não vale a pena criar uma deploy key só para esta fonte secundária: o código já
   trata a ausência com elegância (`jogos.json` não existe → `mod3_gancho` devolve
   `0 ganchos propostos`, sem rebentar, com log claro). Confirmado no teste real
   abaixo. Se o Danilo quiser mesmo os ganchos de jogo na VPS, falta só uma deploy
   key GitHub de leitura — decisão dele, não crítico.
2. **Ollama local (`qwen2.5:7b`)** para polir rascunhos (`radar/llm.py`) — já era
   "nice-to-have" mesmo no PC (se o Ollama não estivesse a correr lá, também caía
   no template determinístico — o design sempre previu isto). Não instalado na
   VPS: puxaria vários GB e carga de CPU/RAM extra ao lado dos 11 containers já
   ativos (Hermes, buzz, cortex-mcp, etc.). Os rascunhos continuam a ser escritos,
   só com o template em vez de LLM — não bloqueia nada.

### PROVA OBRIGATÓRIA — corrida real na VPS, aviso real recebido

Corrida real (`python3 correr.py tudo`), dados de produção, feita na VPS:
```
[2026-09-04 22:57:00] [guardas] linha vermelha verificada (12 marcadores) — módulos [...] ok
[2026-09-04 22:57:00] [correr] perfil=tudo RAM_disponivel=2609MB
[2026-09-04 22:57:11] [llm] indisponível (URLError...) — sigo com template
[2026-09-04 22:57:11] [mod1_vigia] ok: 6 menções novas; 5 páginas capturadas; 1 emails de pedido de link na fila
[2026-09-04 22:57:14] [mod2_cacador] ok: 0 pedidos lidos; 0 encaixam no Jai
[2026-09-04 22:57:14] [mod3_gancho] git pull: fatal: cannot change to '...guarda-fc-site': No such file or directory
[2026-09-04 22:57:14] [mod3_gancho] ok: 0 ganchos propostos na fila (0 jogos no calendário)
[2026-09-04 22:57:14] [mod4_conteudo] ok: sem material novo em factos/ — nada a propor
[2026-09-04 22:57:14] [mod5_medidor] ok: semana 2026-S36: 250 menções (0 citam o site); gráfico actualizado
[2026-09-04 22:57:14] [mod6_fila] aviso entregue por Telegram
[2026-09-04 22:57:14] [correr] perfil tudo terminado (0 falhas)
EXIT=0
```
6 menções novas reais capturadas por RSS/Gmail — não é um teste fictício, é o
próprio radar-jai a processar dados reais e a meter 1 item novo na fila.

Prova literal da entrega no Telegram — chamado o mesmo caminho de código que o
`mod6_fila` usa (`_resumo()` a ler a fila real da base), resposta crua da API do
Telegram capturada:
```json
{
  "ok": true,
  "result": {
    "message_id": 6052,
    "from": {"id": 8288018149, "is_bot": true, "username": "BoraHermesbot"},
    "chat": {"id": 6731890157, "first_name": "Danilo", "last_name": "Fulfaro", "type": "private"},
    "date": 1788562657,
    "text": "[PROVA radar-jai->VPS] 📡 RADAR JAI — fila de aprovação\n• 14 emails de pedido de link prontos\n• 1 medição semanal\n• 1 propostas de post/nota\n\nVer e aprovar: python ver-fila.py   (na pasta radar-jai)"
  }
}
```
Texto gerado a partir do estado real da fila (14 pendentes de pedidos de link, 1
medição, 1 post) — não uma string inventada para o teste.

### Regras respeitadas
Nada de tráfego artificial, nada de posição no Google, nada em massa, nada de
Wikipédia, nada enviado em nome do Jai sem aprovação — o `guardas.py` correu antes
de cada módulo e confirmou os 12 marcadores de `REGRAS.md` intactos
(`linha vermelha verificada (12 marcadores)` nos logs acima). O único envio real
foi o aviso **ao Danilo** (dono), que `REGRAS.md` explicitamente permite
("avisar o dono não é publicar em nome do Jai").

## Resultado
- Diagnóstico: nenhuma das 3 causas apontadas se confirmou — a entrega já estava
  a funcionar; risco estrutural real era a dependência do PC ligado.
- radar-jai agora corre na VPS (`/root/radar-jai`, cron root, mesma cadência),
  usando o bot/token já existente do Hermes — zero credencial nova pedida ao
  Danilo.
- Tarefas do Windows desativadas (reversíveis).
- Prova real e literal de entrega no Telegram anexada acima.
