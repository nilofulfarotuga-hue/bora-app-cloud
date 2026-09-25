# BLOCO C — Radar de dinheiro do batedor

Data: 2026-09-02 · VPS `srv1786862.hstgr.cloud` · contentor `hermes-agent-fvnc-hermes-agent-1`
Portão de RAM: nível leve (400 MB). Medido no PC do Danilo: **1055 MB disponíveis** — acima do portão, avançou-se sem ressalvas. Na VPS: 2801 MB disponíveis no arranque.

---

## 1. O que ficou feito

| Ponto | Estado |
|---|---|
| **C1** — `/opt/data/scripts/radar-dinheiro.sh`, quarta 09:00 Lisboa | Feito |
| **C2** — inventário do Danilo dentro do prompt | Feito |
| **C3** — regras duras de rejeição + exemplo negativo fixo | Feito |
| **C4** — fontes grátis, máx. 10 vídeos, 60 dias, 5 pesquisas | Feito, **com uma ressalva grande** (ver ponto 4) |
| **C5** — Telegram + ficheiro `AAAA-SS.md` + `cortex_reportar` + `RADAR_FORCE=1` | Feito |

Nada foi tocado no `radar-ia.sh`, no tecto de 1 € do Gemini, no loop, no carteiro ou em zona de dinheiro real. Nada foi instalado no PC do Danilo.

---

## 2. Provas literais

### Prova 1 — o ficheiro da semana existe em disco, com data e hora

```
$ docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 ls -la --time-style=full-iso /opt/data/radar-dinheiro/
total 172
drwxr-xr-x  2 hermes hermes  4096 2026-09-02 22:35:24.647243414 +0000 .
drwx------ 52 hermes hermes 12288 2026-09-02 22:40:42.149296651 +0000 ..
-rw-r--r--  1 hermes hermes 50026 2026-09-02 22:37:08.990607283 +0000 2026-36.md
-rw-r--r--  1 hermes hermes 48719 2026-09-02 22:14:25.293249540 +0000 _antes-de-forcar-2026-36-20260902-231522.md
-rw-r--r--  1 hermes hermes 48719 2026-09-02 22:14:25.293249540 +0000 _antes-de-forcar-2026-36-20260902-233524.md
-rw-r--r--  1 hermes hermes  2770 2026-09-02 22:40:13.957208905 +0000 _execucoes.log
-rw-r--r--  1 hermes hermes   315 2026-09-02 22:37:08.986607269 +0000 _ja_enviados.txt
```

Isto responde directamente à lição `licao-pendente-ordem-20260820185129-46bd` do Córtex (um radar anterior afirmou ter escrito `/opt/data/radar/AAAA-SS.md` e o ficheiro não existia). Aqui o ficheiro existe, tem 50 026 bytes, e o conteúdo está colado no ponto 3 — lido de volta com `cat`, não afirmado.

As duas cópias `_antes-de-forcar-*` provam o `cp -p`: ambas mantêm o carimbo original **22:14:25.293249540**, idêntico ao do ficheiro que copiaram. Forçar não destruiu a semana.

### Prova 2 — a tarefa agendada

```
$ crontab -l | grep -n 'radar-dinheiro'
34:0 8,9 * * 3 docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 bash /opt/data/scripts/radar-dinheiro.sh >> /root/radar-dinheiro.log 2>&1 # radar-dinheiro-semanal

$ crontab -l | grep -n '^CRON_TZ='
7:CRON_TZ=Europe/Lisbon
```

**O `CRON_TZ` não foi duplicado** — confirmei antes de escrever que já existia (linha 7) e a linha nova, no fim do ficheiro, herda-o. As outras duas ocorrências da palavra no crontab são comentários meus, não declarações.

Porquê `0 8,9 * * 3` e não `0 9 * * 3`: dispara às 08 **e** às 09, e a guarda dentro do script só deixa passar as 09 do relógio de Lisboa. Assim a hora fica certa mesmo que o `CRON_TZ` não pegue e o cron corra em UTC (verão +01 ou inverno +00, cai sempre uma das duas nas 09:00 de Lisboa). É a mesma técnica do `radar-ia.sh`.

Guarda testada a sério, não por dedução:

```
$ docker exec -u hermes ... bash /opt/data/scripts/radar-dinheiro.sh; echo rc=$?
rc=0
[2026-09-02T23:40:13+0100] SALTA: sao 23 em Lisboa, o radar de dinheiro so corre as 09
```

Backup do crontab antes de mexer: `/root/crontab.bak-antes-radar-dinheiro-20260902-221318`.

### Prova 3 — o primeiro relatório forçado, inteiro

Está colado na íntegra no ponto 3 deste documento.

### Prova 4 — `bash -n` limpo **e** corrida real

```
$ bash -n /opt/data/scripts/radar-dinheiro.sh && echo 'bash -n LIMPO (rc=0)'
bash -n LIMPO (rc=0)
```

Corrida real, fim a fim (`_execucoes.log`):

```
[2026-09-02T23:35:24+0100] copia de seguranca antes de forcar: /opt/data/radar-dinheiro/_antes-de-forcar-2026-36-20260902-233524.md
[2026-09-02T23:35:24+0100] START radar-dinheiro semana 2026-36 (force=1)
[2026-09-02T23:35:24+0100] material recolhido: 341 linhas, 8 videos (0 com legenda real), 4 artigos
[2026-09-02T23:35:24+0100] prompt montado: 52318 bytes, canario=RADAR-DINHEIRO-CANARIO-2026-36
[2026-09-02T23:35:24+0100] MODELO OK: gemini/gemini-3.6-flash (rc=0, 2615 bytes)
[2026-09-02T23:35:24+0100] arquivo gravado: /opt/data/radar-dinheiro/2026-36.md (50026 bytes)
[2026-09-02T23:35:24+0100] TELEGRAM rc=0 resposta={ "success": true, "platform": "telegram", "chat_id": "6731890157", "message_id": "5892", "note": "Sent to telegram home channel (chat_id: 6731890157)", "mirrored": true }
[2026-09-02T23:35:24+0100] CORTEX_REPORTAR: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"{\"ref\":\"ref-c6708f\",\"estado\":\"POR REVER\",\"pagina\":\"hermes-reporte\",\"nota\":\"Registado. Fica [POR REVER] até a Claude.ai confirmar.\"}"}]}}
[2026-09-02T23:35:24+0100] FIM radar-dinheiro semana 2026-36
```

Os três destinos do C5 têm cada um a sua prova de **efeito**, não de invólucro: `message_id: 5892` (Telegram aceitou e devolveu id), `ref-c6708f` (o Córtex gravou e devolveu a referência), e o ficheiro de 50 026 bytes em disco.

### Prova 5 — a armadilha das aspas está desarmada

A ordem avisa que aspas duplas dentro de `PROMPT="…"` partem o script e que o `bash -n` **não** apanha isso. O prompt é montado por here-doc citado (`<<'PROMPTFIM'`), onde as aspas são texto literal. Mas isso é desenho, não prova. A prova é o canário: a última linha do prompt leva um código único, e perguntou-se ao agente qual era, com o ficheiro de prompt que o próprio script gerou:

```
bytes do prompt que o script montou: 52318
primeira linha : Es o batedor (le a tua SOUL.md). E o RADAR DE DINHEIRO semanal do Danilo, semana 2026-36.
ultima linha   : (fim do material. codigo desta corrida: RADAR-DINHEIRO-CANARIO-2026-36)
--- pergunta ao agente qual e o codigo que esta na ULTIMA linha do prompt ---
RADAR-DINHEIRO-CANARIO-2026-36
```

52 318 bytes entram, e a última linha sai do outro lado. O prompt chega inteiro.

### Prova 6 — o que era para não tocar não foi tocado

```
$ md5sum /opt/data/scripts/radar-ia.sh
4269b9e06e65aa7be98befd0593b6053  /opt/data/scripts/radar-ia.sh     (igual ao de antes de eu começar)
-rwxr-xr-x 1 hermes-exec hermes-exec 10075 Aug 21 16:10 radar-ia.sh  (data original intacta)

$ jobs.json:  Radar de IA semanal (batedor) | 0 8,9 * * 0 | enabled=true | next=2026-09-06T08:00:00+00:00
```

---

## 3. O primeiro relatório forçado, inteiro

```
---
id: radar-dinheiro-2026-36
tema: radar-dinheiro
estado: atual
data: 2026-09-02
autor: batedor (Hermes, perfil batedor)
gerado_em: 2026-09-02T23:35:24+0100
modelo: gemini/gemini-3.6-flash
---

# Radar de dinheiro — semana 2026-36

Radar de dinheiro da semana 2026-36.
ja tens: o Bora App na Guarda com o codigo BEMVINDO.
ja tens: sites de clientes como Guarda FC, Jai Agarwal e Ouro e Prata.
ja tens: TVDE ao volante do Ioniq 5.
ja tens: Hermes na VPS com leitor de paginas e pesquisas gratis.
ja tens: computador Acer de 4 GB de RAM.

Primeiro achado. O que e: o video do canal Aprendendo Sites aborda a prospecao de sites
focada nas vendas do comercio local. Porque funciona: a IA simplificou a criacao, logo os
clientes procuram quem traga contactos reais. Como aplicar na Guarda em tres passos ou menos:
passo um, escolher comercios sem site; passo dois, mostrar o portfolio do Guarda FC e Jai
Agarwal; passo tres, propor uma pagina simples de captacao. Quanto custa: zero euros. Qual e
o risco: perder tempo com clientes desinteressados.
Link: https://www.youtube.com/watch?v=QTZzDvcWvwg

Segundo achado. O que e: o artigo da Rock Content ensina a criar uma campanha de marketing de
quatro semanas com meta SMART. Porque funciona: acoes com prazo fixo criam um pico de vendas
superior a divulgacao continua. Como aplicar na Guarda em tres passos ou menos: passo um,
definir meta de registos no Bora App; passo dois, lancar campanha de quatro semanas com o
codigo BEMVINDO; passo tres, medir a conversao semanal. Quanto custa: zero euros. Qual e o
risco: habituar o publico a promocoes permanentes.
Link: https://analoghq.ai/blog/br/campanha-de-marketing-2/

Terceiro achado. O que e: o artigo da Rock Content ensina a mapear a jornada do cliente para
eliminar pontos de atrito. Porque funciona: corrigir falhas onde o cliente desiste aumenta
vendas sem gastar em publicidade. Como aplicar na Guarda em tres passos ou menos: passo um,
rever o caminho do cliente no Bora App ou TVDE; passo dois, detetar onde desistem; passo tres,
simplificar o pedido e destacar o codigo BEMVINDO. Quanto custa: zero euros. Qual e o risco:
alterar o fluxo com base em palpites.
Link: https://analoghq.ai/blog/br/mapa-da-jornada-do-cliente/

Kiwify do Gustavo de Castro e Hora de Negocios ficou de fora por ser esquema de afiliados.
Hostinger dos Nerds de Negocios ficou de fora por exigir ferramentas pagas e afiliados.
Publicacoes do Eleazar FEX ficaram de fora por ser conteudo em espanhol.
Delivery do Victor Rocha ficou de fora por exigir anuncios pagos no Meta Ads.
Google Anuncios ficou de fora por exigir orcamento de trafego pago.

Veredito do batedor: esta semana vale a pena fechar sites na Guarda com o portfolio real e
lancar uma campanha de quatro semanas do Bora App com o codigo BEMVINDO, sendo o resto so
barulho de afiliados e anuncios pagos.
```

O relatório cumpriu o que a ordem manda: declarou o inventário antes de sugerir, entregou menos de 5 achados (3, porque só 3 prestavam), cada um com o que é / porque funciona / 3 passos / custo / risco / link, rejeitou 5 coisas com a razão escrita em cada linha (afiliados, ferramentas pagas, espanhol, anúncios pagos), e fechou com o veredito. Texto corrido, PT-PT, sem emojis nem markdown.

**Verificação de fonte:** o link `analoghq.ai` levantou suspeita — o modelo diz "Rock Content" e o domínio é outro. Fui ver: o feed `rockcontent.com/br/blog/feed` aponta mesmo para `analoghq.ai` (mudaram de marca). O link responde `HTTP 200`. O modelo não inventou.

---

## 4. O que falhou, com a causa real

### As legendas do YouTube não vêm nesta VPS. Ponto.

A ordem manda `yt-dlp --write-auto-sub --skip-download`. **Não funciona a partir deste IP** e isso não é contornável com truques de configuração. O YouTube responde a qualquer extracção:

```
ERROR: [youtube] lGFnV-z4B4g: Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies
```

Foi tudo testado antes de desistir, e falhou tudo:

- **8 clientes do extractor**: `tv`, `android`, `ios`, `mweb`, `web_embedded`, `android_vr`, `tv_simply`, `web_safari` — todos com o mesmo erro.
- **yt-dlp actualizado** de 2026.06.09 para **2026.08.19** (dentro do contentor, no venv do agent-reach; nunca no PC do Danilo) — mesmo erro.
- **`api/timedtext` do YouTube e do `video.google.com`**: 0 bytes.
- **6 instâncias Invidious**: a lista de legendas vem, o ficheiro vem com o cabeçalho `WEBVTT` e **36 bytes**, ou seja vazio.
- **readpage (Jina) na página do vídeo**: o YouTube devolve-lhe `401 Unauthorized`.

O `yt-dlp` **não** está instalado no PC do Danilo — a actualização foi só no contentor, como a ordem exige.

**O que fiz em vez de fingir.** O script continua a tentar a legenda primeiro (é o que a ordem pede, e volta a funcionar sozinho no dia em que o bloqueio cair, ou se alguém puser um ficheiro de cookies em `$YT_COOKIES`). Quando a legenda não vem, usa a **descrição completa** do vídeo. E cada vídeo no material leva escrito de que profundidade é o texto:

```
origem do texto: LEGENDA (transcricao automatica do proprio video)
origem do texto: DESCRICAO do video (SEM legenda: o YouTube bloqueou a transcricao a partir deste servidor)
```

O prompt manda o modelo olhar para essa etiqueta e deitar fora o achado se a descrição não chegar para perceber a ideia. **O modelo nunca recebe uma descrição disfarçada de legenda**, e o log da corrida diz o número em cru: `8 videos (0 com legenda real)`. Esta é a rede de segurança visível — não mascara nada, declara-se.

### O SearXNG está partido para este uso (falso positivo apanhado)

Ia usar o SearXNG local para os artigos. Devolvia `HTTP 200` e `10 resultados` — parecia bom. Fui ver o conteúdo:

```
--- "vender sem trafego pago"  ->  zhidao.baidu.com/question/13311321.html (fórum chinês)
--- "ganhar dinheiro criando sites"  ->  microsoft.com/en-us
--- "marketing grupos facebook 2026"  ->  support.microsoft.com/sk-SK/... (esloveno)
```

Resultados sem relação nenhuma com a pergunta. O `duckduckgo` está em CAPTCHA e o `bing` devolve lixo. Foi exactamente o que a ordem avisa — *um 200 não prova nada por dentro* — e por isso o SearXNG ficou de fora. Os artigos vêm de **feeds RSS de imprensa PT e BR** (ECO, Marketeer, E-commerce News, PME Magazine, Exame, Rock Content, Dinheiro Vivo — os 7 que testei e responderam com itens), e o texto integral dos mais próximos do tema é puxado pelo **readpage (r.jina.ai)**, que funciona sem chave. Na corrida: **4 artigos lidos por inteiro**.

O `s.jina.ai` (pesquisa) ficou de fora porque devolve `401 AuthenticationRequiredError` — exige chave. Pela regra C3, isso não é grátis e não entra.

### O tecto do Gemini foi batido, e o script não parou

Na segunda corrida:

```
[2026-09-02T23:15:22+0100] MODELO gemini/gemini-3.6-flash: TECTO DE GASTO BATIDO — segue para o proximo, o tecto de 1 EUR fica como esta
```

Como a ordem manda: **não parei, não pedi para subir o tecto de 1 €**, ficou registado onde aconteceu. Também apanhei `Please retry in 44s` (limite de ritmo do plano gratuito) durante a prova do canário — fiz essa prova com o segundo modelo da cadeia (`nemotron-3-ultra-free`), que respondeu.

### Uma corrida perdeu-se a meio (causa encontrada)

A segunda corrida morreu durante a chamada ao segundo modelo, sem log de erro. Não foi OOM (o `dmesg` só tem mortes de Agosto) nem reinício do contentor (`restarts=0`): foi o `docker exec -d` a largar o processo. Relançada com `setsid nohup` e correu até ao fim. Fica dito porque saltou um passo antes de eu o repetir.

### Um detalhe cosmético que corrigi

O log escrevia `8 videos (0\n0 com legenda real)` — o número partido em duas linhas. Causa: `grep -c` já imprime `0` quando não encontra, mas sai com `rc=1`, e o `|| echo 0` acrescentava um segundo zero. Corrigido com `head -1`. Vê-se a diferença entre a corrida das 23:15 (partido) e a das 23:35 (limpo).

---

## 5. Como o script está feito

`/opt/data/scripts/radar-dinheiro.sh` (23 KB, `hermes-exec:hermes-exec`, 755) — copiado do modelo do `radar-ia.sh` e adaptado.

- **Guardas**: só às 09 de Lisboa, só à quarta, e só uma vez por semana. `RADAR_FORCE=1` passa por cima — e nesse caso faz `cp -p` automático do ficheiro da semana antes de o sobrescrever, com data e hora no nome. Cinto e suspensórios: mesmo que alguém force sem pensar, a semana anterior não se perde.
- **Fontes** (todas grátis, nenhuma com chave): pesquisa do YouTube via Invidious (escolhe a primeira instância que devolva mesmo itens, não a que devolva 200), as 5 pesquisas de partida da ordem, janela de 60 dias, máximo 10 vídeos, vídeos entre 90 s e 80 min; feeds RSS PT/BR; readpage nos 4 artigos mais próximos do tema.
- **Prompt**: here-doc citado, inventário completo do Danilo, as 5 regras de rejeição mais a regra do hardware (Acer Celeron N4500, 4 GB, sem GPU — rejeita GPU local, ComfyUI e modelos na máquina), o exemplo negativo fixo do "Pulso Social" de 02/09 (fica a ideia dos 3 textos e 3 imagens, cai a extensão), a proibição de chamar "grátis" ao que pede chave ou cartão, só português, e ignorar investimento, cripto, apostas e tarefas pagas.
- **Cadeia de modelos** explícita e registada: `gemini-3.6-flash` → `nemotron-3-ultra-free` → `hy3-free`. Sem resposta boa de nenhum, avisa no Telegram e sai com erro — não inventa sucesso.
- **Livro de bordo** `_ja_enviados.txt` com os links que **saíram mesmo** para o Telegram, para não repetir na semana seguinte. Não se lê isto dos `.md` do arquivo: cada `.md` leva colado o material bruto com dezenas de links que nunca foram enviados, e foi assim que o `radar-ia` repetiu um achado a 2026-08-20.

---

## PARA O DANILO

Nada aqui precisa das mãos dele — o radar está a correr sozinho e já mandou o primeiro relatório ao Telegram. Duas coisas só para ele saber, quando lhe der jeito:

1. **As legendas dos vídeos não vêm.** O YouTube bloqueia o servidor. O radar funciona à mesma, mas em vez da transcrição do que a pessoa diz, lê a descrição escrita por baixo do vídeo — que é menos fundo. Se um dia isto interessar mesmo, resolve-se com um ficheiro de cookies de uma conta YouTube posto no servidor (o script já o aceita na variável `YT_COOKIES`, é só apontar). **Não é urgente e não vale uma sessão só para isso** — os artigos, que são lidos por inteiro, já estão a dar a maior parte do miolo.

2. **O tecto de 1 € do Gemini bateu uma vez** a meio dos testes desta noite. Não mexi nele, como mandado. O radar tem mais dois modelos atrás e passou à frente sozinho. Fica registado só para ele saber que aconteceu.
