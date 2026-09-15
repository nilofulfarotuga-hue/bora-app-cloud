# BLOCO A — Redes atrasadas: publicar à mão + confirmar horários — 2026-09-05

> Sessão `social-media`, motor Sonnet 5. Investigação real na VPS (`root@srv1786862.hstgr.cloud`,
> chave `id_ed25519_vps`) — **não** usei Postiz (infra `infra/postiz-pc/` está parada/PC-only e
> não é o mecanismo real). O que corre de verdade é um conjunto de scripts bash/python em
> `/opt/data/scripts/` + `/opt/data/social/` dentro do contentor `hermes-agent-fvnc-hermes-agent-1`,
> publicando direto na Graph API do Meta (Facebook + Instagram), com log próprio em
> `/opt/data/social/log.md` e guardas `.loja-feita-<data>` / `.story-feita-<data>` /
> `.reel-feito-<data>` / `.carrossel-feito-<data>`. Isto diverge da memória do agente
> (que descrevia Postiz como o pipeline) — corrigido no handoff ao Bibliotecário no fim.

---

## ⚠️ Correção à premissa do pedido (prova, não suposição)

O pedido descrevia "ontem 2026-09-03" como o dia todo perdido por permissão do `.env`,
corrigido às 22h12 de ontem. **Os dados reais da VPS não confirmam essa data.** Prova:

- Guardas de sucesso existentes: `.loja-feita-2026-09-03`, `.story-feita-2026-09-03`,
  `.reel-feito-2026-09-03`, `.feito-2026-09-03` — **todas presentes**, ou seja o dia
  03/09 **completou** (confirmado também por `/opt/data/social/log.md`: loja do dia
  McDonald's publicada em FB+IG+stories às 13:00, reel em FB+IG às 11:13–11:31, story
  das 19h30 em FB+IG às 20:30, todos com HTTP 200 e IDs reais).
- Quem **não tem** guarda de hoje é **2026-09-04**: sem `.loja-feita-2026-09-04`, sem
  `.story-feita-2026-09-04`, sem `.reel-feito-2026-09-04`. Prova direta em
  `/root/social-loja.log`, `/root/social-reel.log`, `/root/social-story.log`,
  `/root/social-grupos.log` — cada um com a linha `Permission denied` no `/opt/data/.env`
  como única saída, exatamente a causa-raiz descrita no pedido, só que **datada de hoje**.
- `/opt/data/.env`: `stat` mostra `Modify: 2026-09-04 22:00:13 UTC` (23:00 Lisboa) — ou
  seja a correção de permissão (que o relatório `TUDO-04-09-NOITE-2026-09-04.md`, Bloco A,
  já documentava parcialmente às 09:30 de hoje) continuou a ser mexida até às 22h de hoje.

**Conclusão:** o dia realmente por publicar é **2026-09-04** (hoje), não 03/09. Tratei
o pedido pelo espírito ("o que ficou por sair por causa da permissão do `.env`, publica
agora à mão") e fui atrás do que a prova mostra estar mesmo em falta.

---

## O que já estava PUBLICADO antes de eu mexer (nenhuma ação necessária)

| Item | Prova |
|---|---|
| Carrossel "13 coisas que o Bora faz" (hoje 07:35, catch-up de sessão anterior) | FB: https://www.facebook.com/1230974540107256_122096801547453644 · IG: https://www.instagram.com/p/Dc2wf_Glx8U/ |
| Resumo dos grupos de Facebook (18h30) → é um resumo por **Telegram** ao Danilo, não um post — ver `social-grupos-resumo.sh` linha 1-4: "a mensagem de fim de tarde ao Danilo, no Telegram, com o que saiu hoje nos grupos" | HTTP 200, `message_id 6022`, canal `6731890157`. Conteúdo real citado: 3 posts em grupos hoje de manhã, com links `https://www.facebook.com/groups/1510534389226500/posts/4623369631276278` e `https://www.facebook.com/groups/511781988466174/posts/1093887370255630` |

---

## O que EU tentei publicar agora, à mão (prova literal)

### 1. Loja do dia (McDonald's, slot 12h00 → guarda ainda em falta)
Comando real corrido:
```
docker exec -u hermes -e SOCIAL_FORCE=1 hermes-agent-fvnc-hermes-agent-1 \
  bash /opt/data/scripts/social-loja-do-dia.sh
```
Resultado em `/opt/data/social/log.md`:
```
[2026-09-04T23:55:17+0100] FACEBOOK FALHOU (HTTP 400): {"error":{"message":"Cannot call API
for app 1598568711343805 on behalf of user 122097657423468264","type":"OAuthException","code":200}}
[2026-09-04T23:55:15+0100] loja-do-dia: FIM: mcdonalds-guarda NAO saiu nas duas redes (rc=1).
facebook=nao instagram=nao
```
**não publicado: token/app do Meta bloqueado (ver bloqueio abaixo) — não é falha de permissão de
ficheiro, é um erro novo e diferente.**

### 2. Reel (slot 18h00 → guarda ainda em falta)
```
docker exec -u hermes -e SOCIAL_FORCE=1 hermes-agent-fvnc-hermes-agent-1 \
  bash /opt/data/scripts/social-reel.sh
```
Resultado:
```
[2026-09-04T23:56:12+0100] reel: FB VIDEO falhou: {"error":{"message":"Cannot call API for app
1598568711343805 on behalf of user 122097657423468264","type":"OAuthException","code":200}}
```
**não publicado: mesmo bloqueio de token/app do Meta.**

### 3. Story (slot 19h30 → guarda ainda em falta)
**Não tentei republicar** — já tinha sido tentado pelo cron às 20:30 de hoje e **reprovado pelo
design kit** (gate de marca, não é bug de rede/permissão):
```
kit: FALHA nenhum elemento laranja chapado: a peca nao tem chamada (o selo BEMVINDO ou o botao)
kit: REPROVADO: 1 motivo(s). NAO PUBLICAR.
```
**não publicado: a imagem gerada (pergunta "Jantar de casa ou do restaurante?", sem foto real —
"foto: nenhuma") não tem o selo/CTA laranja obrigatório do design kit.** Mesmo que eu forçasse,
ia bater no mesmo bloqueio de token do Meta a seguir — não vale a pena gastar mais uma tentativa
de imagem sem resolver o bloqueio de baixo primeiro.

---

## 🔴 BLOQUEIO REAL — token/app do Meta, não consigo resolver sozinho

Confirmado com uma chamada crua à Graph API, fora dos scripts:
```
curl "https://graph.facebook.com/v20.0/debug_token?input_token=$META_PAGE_TOKEN&access_token=$META_PAGE_TOKEN"
→ {"error":{"message":"Cannot call API for app 1598568711343805 on behalf of user
122097657423468264","type":"OAuthException","code":200}}
```
O mesmo erro aparece a cada 10 minutos desde as 22h00 de hoje no `ig_auto_dm.py` (cron
`*/10 * * * *`), portanto **não é um acaso de uma chamada só — a app/token está mesmo
bloqueada agora**. As credenciais (`META_PAGE_TOKEN`, `META_PAGE_ID`, `IG_USER_ID`) estão
presentes e legíveis no `.env` (confirmei `grep -c` = 1 para as três) — não é falta de
variável, é o próprio token/app que o Meta está a recusar.

Isto é exatamente o tipo de coisa que a regra da casa reserva para o Danilo: "Ligação de
contas = OAuth oficial feito PELO DANILO". Não tentei renovar nem reautorizar nada — só
diagnostiquei. **Preciso que o Danilo entre em business.facebook.com / developers.facebook.com,
veja o estado da app `1598568711343805` (pode ter caído em revisão, ter o Business Manager
desligado da página, ou o token de página ter expirado) e gere um token novo.** Assim que
o `.env` tiver um `META_PAGE_TOKEN` válido, os três scripts (loja, reel, story) podem ser
corridos outra vez exatamente como acima (`SOCIAL_FORCE=1` para loja/reel, já passou da hora).

---

## Links reais publicados hoje (os que existem)

| Peça | Facebook | Instagram |
|---|---|---|
| Carrossel "coisas que o Bora faz" | https://www.facebook.com/1230974540107256_122096801547453644 | https://www.instagram.com/p/Dc2wf_Glx8U/ |
| Post em grupo — Amigos do distrito da Guarda | https://www.facebook.com/groups/1510534389226500/posts/4623369631276278 | — |
| Post em grupo — OLX Guarda | https://www.facebook.com/groups/511781988466174/posts/1093887370255630 | — |

**Loja do dia, reel e story de hoje: não publicado — bloqueio de token/app do Meta (acima).**

---

## Horários de hoje/amanhã no crontab (Europe/Lisbon) — confirmados

```
0 12 * * *      social-loja-do-dia.sh     # loja do dia
30 19 * * *     social-story.sh           # story diário
0 18 * * 1,3,5  social-reel.sh            # reel seg/qua/sex
0 18 * * 2,4,6  social-carrossel.sh       # carrossel ter/qui/sáb
0 11 * * 0      social-semana.sh          # grelha domingo
0 9  * * 1      social-medir.sh           # relatório segunda
30 18 * * *     social-grupos-resumo.sh   # resumo grupos → Telegram
*/10 * * * *    ig_auto_dm.py             # DM automático Instagram
```
Todas as 8 linhas estão **ativas** (não comentadas) e herdam `CRON_TZ=Europe/Lisbon`
declarado uma vez, linha 7 do crontab.

**Achado à parte, honesto:** comparando a hora do cron com a hora real em que o script
regista o primeiro log do dia, há um **atraso sistemático de ~1 hora** nos últimos 2 dias
(loja marcada para 12:00 → primeira linha de log às 13:00, tanto em 03/09 como em 04/09;
story marcada para 19:30 → log às 20:30 nos dois dias). Não mexi nisto — não foi pedido e
não quis arriscar o crontab às 23h56 sem seguimento. Fica registado para quem for investigar
o `CRON_TZ`: os horários **disparam sozinhos**, só que ~1h depois do que o nome da linha diz.
Enquanto o bloqueio de token não for resolvido pelo Danilo, o cron de amanhã (loja 12h/13h,
carrossel/reel se for dia, story 19h30/20h30) vai **voltar a falhar** nas mesmas chamadas —
não é um problema que se resolva sozinho de um dia para o outro.

---

## Regras duras — verificação

- Nenhuma menção a TVDE/motorista/boleia em nada do que vi ou tentei publicar hoje.
- Não criei conta nenhuma, não fiz login OAuth em lado nenhum — só diagnosticei com o
  token que já estava no `.env`.
- Não toquei em Stripe/pagamentos/preços/comissões/`dispatch_engine`/`bora_tokens`.
- Design: não gerei arte nova (o bloqueio de token tornou isso inútil por agora); a única
  peça reprovada foi pelo próprio gate de design kit do sistema (selo laranja em falta),
  não por mim.

## Fim de tarefa

- **Handoff ao `bibliotecario-cerebro`:** a memória do agente `social-media` (arranque
  desta sessão) descreve Postiz como o pipeline real de publicação — **está desatualizada**.
  O pipeline real, vivo e a publicar hoje mesmo, é o conjunto de scripts em
  `/opt/data/scripts/social-*.sh` + `/opt/data/social/` no contentor `hermes-agent-fvnc-hermes-agent-1`
  da VPS `srv1786862.hstgr.cloud`, ligado direto à Graph API do Meta, com log em
  `/opt/data/social/log.md`, guardas `.{loja,story,reel,carrossel}-{feita,feito}-<data>`,
  e override `SOCIAL_FORCE=1` para publicar fora da janela de hora. Postiz/`infra/postiz-pc/`
  parece ter sido abandonado a favor deste pipeline mais direto — vale confirmar com o Danilo
  e atualizar `permanente/semantica/` (não escrevo lá; só o Bibliotecário).
- **Bloqueio para o Danilo (PARA O DANILO):** token/app do Meta (`app 1598568711343805`)
  a recusar todas as chamadas desde pelo menos as 22h00 de hoje — preciso que reautorizes
  em business.facebook.com/developers.facebook.com e gere um `META_PAGE_TOKEN` novo no
  `/opt/data/.env` da VPS. Sem isso, loja do dia, reel e story continuam a falhar amanhã
  também, mesmo com o crontab a disparar certinho.
